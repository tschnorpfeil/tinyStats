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
    /// The wing the user asked for, whether or not it currently fits.
    private var wantedWing: NotchWing?
    /// Other apps' status items reach into the wing's place: tinyStats shows
    /// as a status item until there is room again.
    private var crowded = false
    private var roomVotes = 0
    /// Invisible status item left of all others: its right edge is where they begin.
    private var probe: NSStatusItem?
    private var probeAge = 0
    private static let probeName = "RoomProbe"

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

    /// Re-evaluates the connected displays; the status item returns when no
    /// notch is left or the wing would cover other status items.
    private func updatePlacement() {
        let available = NotchWing.firstAvailable(on: NSScreen.screens)
        let enabled = UserDefaults.standard.bool(forKey: Self.notchDefaultsKey)
        content.setNotchOption(available: available != nil, enabled: enabled)
        presenter.close(animated: false)
        wantedWing = enabled ? available : nil
        if wantedWing == nil { crowded = false }
        roomVotes = 0
        placeProbe()
        wing = crowded ? nil : wantedWing
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

    /// Keeps the probe while a wing is wanted. Its saved position is far
    /// beyond the display, which sorts it left of every other status item,
    /// including ones that apps add later. It is 1 pt of nothing; when the
    /// menu bar overflows, macOS hides it first.
    private func placeProbe() {
        guard wantedWing != nil else {
            if let probe { NSStatusBar.system.removeStatusItem(probe) }
            return probe = nil
        }
        guard probe == nil else { return }
        UserDefaults.standard.set(100_000, forKey: "NSStatusItem Preferred Position \(Self.probeName)")
        let item = NSStatusBar.system.statusItem(withLength: 1)
        item.autosaveName = Self.probeName
        item.button?.setAccessibilityElement(false)
        probe = item
        probeAge = 0
    }

    /// Once a second: gives the wing's place to other apps' status items when
    /// they reach it, and takes it back when they leave. Two equal readings in
    /// a row decide, and nothing moves while the details are open.
    private func checkRoom() {
        guard let wantedWing, !presenter.isPresented else { return }
        probeAge += 1
        // A new item reports its place only after the menu bar has laid it out.
        guard probeAge >= 2, let window = probe?.button?.window, let probeScreen = window.screen,
              let wingScreen = NSScreen.screens.first(where: { $0.frame.contains(wantedWing.frame) }),
              // A hidden menu bar (full screen, auto-hide) says nothing about room.
              NSApp.currentSystemPresentationOptions.isDisjoint(with: [.autoHideMenuBar, .hideMenuBar]),
              wingScreen.visibleFrame.maxY < wingScreen.frame.maxY - 0.5,
              // Nor does a covered one (lock screen, screen saver): the wing is then covered as well.
              crowded || wingPanel.occlusionState.contains(.visible) else { return }
        // Not visible although the menu bar is: macOS moved items into its overflow menu.
        var stripWidth: CGFloat? = window.occlusionState.contains(.visible) ? probeScreen.frame.maxX - window.frame.maxX : nil
        // The status item leaves again when the wing returns.
        let ownItemLeaves = !wantedWing.needsStatusItem(screens: NSScreen.screens.map(\.frame),
                                                         separateSpaces: NSScreen.screensHaveSeparateSpaces)
        if crowded, ownItemLeaves, let own = status.button?.window, own.occlusionState.contains(.visible) {
            stripWidth = stripWidth.map { $0 - own.frame.width }
        }
        let fits = WingRoom.fits(wantedWing, screenMaxX: wingScreen.frame.maxX, stripWidth: stripWidth, returning: crowded)
        guard fits == crowded else { return roomVotes = 0 }
        roomVotes += 1
        if roomVotes >= 2 {
            crowded.toggle()
            updatePlacement()
        }
    }

    private func sample() {
        lastSample = metrics.sample()
        content.update(lastSample)
        refreshIndicator()
        checkRoom()
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
