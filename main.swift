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

    func cpu() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        defer {
            let u = info.cpu_ticks.0, s = info.cpu_ticks.1, i = info.cpu_ticks.2, n = info.cpu_ticks.3
            prevCPU = (u, s, i, n)
        }
        guard let p = prevCPU else { return 0 }
        let du = Double(info.cpu_ticks.0 &- p.user)
        let ds = Double(info.cpu_ticks.1 &- p.sys)
        let di = Double(info.cpu_ticks.2 &- p.idle)
        let dn = Double(info.cpu_ticks.3 &- p.nice)
        let total = du + ds + di + dn
        return total > 0 ? (du + ds + dn) / total : 0
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

    func ram() -> Double {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory
        return total > 0 ? min(1.0, Double(used) / Double(total)) : 0
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
        // Interface set changed or any counter decreased -> new baseline, no artificial spikes.
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
        return NetworkRates(downloadBytesPerSecond: dIn / dt, uploadBytesPerSecond: dOut / dt)
    }
}

// MARK: - Bar View

final class BarsView: NSView {
    var cpu: Double = 0
    var gpu: Double? = nil
    var ram: Double = 0
    var net: Double = 0

    static let barW: CGFloat = 5
    static let gap: CGFloat = 6
    static let h: CGFloat = 18

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let labels: [(String, Double?)] = [("C", cpu), ("G", gpu), ("R", ram), ("N", net)]
        let x0: CGFloat = 4
        let line = NSColor.labelColor
        let fill = NSColor.labelColor

        for (i, (letter, value)) in labels.enumerated() {
            let x = x0 + CGFloat(i) * (BarsView.barW + BarsView.gap)
            let v = min(1.0, max(0.0, value ?? 0))

            // outline
            let o = NSBezierPath(rect: NSRect(x: x, y: 2, width: Self.barW, height: Self.h - 4))
            o.lineWidth = 1
            line.setStroke()
            o.stroke()

            // fill, bottom to top
            let fillH = (Self.h - 4) * v
            if fillH > 0.5 {
                let f = NSBezierPath(rect: NSRect(x: x, y: 2 + (Self.h - 4) - fillH, width: Self.barW, height: fillH))
                fill.setFill()
                f.fill()
            }

            // label, centered
            let font = NSFont(name: "Menlo", size: 5) ?? NSFont.monospacedSystemFont(ofSize: 5, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: (value ?? 0) > 0.5 ? NSColor.textBackgroundColor : NSColor.labelColor
            ]
            let s = NSAttributedString(string: letter, attributes: attrs)
            let sz = s.size()
            s.draw(at: NSPoint(x: x + (Self.barW - sz.width) / 2, y: (Self.h - sz.height) / 2))
        }
    }
}

// MARK: - Popover

final class StatusViewController: NSViewController {
    private var cpuValue: NSTextField!
    private var gpuValue: NSTextField!
    private var ramValue: NSTextField!
    private var netValue: NSTextField!

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let padding: CGFloat = 16

        let title = NSTextField(labelWithString: "Systemstatus")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        title.textColor = NSColor.labelColor

        let subtitle = NSTextField(labelWithString: "RAM: geschätzte Belegung")
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = NSColor.secondaryLabelColor

        let rows: NSStackView = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        rows.distribution = .fill

        func makeRow(_ label: String) -> (NSView, NSTextField) {
            let l = NSTextField(labelWithString: label)
            l.font = NSFont.systemFont(ofSize: 13)
            l.textColor = NSColor.labelColor

            let v = NSTextField(labelWithString: "—")
            v.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            v.textColor = NSColor.labelColor
            v.alignment = .right

            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(l)
            row.addSubview(v)
            l.translatesAutoresizingMaskIntoConstraints = false
            v.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                l.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                l.topAnchor.constraint(equalTo: row.topAnchor),
                l.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                v.topAnchor.constraint(equalTo: row.topAnchor),
                v.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            ])
            return (row, v)
        }

        let cpuRow = makeRow("CPU")
        let gpuRow = makeRow("GPU")
        let ramRow = makeRow("RAM")
        let netRow = makeRow("Netzwerk")
        cpuValue = cpuRow.1
        gpuValue = gpuRow.1
        ramValue = ramRow.1
        netValue = netRow.1
        rows.addArrangedSubview(cpuRow.0)
        rows.addArrangedSubview(gpuRow.0)
        rows.addArrangedSubview(ramRow.0)
        rows.addArrangedSubview(netRow.0)

        let quitButton = NSButton(title: "Beenden", target: nil, action: nil)
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .regular

        let topStack = NSStackView(views: [title, subtitle])
        topStack.orientation = .vertical
        topStack.alignment = .leading
        topStack.spacing = 4

        let mainStack = NSStackView(views: [topStack, rows, quitButton])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            mainStack.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            mainStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
            container.widthAnchor.constraint(equalToConstant: 280),
            quitButton.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])

        self.view = container
    }

    func updateMetrics(cpu: Double, gpu: Double?, ram: Double) {
        cpuValue.stringValue = "\(Int((cpu * 100).rounded())) %"
        gpuValue.stringValue = gpu.map { "\(Int(($0 * 100).rounded())) %" } ?? "Nicht verfügbar"
        ramValue.stringValue = "\(Int((ram * 100).rounded())) %"
        netValue.stringValue = "Noch nicht verbunden"
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let status = NSStatusBar.system.statusItem(withLength: 64)
    let view = BarsView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
    let metrics = Metrics()
    let popover = NSPopover()
    let vc = StatusViewController()
    private(set) var networkRates: NetworkRates?

    func applicationDidFinishLaunching(_ n: Notification) {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.view.cpu = self.metrics.cpu()
            self.view.gpu = self.metrics.gpu()
            self.view.ram = self.metrics.ram()
            let rates: NetworkRates? = self.metrics.network()
            self.networkRates = rates
            self.view.net = 0
            self.view.needsDisplay = true
            self.status.button?.image = self.imageForView()
            self.updateTooltip()
            self.vc.updateMetrics(cpu: self.view.cpu, gpu: self.view.gpu, ram: self.view.ram)
        }
        RunLoop.main.add(t, forMode: .common)
        let item = status.button!
        item.title = ""
        item.image = nil
        item.imagePosition = .imageOnly
        item.image = imageForView()
        updateTooltip()

        if let found = findButton(in: vc.view) {
            found.target = self
            found.action = #selector(quit)
        }
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.delegate = self

        item.target = self
        item.action = #selector(togglePopover)
    }

    private func findButton(in view: NSView) -> NSButton? {
        for sub in view.subviews {
            if let btn = sub as? NSButton { return btn }
            if let found = findButton(in: sub) { return found }
        }
        return nil
    }

    @objc func togglePopover() {
        guard let button = status.button else { return }
        if popover.isShown {
            popover.performClose(button)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverWillClose(_ notification: Notification) {
        // nothing needed for now
    }

    private func updateTooltip() {
        let tip: String
        if let g = view.gpu {
            tip = "GPU: \(Int((g * 100).rounded())) %"
        } else {
            tip = "GPU: Nicht verfügbar"
        }
        status.button?.toolTip = tip
    }

    @objc func quit() { NSApp.terminate(nil) }

    func imageForView() -> NSImage {
        let v = BarsView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
        v.cpu = view.cpu; v.gpu = view.gpu; v.ram = view.ram; v.net = view.net
        let img = NSImage(size: v.frame.size)
        img.lockFocus()
        v.draw(v.bounds)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
