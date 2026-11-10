import AppKit

// MARK: - Single instance

/// One instance per session. The bundle identifier survived the Systemstatus →
/// tinyStats rename, so older builds and other copies of the bundle count too.
enum SingleInstance {
    static let bundleIdentifier = "local.hsb.systemstatus"

    /// Yields to any instance launched before (or with) this one; when a launch
    /// date is unknown it yields as well, preferring no duplicate over a second icon.
    static func shouldYield(ownLaunch: Date?, otherLaunches: [Date?]) -> Bool {
        otherLaunches.contains { other in
            guard let other, let ownLaunch else { return true }
            return other <= ownLaunch
        }
    }

    /// PID of the running instance this launch should give way to, if any.
    static func runningInstance() -> pid_t? {
        let own = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != own.processIdentifier && !$0.isTerminated }
        guard shouldYield(ownLaunch: own.launchDate, otherLaunches: others.map(\.launchDate)) else { return nil }
        return others.first?.processIdentifier
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate {
    static let notchDefaultsKey = "showAtNotch"
    let status = NSStatusBar.system.statusItem(withLength: MenuBarIndicators.size.width + 8)
    let metrics = Metrics()
    let content = IslandContentView(width: IslandLayout.menuBarWidth, hasBattery: Metrics.hasBattery)
    private var lastSample = Sample()
    private lazy var presenter = IslandPresenter(content: content)
    private lazy var wingPanel = WingPanel()
    private var wing: NotchWing?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = status.button else { return }
        UserDefaults.standard.register(defaults: [Self.notchDefaultsKey: true])
        button.setAccessibilityLabel("tinyStats")
        button.target = self
        button.action = #selector(statusItemClicked)
        content.onNotchToggle = { [weak self] enabled in
            UserDefaults.standard.set(enabled, forKey: Self.notchDefaultsKey)
            self?.updatePlacement()
        }
        content.setMetricLayout(.stored(in: .standard, hasBattery: Metrics.hasBattery))
        content.onLayoutChange = { [weak self] layout in
            layout.save(to: .standard)
            self?.refreshIndicator()
        }
        wingPanel.wingView.setAccessibilityLabel("tinyStats")
        wingPanel.wingView.onClick = { [weak self] in self?.toggleDetails() }
        presenter.onProgress = { [weak self] progress in
            guard let self else { return }
            // Only join the lower corner; the compact wing never changes width.
            // A card floating under the status item leaves the wing alone.
            let attached = presenter.view.layout?.isFloating == false
            wingPanel.wingView.attach = attached ? Choreography.attach(progress) : 0
            let corner = attached && progress > 0 ? presenter.view.layout?.wingCorner(at: progress) : nil
            wingPanel.wingView.corner = corner.map { NSSize(width: $0.radius, height: $0.rise) }
        }
        presenter.onPresentedChange = { [weak self] shown in
            let highlighted = shown && self?.presenter.view.layout?.isFloating == true
            // After the button's own mouse-up handling, which resets its highlight.
            DispatchQueue.main.async { self?.status.button?.highlight(highlighted) }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensSlept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        updatePlacement()
        startSampling()
    }

    @objc private func screensChanged(_ notification: Notification) { updatePlacement() }

    /// Nobody can read a dark display; sampling resumes when it wakes.
    @objc private func screensSlept(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    @objc private func screensWoke(_ notification: Notification) {
        metrics.restartBaselines()
        startSampling()
    }

    private func startSampling() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        // Lets macOS coalesce wake-ups; a reading a tenth of a second late looks the same.
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Re-evaluates the connected displays; the status item returns when no notch is left.
    private func updatePlacement() {
        let available = NotchWing.firstAvailable(on: NSScreen.screens)
        let enabled = UserDefaults.standard.bool(forKey: Self.notchDefaultsKey)
        content.setNotchOption(available: available != nil, enabled: enabled)
        presenter.close(animated: false)
        wing = enabled ? available : nil
        if let wing {
            wingPanel.place(wing)
            wingPanel.orderFrontRegardless()
            status.isVisible = wing.needsStatusItem(screens: NSScreen.screens.map(\.frame),
                                                    separateSpaces: NSScreen.screensHaveSeparateSpaces)
        } else {
            wingPanel.orderOut(nil)
            status.isVisible = true
        }
    }

    private func sample() {
        lastSample = metrics.sample()
        content.update(lastSample)
        refreshIndicator()
    }

    /// Also runs on a layout change, so a new choice shows without waiting for the next sample.
    private func refreshIndicator() {
        let layout = content.metricLayout
        let summary = Format.summary(lastSample, hasBattery: Metrics.hasBattery)
        let image = MenuBarIndicators.image(bars: layout.top.map { $0.fraction(lastSample) },
                                            readout: layout.menuBar.readout(lastSample))
        status.button?.image = image
        wingPanel.wingView.indicator = image
        for view in [status.button, wingPanel.wingView] as [NSView?] {
            view?.toolTip = summary
            view?.setAccessibilityValue(summary)
        }
    }

    /// Island geometry for the clicked source and its clickable rect. The status
    /// item opens under itself, except on the notched display, where it joins the wing.
    private func currentLayout(fromStatusItem: Bool) -> (IslandLayout, NSRect)? {
        if let wing, !fromStatusItem { return (.notch(wing, height: IslandContentView.height), wing.frame) }
        guard let button = status.button, let window = button.window, let screen = window.screen else { return nil }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        if let wing, screen.frame.contains(wing.frame) {
            return (.notch(wing, height: IslandContentView.height), anchor.union(wing.frame))
        }
        return (.menuBar(anchor: anchor, screen: screen.frame, visibleTop: screen.visibleFrame.maxY,
                         height: IslandContentView.height), anchor)
    }

    @objc private func statusItemClicked() { toggleDetails(fromStatusItem: true) }

    func toggleDetails(fromStatusItem: Bool = false) {
        if presenter.isPresented {
            presenter.close()
        } else if let (layout, source) = currentLayout(fromStatusItem: fromStatusItem) {
            presenter.open(layout: layout, source: source)
        }
    }
}
