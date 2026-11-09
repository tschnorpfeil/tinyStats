import AppKit
import IOKit
import Darwin
import CoreFoundation

// MARK: - Metrics

struct NetworkRates {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
}

final class Metrics {
    private var prevCPU: (user: UInt32, sys: UInt32, idle: UInt32, nice: UInt32)?
    private var prevNets: [String: (in: UInt64, out: UInt64)]?
    private var prevNetTime: TimeInterval?

    func cpu() -> Double? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        defer {
            let u = info.cpu_ticks.0, s = info.cpu_ticks.1, i = info.cpu_ticks.2, n = info.cpu_ticks.3
            prevCPU = (u, s, i, n)
        }
        guard let p = prevCPU else { return nil }
        let du = Double(info.cpu_ticks.0 &- p.user)
        let ds = Double(info.cpu_ticks.1 &- p.sys)
        let di = Double(info.cpu_ticks.2 &- p.idle)
        let dn = Double(info.cpu_ticks.3 &- p.nice)
        let total = du + ds + di + dn
        return total > 0 ? (du + ds + dn) / total : nil
    }

    func gpu() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var busy = 0.0
        var found = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let stats = props["PerformanceStatistics"] as? [String: Any],
                  let n = stats["Device Utilization %"] as? NSNumber else { continue }
            let raw = n.doubleValue
            guard raw.isFinite, raw >= 0, raw <= 100 else { continue }
            busy += raw / 100.0
            found = true
        }
        return found ? min(1.0, busy) : nil
    }

    func ram() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory
        return total > 0 ? min(1.0, Double(used) / Double(total)) : nil
    }

    func network() -> NetworkRates? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            prevNets = nil
            prevNetTime = nil
            return nil
        }
        defer { freeifaddrs(ifaddr) }
        var current: [String: (in: UInt64, out: UInt64)] = [:]
        var ptr = ifaddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let ifa = cur.pointee
            guard let namePtr = ifa.ifa_name,
                  let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let name = String(validatingUTF8: namePtr), name.hasPrefix("en") else { continue }
            if let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                current[name] = (UInt64(data.pointee.ifi_ibytes), UInt64(data.pointee.ifi_obytes))
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard !current.isEmpty else {
            prevNets = nil
            prevNetTime = nil
            return nil
        }
        guard let prev = prevNets, let prevTime = prevNetTime, now > prevTime else {
            prevNets = current
            prevNetTime = now
            return nil
        }
        if Set(prev.keys) != Set(current.keys) {
            prevNets = current
            prevNetTime = now
            return nil
        }
        var counterDropped = false
        for name in current.keys {
            guard let p = prev[name], let c = current[name] else { continue }
            if c.in < p.in || c.out < p.out { counterDropped = true; break }
        }
        if counterDropped {
            prevNets = current
            prevNetTime = now
            return nil
        }
        let dt = now - prevTime
        guard dt > 0 else {
            prevNets = current
            prevNetTime = now
            return nil
        }
        var dIn = 0.0
        var dOut = 0.0
        for (name, c) in current {
            let p = prev[name]!
            dIn += Double(c.in - p.in)
            dOut += Double(c.out - p.out)
        }
        prevNets = current
        prevNetTime = now
        return NetworkRates(downloadBytesPerSecond: dIn / dt, uploadBytesPerSecond: dOut / dt)
    }
}

// MARK: - Popover

final class StatusViewController: NSViewController {
    private let cpuValue = NSTextField(labelWithString: "—")
    private let gpuValue = NSTextField(labelWithString: "—")
    private let ramValue = NSTextField(labelWithString: "—")
    private let downValue = NSTextField(labelWithString: "—")
    private let upValue = NSTextField(labelWithString: "—")
    let notchToggle = NSButton(checkboxWithTitle: "An Notch anzeigen", target: nil, action: nil)
    private var contentStack: NSStackView?
    var onQuit: (() -> Void)?
    var onNotchToggle: ((Bool) -> Void)?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 280))
        let title = NSTextField(labelWithString: "Systemstatus")
        title.font = .systemFont(ofSize: 14, weight: .semibold)

        func separator() -> NSView {
            let line = NSBox()
            line.boxType = .separator
            return line
        }

        func row(_ name: String, symbol: String, value: NSTextField) -> NSView {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            icon.contentTintColor = .secondaryLabelColor
            icon.translatesAutoresizingMaskIntoConstraints = false
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 13)
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            value.alignment = .right
            value.setContentCompressionResistancePriority(.required, for: .horizontal)
            value.setAccessibilityLabel(name)
            let spacer = NSView()
            let stack = NSStackView(views: [icon, label, spacer, value])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 9
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                stack.heightAnchor.constraint(equalToConstant: 26),
                spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12)
            ])
            return stack
        }

        let ramRow = row("RAM ≈", symbol: "memorychip", value: ramValue)
        ramRow.toolTip = "Geschätzte Belegung: aktive, verdrahtete und komprimierte Speicherseiten. Kein Speicherdruck."
        let rows = NSStackView(views: [
            row("CPU", symbol: "cpu", value: cpuValue),
            row("GPU", symbol: "square.3.layers.3d", value: gpuValue),
            ramRow,
            separator(),
            row("Download", symbol: "arrow.down", value: downValue),
            row("Upload", symbol: "arrow.up", value: upValue)
        ])
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 5

        let note = NSTextField(labelWithString: "RAM ≈ Schätzung")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        let quit = NSButton(title: "Beenden", target: self, action: #selector(quitClicked))
        quit.bezelStyle = .rounded
        quit.controlSize = .small
        quit.font = .systemFont(ofSize: 11)
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        let footer = NSStackView(views: [note, NSView(), quit])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        notchToggle.target = self
        notchToggle.action = #selector(notchToggleClicked)
        notchToggle.font = .systemFont(ofSize: 12)
        notchToggle.isHidden = true
        let stack = NSStackView(views: [title, rows, separator(), notchToggle, footer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        view = container
        contentStack = stack
        updatePreferredSize()
    }

    private func updatePreferredSize() {
        guard let contentStack else { return }
        preferredContentSize = NSSize(width: 300, height: contentStack.fittingSize.height + 30)
    }

    @objc private func quitClicked() { onQuit?() }
    @objc private func notchToggleClicked() { onNotchToggle?(notchToggle.state == .on) }

    /// Shows the notch checkbox only while the primary display has a usable notch.
    func setNotchOption(available: Bool, enabled: Bool) {
        loadViewIfNeeded()
        notchToggle.state = enabled ? .on : .off
        notchToggle.isEnabled = available
        guard notchToggle.isHidden == available else { return }
        notchToggle.isHidden = !available
        updatePreferredSize()
    }

    func updateMetrics(cpu: Double?, gpu: Double?, ram: Double?, net: NetworkRates?) {
        loadViewIfNeeded()
        cpuValue.stringValue = Self.percent(cpu)
        gpuValue.stringValue = Self.percent(gpu)
        ramValue.stringValue = Self.percent(ram)
        downValue.stringValue = Self.formatRate(net?.downloadBytesPerSecond)
        upValue.stringValue = Self.formatRate(net?.uploadBytesPerSecond)
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return "—" }
        return "\(Int((min(1, max(0, fraction)) * 100).rounded())) %"
    }

    static func formatRate(_ bps: Double?) -> String {
        guard let bps, bps.isFinite, bps >= 0 else { return "—" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bps
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = unit == 0 ? 0 : 1
        formatter.maximumFractionDigits = unit == 0 ? 0 : 1
        let number = formatter.string(from: NSNumber(value: value)) ?? "—"
        return "\(number) \(units[unit])"
    }
}

// MARK: - Menu bar indicators

// Fixed order: CPU, GPU, RAM; network rates are bytes per second.
enum MenuBarIndicators {
    static let size = NSSize(width: 88, height: 22)
    static let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    static func compactRate(_ bytes: Double?, locale: Locale = .current) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        guard bytes < 1_000_000_000_000 else { return "≥1T" }
        let units = ["B", "K", "M", "G", "T"]
        var value = bytes
        var index = 0
        // Promote values that would otherwise round to 1000 of the lower unit.
        while value >= 999.5, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = index > 0 && value < 10 ? 1 : 0
        return (formatter.string(from: NSNumber(value: value)) ?? "—") + units[index]
    }

    static func image(cpu: Double?, gpu: Double?, ram: Double?, net: NetworkRates?) -> NSImage {
        let values = [cpu, gpu, ram]
        let download = compactRate(net?.downloadBytesPerSecond)
        let upload = compactRate(net?.uploadBytesPerSecond)
        let image = NSImage(size: size, flipped: false) { _ in
            let labels = ["C", "G", "R"]
            let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.black]
            for (index, value) in values.enumerated() {
                let columnX = CGFloat(index) * 17
                let label = labels[index] as NSString
                let labelWidth = label.size(withAttributes: labelAttributes).width
                label.draw(at: NSPoint(x: columnX + (9 - labelWidth) / 2, y: 4), withAttributes: labelAttributes)
                let track = NSRect(x: columnX + 10, y: 4, width: 5, height: 14)
                if let value, value.isFinite {
                    NSColor.black.withAlphaComponent(0.25).setFill()
                    NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
                    let height = track.height * min(1, max(0, value))
                    if height > 0 {
                        NSColor.black.setFill()
                        let fill = NSRect(x: track.minX, y: track.minY, width: track.width, height: height)
                        NSBezierPath(roundedRect: fill, xRadius: min(1.5, height / 2), yRadius: min(1.5, height / 2)).fill()
                    }
                } else {
                    // Replace the track with a dash; unavailable is distinct from zero.
                    NSColor.black.withAlphaComponent(0.7).setFill()
                    NSRect(x: track.midX - 1.5, y: track.midY - 0.5, width: 3, height: 1).fill()
                }
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: rateFont, .foregroundColor: NSColor.black]
            for (arrow, text, y) in [("↓", download, CGFloat(11)), ("↑", upload, CGFloat(0))] {
                (arrow as NSString).draw(at: NSPoint(x: 52, y: y), withAttributes: attributes)
                let width = (text as NSString).size(withAttributes: attributes).width
                (text as NSString).draw(at: NSPoint(x: 88 - width, y: y), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Notch overlay

enum NotchGeometry {
    static let horizontalPadding: CGFloat = 10
    static let cornerRadius: CGFloat = 8
    static let contentSize = MenuBarIndicators.size
    static let overlayWidth = contentSize.width + 2 * horizontalPadding
    private static let tolerance: CGFloat = 0.5

    /// Overlay frame flush with the notch's right edge, in the same global
    /// coordinates as `screenFrame`. `rightArea` is `NSScreen.auxiliaryTopRightArea`
    /// and `topInset` is `safeAreaInsets.top`. Returns nil without a notch, when
    /// the area is not at the top edge of this screen, or when it is too small.
    /// The area is only unobscured by the notch; other status items may still
    /// occupy it.
    static func overlayFrame(screenFrame: NSRect, rightArea: NSRect?, topInset: CGFloat) -> NSRect? {
        guard let rightArea, !rightArea.isEmpty, !screenFrame.isEmpty,
              topInset.isFinite, topInset >= contentSize.height,
              rightArea.width >= overlayWidth,
              abs(rightArea.maxY - screenFrame.maxY) <= tolerance,
              rightArea.minX > screenFrame.minX + tolerance,
              rightArea.maxX <= screenFrame.maxX + tolerance else { return nil }
        return NSRect(x: rightArea.minX, y: screenFrame.maxY - topInset,
                      width: overlayWidth, height: topInset)
    }

    /// Straight left edge at the notch; only the two right outer corners are rounded.
    static func shapePath(in rect: NSRect, radius: CGFloat = cornerRadius) -> NSBezierPath {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - r, y: rect.minY))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - r))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.close()
        return path
    }

    static func contentRect(in bounds: NSRect) -> NSRect {
        NSRect(x: bounds.minX + horizontalPadding,
               y: bounds.minY + ((bounds.height - contentSize.height) / 2).rounded(),
               width: contentSize.width, height: contentSize.height)
    }
}

/// Draws the existing template indicator white on a black notch extension.
final class NotchOverlayView: NSView {
    var indicator: NSImage? { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NotchGeometry.shapePath(in: bounds).fill()
        guard let indicator, let context = NSGraphicsContext.current else { return }
        let target = NotchGeometry.contentRect(in: bounds)
        context.saveGraphicsState()
        // Tint the template: keep its alpha, replace its color with white.
        context.cgContext.beginTransparencyLayer(in: target, auxiliaryInfo: nil)
        indicator.draw(in: target)
        NSColor.white.setFill()
        target.fill(using: .sourceAtop)
        context.cgContext.endTransparencyLayer()
        context.restoreGraphicsState()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

final class NotchOverlayPanel: NSPanel {
    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: NotchGeometry.overlayWidth, height: 32),
                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        contentView = NotchOverlayView(frame: NSRect(x: 0, y: 0, width: NotchGeometry.overlayWidth, height: 32))
    }

    var overlayView: NotchOverlayView { contentView as! NotchOverlayView }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Keep the frame at the top edge beside the notch instead of below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static let notchDefaultsKey = "showAtNotch"
    let status = NSStatusBar.system.statusItem(withLength: MenuBarIndicators.size.width + 8)
    let metrics = Metrics()
    let popover = NSPopover()
    let vc = StatusViewController()
    private var timer: Timer?
    private lazy var panel = NotchOverlayPanel()
    private var overlayActive = false
    private var lastPopoverClose: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = status.button else { return }
        UserDefaults.standard.register(defaults: [Self.notchDefaultsKey: true])
        button.setAccessibilityLabel("Systemstatus")
        button.target = self
        button.action = #selector(togglePopover)
        vc.onQuit = { NSApp.terminate(nil) }
        vc.onNotchToggle = { [weak self] enabled in
            UserDefaults.standard.set(enabled, forKey: Self.notchDefaultsKey)
            self?.updatePlacement()
        }
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.delegate = self
        panel.overlayView.setAccessibilityLabel("Systemstatus")
        panel.overlayView.onClick = { [weak self] in self?.togglePopover() }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        updatePlacement()
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func screensChanged(_ notification: Notification) { updatePlacement() }

    /// Re-evaluates the primary display (first screen, carrying the menu bar).
    private func updatePlacement() {
        let frame = NSScreen.screens.first.flatMap {
            NotchGeometry.overlayFrame(screenFrame: $0.frame, rightArea: $0.auxiliaryTopRightArea,
                                       topInset: $0.safeAreaInsets.top)
        }
        let enabled = UserDefaults.standard.bool(forKey: Self.notchDefaultsKey)
        vc.setNotchOption(available: frame != nil, enabled: enabled)
        let target = enabled ? frame : nil
        if (target != nil) != overlayActive, popover.isShown {
            popover.performClose(nil)
        }
        overlayActive = target != nil
        if let target {
            panel.setFrame(target, display: true)
            panel.orderFrontRegardless()
            status.isVisible = false
        } else {
            panel.orderOut(nil)
            status.isVisible = true
        }
    }

    private func sample() {
        let cpu = metrics.cpu()
        let gpu = metrics.gpu()
        let ram = metrics.ram()
        let rates = metrics.network()
        vc.updateMetrics(cpu: cpu, gpu: gpu, ram: ram, net: rates)
        let description = "CPU \(StatusViewController.percent(cpu)) · GPU \(StatusViewController.percent(gpu)) · RAM geschätzt \(StatusViewController.percent(ram)) · Download \(StatusViewController.formatRate(rates?.downloadBytesPerSecond)) · Upload \(StatusViewController.formatRate(rates?.uploadBytesPerSecond))"
            .replacingOccurrences(of: "—", with: "Nicht verfügbar")
        let image = MenuBarIndicators.image(cpu: cpu, gpu: gpu, ram: ram, net: rates)
        status.button?.image = image
        status.button?.toolTip = description
        status.button?.setAccessibilityValue(description)
        panel.overlayView.indicator = image
        panel.overlayView.toolTip = description
        panel.overlayView.setAccessibilityValue(description)
    }

    func popoverWillClose(_ notification: Notification) {
        lastPopoverClose = ProcessInfo.processInfo.systemUptime
    }

    @objc func togglePopover() {
        let anchor: NSView? = overlayActive ? panel.overlayView : status.button
        guard let anchor else { return }
        if popover.isShown {
            popover.performClose(anchor)
        } else {
            // A click on the overlay first closes the transient popover; don't reopen it.
            if overlayActive, ProcessInfo.processInfo.systemUptime - lastPopoverClose < 0.3 { return }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
