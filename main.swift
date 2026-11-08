import AppKit
import IOKit
import Darwin
import CoreFoundation

// MARK: - Metrics

final class Metrics {
    private var prevCPU: (user: UInt32, sys: UInt32, idle: UInt32, nice: UInt32)?
    private var prevNets: (in: UInt64, out: UInt64, t: TimeInterval)?

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

    func gpu() -> Double {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }
        var busy = 0.0
        var found = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            IOObjectRelease(service)
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let util = props["PerformanceStatistics"] as? [String: Any],
                  let stats = util["IOAcceleratorUtilization"] as? [String: Int],
                  let g = stats["GPU"] else { continue }
            busy += Double(g) / 100.0
            found = true
        }
        return found ? min(1.0, busy) : 0
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

    func network() -> Double {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return 0 }
        defer { freeifaddrs(ifaddr) }
        var inTotal: UInt64 = 0, outTotal: UInt64 = 0
        var ptr = ifaddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let ifa = cur.pointee
            guard let namePtr = ifa.ifa_name,
                  let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let name = String(validatingUTF8: namePtr), name.hasPrefix("en") else { continue }
            if let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                inTotal &+= UInt64(data.pointee.ifi_ibytes)
                outTotal &+= UInt64(data.pointee.ifi_obytes)
            }
        }
        let now = Date().timeIntervalSince1970
        defer { prevNets = (inTotal, outTotal, now) }
        guard let p = prevNets, now > p.t else { return 0 }
        let dt = now - p.t
        let bytes = Double((inTotal &- p.in) + (outTotal &- p.out)) / dt
        return min(1.0, bytes / 50_000_000) // saturate at 50 MB/s
    }
}

// MARK: - Bar View

final class BarsView: NSView {
    var cpu: Double = 0
    var gpu: Double = 0
    var ram: Double = 0
    var net: Double = 0
    var showPopup = false

    static let barW: CGFloat = 5
    static let gap: CGFloat = 6
    static let h: CGFloat = 18

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let labels = [("C", cpu), ("G", gpu), ("R", ram), ("N", net)]
        let x0: CGFloat = 4
        let line = NSColor.labelColor
        let fill = NSColor.labelColor
        let popup = NSColor.secondaryLabelColor

        for (i, (letter, value)) in labels.enumerated() {
            let x = x0 + CGFloat(i) * (BarsView.barW + BarsView.gap)
            let v = min(1.0, max(0.0, value))

            if showPopup {
                let p = NSBezierPath(roundedRect: NSRect(x: x - 1, y: 1, width: Self.barW + 2, height: Self.h - 2),
                                     xRadius: 2, yRadius: 2)
                p.lineWidth = 1
                popup.setStroke()
                p.stroke()
            }

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
                .foregroundColor: v > 0.5 ? NSColor.textBackgroundColor : NSColor.labelColor
            ]
            let s = NSAttributedString(string: letter, attributes: attrs)
            let sz = s.size()
            s.draw(at: NSPoint(x: x + (Self.barW - sz.width) / 2, y: (Self.h - sz.height) / 2))
        }
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate {
    let status = NSStatusBar.system.statusItem(withLength: 64)
    let view = BarsView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
    let metrics = Metrics()
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ n: Notification) {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.view.cpu = self.metrics.cpu()
            self.view.gpu = self.metrics.gpu()
            self.view.ram = self.metrics.ram()
            self.view.net = self.metrics.network()
            self.view.needsDisplay = true
            self.status.button?.image = self.imageForView()
        }
        RunLoop.main.add(t, forMode: .common)
        let item = status.button!
        item.title = ""
        item.image = nil
        item.imagePosition = .imageOnly
        item.image = imageForView()
        menu.autoenablesItems = false
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        item.sendAction(on: [.leftMouseUp])
        item.target = self
        item.action = #selector(toggle)
    }

    @objc func toggle() {
        view.showPopup.toggle()
        status.button?.image = imageForView()
    }

    @objc func quit() { NSApp.terminate(nil) }

    func imageForView() -> NSImage {
        let v = BarsView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
        v.cpu = view.cpu; v.gpu = view.gpu; v.ram = view.ram; v.net = view.net
        v.showPopup = view.showPopup
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
