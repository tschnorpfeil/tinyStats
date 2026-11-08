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
    var onQuit: (() -> Void)?

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

        let stack = NSStackView(views: [title, rows, separator(), footer])
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
        preferredContentSize = NSSize(width: 300, height: stack.fittingSize.height + 30)
    }

    @objc private func quitClicked() { onQuit?() }

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

// MARK: - App

final class App: NSObject, NSApplicationDelegate {
    let status = NSStatusBar.system.statusItem(withLength: MenuBarIndicators.size.width + 8)
    let metrics = Metrics()
    let popover = NSPopover()
    let vc = StatusViewController()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = status.button else { return }
        button.setAccessibilityLabel("Systemstatus")
        button.target = self
        button.action = #selector(togglePopover)
        vc.onQuit = { NSApp.terminate(nil) }
        popover.contentViewController = vc
        popover.behavior = .transient
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sample() {
        let cpu = metrics.cpu()
        let gpu = metrics.gpu()
        let ram = metrics.ram()
        let rates = metrics.network()
        vc.updateMetrics(cpu: cpu, gpu: gpu, ram: ram, net: rates)
        let description = "CPU \(StatusViewController.percent(cpu)) · GPU \(StatusViewController.percent(gpu)) · RAM geschätzt \(StatusViewController.percent(ram)) · Download \(StatusViewController.formatRate(rates?.downloadBytesPerSecond)) · Upload \(StatusViewController.formatRate(rates?.uploadBytesPerSecond))"
            .replacingOccurrences(of: "—", with: "Nicht verfügbar")
        status.button?.image = MenuBarIndicators.image(cpu: cpu, gpu: gpu, ram: ram, net: rates)
        status.button?.toolTip = description
        status.button?.setAccessibilityValue(description)
    }

    @objc func togglePopover() {
        guard let button = status.button else { return }
        if popover.isShown {
            popover.performClose(button)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
