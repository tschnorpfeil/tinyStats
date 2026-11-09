import AppKit
import QuartzCore
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

// MARK: - Formatting

/// "—" means missing data or a fresh baseline; 0 is a valid measurement.
enum Format {
    static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return "—" }
        return "\(Int((min(1, max(0, fraction)) * 100).rounded())) %"
    }

    static func rate(_ bps: Double?) -> String {
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

    /// Splits "8,2 KB/s" or "23 %" into number and unit.
    static func split(_ text: String) -> (number: String, unit: String) {
        guard let space = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }

    static func summary(cpu: Double?, gpu: Double?, ram: Double?, net: NetworkRates?) -> String {
        "CPU \(percent(cpu)) · GPU \(percent(gpu)) · RAM estimated \(percent(ram)) · Upload \(rate(net?.uploadBytesPerSecond)) · Download \(rate(net?.downloadBytesPerSecond))"
            .replacingOccurrences(of: "—", with: "Not available")
    }
}

// MARK: - Menu bar indicators

// Three bars in fixed order, left to right: CPU, GPU, RAM. No letters: the
// position names the bar; tooltip and VoiceOver carry the full names. Network
// rates are bytes per second, upload above download.
enum MenuBarIndicators {
    static let barWidth: CGFloat = 4
    static let barGap: CGFloat = 3
    /// Between the bars and the rates, wider than `barGap` so the arrows read as their own group.
    static let groupGap: CGFloat = 6
    /// Drawn arrow, as tall as the digits and stroked like the bars are rounded.
    static let arrowSize = NSSize(width: 5, height: 6)
    /// Arrow plus right-aligned rate; the widest rate ("999M") keeps 2 pt from its arrow.
    static let rateColumn: CGFloat = 34
    static let barsWidth = 3 * barWidth + 2 * barGap
    static let size = NSSize(width: barsWidth + groupGap + rateColumn, height: 22)
    static let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    /// Track of bar 0 (CPU), 1 (GPU) or 2 (RAM).
    static func track(_ index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * (barWidth + barGap), y: 4, width: barWidth, height: 14)
    }

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

    /// Upload on top, download below; each row keeps its own measured rate.
    static func rateRows(_ net: NetworkRates?) -> [(arrow: String, text: String, y: CGFloat)] {
        [("↑", compactRate(net?.uploadBytesPerSecond), 11), ("↓", compactRate(net?.downloadBytesPerSecond), 0)]
    }

    static func drawArrow(up: Bool, in box: NSRect) {
        let inset = box.insetBy(dx: 0.6, dy: 0.6)
        let tip = NSPoint(x: inset.midX, y: up ? inset.maxY : inset.minY)
        let tail = NSPoint(x: inset.midX, y: up ? inset.minY : inset.maxY)
        let wing = inset.width / 2
        let path = NSBezierPath()
        path.move(to: tail)
        path.line(to: tip)
        path.move(to: NSPoint(x: tip.x - wing, y: tip.y + (up ? -wing : wing)))
        path.line(to: tip)
        path.line(to: NSPoint(x: tip.x + wing, y: tip.y + (up ? -wing : wing)))
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.black.setStroke()
        path.stroke()
    }

    static func image(cpu: Double?, gpu: Double?, ram: Double?, net: NetworkRates?) -> NSImage {
        let values = [cpu, gpu, ram]
        let rows = rateRows(net)
        let image = NSImage(size: size, flipped: false) { _ in
            for (index, value) in values.enumerated() {
                let track = track(index)
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
            // Digits sit on the baseline and are cap-height tall; the arrow spans the same band.
            let baseline = -rateFont.descender + (11 - rateFont.ascender + rateFont.descender) / 2
            for (arrow, text, y) in rows {
                let box = NSRect(x: barsWidth + groupGap, y: y + baseline + (rateFont.capHeight - arrowSize.height) / 2,
                                 width: arrowSize.width, height: arrowSize.height)
                drawArrow(up: arrow == "↑", in: box)
                let width = (text as NSString).size(withAttributes: attributes).width
                (text as NSString).draw(at: NSPoint(x: size.width - width, y: y), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Silhouette

/// Lower edge of the camera housing as AppKit outlines the display. The public
/// values are whole points (safe area 32 pt on this Mac); the outline puts the
/// housing's lower edge at 32.17 pt, the panel's 56th pixel row. The outline
/// comes from NSScreen's undocumented `bezelPath`, is only read, and is used
/// only when it agrees with the public values to within a point.
enum HousingOutline {
    static func outline(of screen: NSScreen) -> NSBezierPath? {
        let selector = NSSelectorFromString("bezelPath")
        guard let method = class_getInstanceMethod(NSScreen.self, selector),
              let types = method_getTypeEncoding(method), String(cString: types).hasPrefix("@") else { return nil }
        return screen.perform(selector)?.takeUnretainedValue() as? NSBezierPath
    }

    /// Lowest outline vertex within the housing's span, in global coordinates;
    /// nil without a housing in the outline or when it disagrees with `notch`.
    /// Vertices lie on the outline; control points and the few hundredths of a
    /// point that continuous corners overshoot between vertices do not count.
    static func bottom(in outline: NSBezierPath, screenFrame: NSRect, notch: NSRect) -> CGFloat? {
        func matches(_ rect: NSRect) -> Bool {
            let b = outline.bounds
            return abs(b.minX - rect.minX) <= 1 && abs(b.minY - rect.minY) <= 1
                && abs(b.maxX - rect.maxX) <= 1 && abs(b.maxY - rect.maxY) <= 1
        }
        let offset: NSPoint
        if matches(screenFrame) {
            offset = .zero
        } else if matches(NSRect(origin: .zero, size: screenFrame.size)) {
            offset = screenFrame.origin
        } else {
            return nil
        }
        var points = [NSPoint](repeating: .zero, count: 3)
        var lowest = CGFloat.infinity
        for index in 0..<outline.elementCount {
            let vertex: NSPoint
            switch outline.element(at: index, associatedPoints: &points) {
            case .moveTo, .lineTo: vertex = points[0]
            case .curveTo, .cubicCurveTo: vertex = points[2]
            case .quadraticCurveTo: vertex = points[1]
            default: continue
            }
            let x = vertex.x + offset.x, y = vertex.y + offset.y
            if x > notch.minX + 1, x < notch.maxX - 1, y > notch.minY - 1 { lowest = min(lowest, y) }
        }
        guard lowest.isFinite, abs(lowest - notch.minY) <= 1 else { return nil }
        return lowest
    }
}

/// Black wing flush right of the camera housing. Global coordinates unless
/// noted. The window also reaches `notchOverlap` behind the housing, so the
/// wing's lower edge continues the housing's lower edge through its rounded
/// corner; that strip is otherwise hidden by the housing itself.
struct NotchWing: Equatable {
    static let indicatorInset: CGFloat = 6
    static let wingWidth: CGFloat = indicatorInset + MenuBarIndicators.size.width + 10
    static let notchOverlap: CGFloat = 36
    static let topFlare: CGFloat = 7
    static let bottomRadius: CGFloat = 10
    private static let tolerance: CGFloat = 0.5

    /// Housing bounding box: between both auxiliary areas, from the top of the
    /// screen down to the housing's lower edge (outline, else safe area).
    let notch: NSRect

    /// Right edge of the compact wing.
    var wingMaxX: CGFloat { notch.maxX + Self.wingWidth }

    /// One fixed window for the compact wing, including its top flare.
    var frame: NSRect {
        let minX = (notch.maxX - Self.notchOverlap).rounded(.down)
        let maxX = (wingMaxX + Self.topFlare).rounded(.up)
        let minY = notch.minY.rounded(.down)
        return NSRect(x: minX, y: minY, width: maxX - minX, height: notch.maxY - minY)
    }

    /// Housing edge, compact wing edge and lower edge in window coordinates (sub-point exact).
    var junctionX: CGFloat { notch.maxX - frame.minX }
    var edgeX: CGFloat { wingMaxX - frame.minX }
    var bottomY: CGFloat { notch.minY - frame.minY }

    /// Visible wing in window coordinates; only this part opens the details.
    var hitRect: NSRect { NSRect(x: junctionX, y: bottomY, width: Self.wingWidth, height: notch.height) }

    var indicatorRect: NSRect {
        NSRect(x: junctionX + Self.indicatorInset,
               y: (bottomY + (notch.height - MenuBarIndicators.size.height) / 2).rounded(),
               width: MenuBarIndicators.size.width, height: MenuBarIndicators.size.height)
    }

    /// `leftArea`/`rightArea` are `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`,
    /// `topInset` is `safeAreaInsets.top`, `outline` refines the lower edge.
    /// Nil without a usable housing.
    static func make(screenFrame: NSRect, leftArea: NSRect?, rightArea: NSRect?, topInset: CGFloat,
                     outline: NSBezierPath? = nil) -> NotchWing? {
        guard let leftArea, let rightArea, !leftArea.isEmpty, !rightArea.isEmpty, !screenFrame.isEmpty,
              topInset.isFinite, topInset >= MenuBarIndicators.size.height,
              abs(leftArea.maxY - screenFrame.maxY) <= tolerance,
              abs(rightArea.maxY - screenFrame.maxY) <= tolerance,
              leftArea.minX >= screenFrame.minX - tolerance,
              rightArea.maxX <= screenFrame.maxX + tolerance,
              rightArea.minX - leftArea.maxX >= 2 * notchOverlap else { return nil }
        var notch = NSRect(x: leftArea.maxX, y: screenFrame.maxY - topInset,
                           width: rightArea.minX - leftArea.maxX, height: topInset)
        if let outline, let bottom = HousingOutline.bottom(in: outline, screenFrame: screenFrame, notch: notch) {
            notch = NSRect(x: notch.minX, y: bottom, width: notch.width, height: screenFrame.maxY - bottom)
        }
        let wing = NotchWing(notch: notch)
        return wing.frame.maxX <= rightArea.maxX + tolerance &&
            wing.notch.width + Self.wingWidth >= IslandLayout.minimumWidth ? wing : nil
    }

    /// The wing for the first display with a usable housing. That display need
    /// not be the primary one: a built-in screen beside an external primary
    /// still has its notch.
    static func firstAvailable(on screens: [NSScreen]) -> NotchWing? {
        screens.lazy.compactMap {
            make(screenFrame: $0.frame, leftArea: $0.auxiliaryTopLeftArea, rightArea: $0.auxiliaryTopRightArea,
                 topInset: $0.safeAreaInsets.top, outline: HousingOutline.outline(of: $0))
        }.first
    }

    /// Whether a menu bar away from the wing would otherwise show no tinyStats.
    /// Every display has a menu bar with separate Spaces, otherwise only the
    /// primary (first) one does. macOS cannot hide a status item per display.
    func needsStatusItem(screens: [NSRect], separateSpaces: Bool) -> Bool {
        (separateSpaces ? screens[...] : screens.prefix(1)).contains { !$0.contains(frame) }
    }

    /// Window coordinates. Concave flare where the right edge meets the top of
    /// the display, straight lower edge on the housing's lower edge, convex free
    /// lower-right corner that squares off (`attach` → 1) while details hang
    /// below. Its width stays fixed throughout the transition.
    func path(attach: CGFloat) -> NSBezierPath {
        let top = notch.maxY - frame.minY
        let bottom = bottomY
        let edge = edgeX
        let flare = Self.topFlare
        let radius = Self.bottomRadius * (1 - min(1, max(0, attach)))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: top))
        path.line(to: NSPoint(x: edge + flare, y: top))
        path.appendArc(withCenter: NSPoint(x: edge + flare, y: top - flare), radius: flare,
                       startAngle: 90, endAngle: 180, clockwise: false)
        path.line(to: NSPoint(x: edge, y: bottom + radius))
        if radius > 0.01 {
            path.appendArc(withCenter: NSPoint(x: edge - radius, y: bottom + radius), radius: radius,
                           startAngle: 0, endAngle: 270, clockwise: true)
        }
        path.line(to: NSPoint(x: 0, y: bottom))
        path.close()
        return path
    }
}

/// Where the details hang and how they grow out of their source. Global
/// coordinates; `path`, `bodyRect` and `finalBodyRect` use window coordinates.
struct IslandLayout: Equatable {
    static let fillet: CGFloat = 10
    static let cornerRadius: CGFloat = 22
    static let menuBarWidth: CGFloat = 272
    /// Narrowest width that still fits three columns, the network tray and the footer.
    static let minimumWidth: CGFloat = 248
    static let screenMargin: CGFloat = 8
    static let headroom: CGFloat = 6

    var attachY: CGFloat
    var source: ClosedRange<CGFloat>
    var final: ClosedRange<CGFloat>
    var height: CGFloat
    var leftFillet: CGFloat
    var rightFillet: CGFloat
    var housingCapHeight: CGFloat = 0
    var isFloating: Bool = false

    /// Exact union of housing and compact wing: neither outer edge moves.
    /// Overlap the fractional lower edge to avoid a seam between windows.
    static func notch(_ wing: NotchWing, height: CGFloat) -> IslandLayout {
        IslandLayout(attachY: wing.notch.minY.rounded(.up), source: wing.notch.maxX...wing.wingMaxX,
                     final: wing.notch.minX...wing.wingMaxX, height: height,
                     leftFillet: 0, rightFillet: 0, housingCapHeight: wing.notch.maxY - wing.notch.minY.rounded(.up))
    }

    /// From the menu bar's lower edge, centred under the status item.
    static func menuBar(anchor: NSRect, screen: NSRect, visibleTop: CGFloat, height: CGFloat) -> IslandLayout {
        // The button is shorter than the bar; use the bar edge when the bar is reserved.
        let barBottom = visibleTop < screen.maxY - 0.5 ? min(anchor.minY, visibleTop) : anchor.minY
        let low = screen.minX + screenMargin
        let high = screen.maxX - screenMargin
        let width = min(menuBarWidth, high - low)
        let minX = min(max((anchor.midX - width / 2).rounded(), low), high - width)
        let sourceLow = min(max(anchor.minX, low), high)
        let sourceHigh = max(min(anchor.maxX, high), sourceLow)
        return IslandLayout(attachY: barBottom - 6, source: sourceLow...sourceHigh, final: minX...(minX + width),
                            height: height, leftFillet: 0, rightFillet: 0, isFloating: true)
    }

    var width: CGFloat { final.upperBound - final.lowerBound }

    /// Whole-point frame; notch mode also covers the housing cutout above the attach line.
    var frame: NSRect {
        let minX = (min(source.lowerBound, final.lowerBound) - leftFillet).rounded(.down)
        let maxX = (max(source.upperBound, final.upperBound) + rightFillet).rounded(.up)
        let top = (attachY + housingCapHeight).rounded(.up)
        let bottom = (attachY - height - Self.headroom).rounded(.down)
        return NSRect(x: minX, y: bottom, width: maxX - minX, height: top - bottom)
    }

    struct Shape: Equatable {
        var minX: CGFloat, maxX: CGFloat, height: CGFloat
        var leftFillet: CGFloat, rightFillet: CGFloat, radius: CGFloat
    }

    func shape(at progress: CGFloat) -> Shape {
        let grow = Choreography.widthProgress(progress)
        let minX = source.lowerBound + (final.lowerBound - source.lowerBound) * grow
        let maxX = source.upperBound + (final.upperBound - source.upperBound) * grow
        let h = min(height + Self.headroom, max(0, height * progress))
        let left = min(leftFillet, h / 2), right = min(rightFillet, h / 2)
        let radius = max(0, min(Self.cornerRadius, (maxX - minX) / 2, h - max(left, right)))
        return Shape(minX: minX, maxX: maxX, height: h, leftFillet: left, rightFillet: right, radius: radius)
    }

    /// Body without fillets.
    func bodyRect(at progress: CGFloat) -> NSRect {
        let s = shape(at: progress)
        return NSRect(x: s.minX - frame.minX, y: attachY - frame.minY - s.height,
                      width: s.maxX - s.minX, height: s.height)
    }

    var finalBodyRect: NSRect {
        NSRect(x: final.lowerBound - frame.minX, y: attachY - height - frame.minY, width: width, height: height)
    }

    func path(at progress: CGFloat) -> NSBezierPath {
        let s = shape(at: progress)
        let path = NSBezierPath()
        guard s.height > 0.01, s.maxX - s.minX > 0.01 else { return path }
        if isFloating {
            let body = bodyRect(at: progress)
            let radius = min(Self.cornerRadius, body.height / 2, body.width / 2)
            return NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        }
        let left = s.minX - frame.minX, right = s.maxX - frame.minX
        let top = attachY - frame.minY, bottom = top - s.height
        path.move(to: NSPoint(x: left - s.leftFillet, y: top))
        path.line(to: NSPoint(x: right + s.rightFillet, y: top))
        if s.rightFillet > 0.01 {
            path.appendArc(withCenter: NSPoint(x: right + s.rightFillet, y: top - s.rightFillet),
                           radius: s.rightFillet, startAngle: 90, endAngle: 180, clockwise: false)
        }
        path.line(to: NSPoint(x: right, y: bottom + s.radius))
        if s.radius > 0.01 {
            path.appendArc(withCenter: NSPoint(x: right - s.radius, y: bottom + s.radius),
                           radius: s.radius, startAngle: 0, endAngle: 270, clockwise: true)
        }
        path.line(to: NSPoint(x: left + s.radius, y: bottom))
        if s.radius > 0.01 {
            path.appendArc(withCenter: NSPoint(x: left + s.radius, y: bottom + s.radius),
                           radius: s.radius, startAngle: 270, endAngle: 180, clockwise: true)
        }
        path.line(to: NSPoint(x: left, y: top - s.leftFillet))
        if s.leftFillet > 0.01 {
            path.appendArc(withCenter: NSPoint(x: left - s.leftFillet, y: top - s.leftFillet),
                           radius: s.leftFillet, startAngle: 0, endAngle: 90, clockwise: false)
        }
        path.close()
        // Fill the housing's lower-left rounded cutout as the island reaches
        // its left edge. The cap stays strictly inside the housing bounds;
        // the wing's visible width and the content position do not change.
        if housingCapHeight > 0 {
            let capRight = min(source.lowerBound, s.maxX) - frame.minX
            if capRight > left {
                path.appendRect(NSRect(x: left, y: top, width: capRight - left, height: housingCapHeight))
            }
        }
        return path
    }
}

// MARK: - Motion

/// Pure functions of the presentation progress (0 closed, 1 open, small
/// overshoot allowed). Drawing, reversals and render checks share them.
enum Choreography {
    /// Width leads height slightly, so the shape first spreads, then drops.
    static func widthProgress(_ p: CGFloat) -> CGFloat {
        let t = min(max(p / 0.8, 0), 1)
        return 1 - (1 - t) * (1 - t)
    }
    /// The silhouette fades from transparent to black as it opens and back as
    /// it closes. It finishes before the content starts, because the content
    /// paints its own black and would show as a darker rectangle otherwise.
    static func backgroundAlpha(_ p: CGFloat) -> CGFloat { smoothstep(0, 0.55, p) }
    static func contentAlpha(_ p: CGFloat) -> CGFloat { smoothstep(0.55, 0.95, p) }
    /// Content settles downward into place while the body opens.
    static func contentDrop(_ p: CGFloat) -> CGFloat { 8 * (1 - smoothstep(0.3, 1, p)) }
    /// Squares the wing's lower-right corner as the body fades in below it.
    static func attach(_ p: CGFloat) -> CGFloat { smoothstep(0, 0.3, p) }

    static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Damped spring on the progress. Retargeting keeps value and velocity, so a
/// reversal continues from wherever the shape is.
struct Spring {
    struct Parameters: Equatable {
        var response: Double
        var damping: Double
    }
    static let opening = Parameters(response: 0.5, damping: 0.85)
    static let closing = Parameters(response: 0.34, damping: 1)

    private(set) var value: Double = 0
    private(set) var velocity: Double = 0
    private(set) var target: Double = 0
    private(set) var parameters = Spring.closing

    var isSettled: Bool { value == target && velocity == 0 }

    mutating func retarget(_ target: Double, _ parameters: Parameters) {
        self.target = target
        self.parameters = parameters
    }

    mutating func snap(to target: Double) {
        self.target = target
        value = target
        velocity = 0
    }

    mutating func advance(by interval: Double) {
        guard interval > 0, !isSettled else { return }
        let stiffness = pow(2 * Double.pi / parameters.response, 2)
        let friction = 4 * Double.pi * parameters.damping / parameters.response
        // A stalled frame slows the motion down instead of making it jump.
        var remaining = min(interval, 1.0 / 15)
        while remaining > 0 {
            let step = min(1.0 / 480, remaining)
            velocity += (-stiffness * (value - target) - friction * velocity) * step
            value += velocity * step
            remaining -= step
        }
        if abs(value - target) < 0.0005, abs(velocity) < 0.01 {
            value = target
            velocity = 0
        }
    }
}

// MARK: - Details content

enum IslandStyle {
    static let primary = NSColor(white: 1, alpha: 0.95)
    static let secondary = NSColor(white: 1, alpha: 0.56)
    static let tertiary = NSColor(white: 1, alpha: 0.32)
    static let track = NSColor(white: 1, alpha: 0.17)
    static let tray = NSColor(white: 1, alpha: 0.075)
    static let hairline = NSColor(white: 1, alpha: 0.12)
    static let caption = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    static let value = rounded(24, .semibold)
    static let valueUnit = rounded(13, .semibold)
    static let rate = rounded(13, .semibold)
    static let rateUnit = NSFont.systemFont(ofSize: 10.5, weight: .medium)
    static let footer = NSFont.systemFont(ofSize: 11, weight: .medium)

    /// SF Pro Rounded with tabular digits, so 1 Hz updates do not wobble.
    static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let tabular = design.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        return NSFont(descriptor: tabular, size: size) ?? base
    }

    static func text(_ string: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    /// Number with a smaller unit on the same baseline; a dim dash when missing.
    static func measure(_ formatted: String, number: NSFont, unit: NSFont) -> NSAttributedString {
        let parts = Format.split(formatted)
        let result = NSMutableAttributedString(attributedString:
            text(parts.number, number, parts.unit.isEmpty ? secondary : primary))
        if !parts.unit.isEmpty { result.append(text("\u{2009}" + parts.unit, unit, secondary)) }
        return result
    }

    static func drawCentered(_ text: NSAttributedString, x: CGFloat, in bounds: NSRect, alignRight: Bool = false) {
        let size = text.size()
        let width = ceil(size.width), height = ceil(size.height)
        text.draw(in: NSRect(x: alignRight ? x - width : x, y: ((bounds.height - height) / 2).rounded(),
                             width: width, height: height))
    }
}

/// Caption, value and a thin proportional meter for one utilisation metric.
final class MetricView: NSView {
    static let height: CGFloat = 50
    let caption: String
    var value: Double? { didSet { if value != oldValue { needsDisplay = true } } }

    init(caption: String, name: String) {
        self.caption = caption
        super.init(frame: NSRect(x: 0, y: 0, width: 70, height: Self.height))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(name)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func accessibilityValue() -> Any? { Format.percent(value).replacingOccurrences(of: "—", with: "Not available") }

    override func draw(_ dirtyRect: NSRect) {
        IslandStyle.text(caption, IslandStyle.caption, IslandStyle.secondary, kern: 0.4).draw(at: NSPoint(x: 0, y: 0))
        IslandStyle.measure(Format.percent(value), number: IslandStyle.value, unit: IslandStyle.valueUnit)
            .draw(at: NSPoint(x: -1, y: 12))
        Self.drawMeter(in: NSRect(x: 0, y: bounds.height - 3, width: bounds.width, height: 3), value: value)
    }

    /// Solid track for a measurement (empty at 0 %), dotted track when unavailable.
    static func drawMeter(in rect: NSRect, value: Double?) {
        let radius = rect.height / 2
        guard let value, value.isFinite else {
            IslandStyle.tertiary.setFill()
            var x = rect.minX
            while x + rect.height <= rect.maxX + 0.01 {
                NSBezierPath(ovalIn: NSRect(x: x, y: rect.minY, width: rect.height, height: rect.height)).fill()
                x += rect.height * 2.5
            }
            return
        }
        IslandStyle.track.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let width = rect.width * CGFloat(min(1, max(0, value)))
        guard width > 0 else { return }
        IslandStyle.primary.setFill()
        let fill = NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        NSBezierPath(roundedRect: fill, xRadius: min(radius, width / 2), yRadius: min(radius, width / 2)).fill()
    }
}

/// Upload and download as one quiet tray. Rates are not normalised to a capacity.
final class NetworkView: NSView {
    static let height: CGFloat = 30
    var rates: NetworkRates? { didSet { needsDisplay = true } }
    private static let arrow = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [IslandStyle.secondary]))

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Network")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// Reading order upload, then download, matching the menu bar (upload on top).
    static func entries(_ rates: NetworkRates?) -> [(symbol: String, name: String, value: Double?)] {
        [("arrow.up", "Upload", rates?.uploadBytesPerSecond), ("arrow.down", "Download", rates?.downloadBytesPerSecond)]
    }

    override func accessibilityValue() -> Any? {
        Self.entries(rates).map { "\($0.name) \(Format.rate($0.value))" }.joined(separator: ", ")
            .replacingOccurrences(of: "—", with: "not available")
    }

    override func draw(_ dirtyRect: NSRect) {
        IslandStyle.tray.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        IslandStyle.hairline.setFill()
        NSRect(x: (bounds.midX - 0.5).rounded(), y: 9, width: 1, height: bounds.height - 18).fill()
        for (index, entry) in Self.entries(rates).enumerated() {
            let x = CGFloat(index) * bounds.width / 2 + 11
            if let image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(Self.arrow) {
                let size = image.size
                image.draw(in: NSRect(x: x, y: ((bounds.height - size.height) / 2).rounded(),
                                      width: size.width, height: size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            IslandStyle.drawCentered(IslandStyle.measure(Format.rate(entry.value), number: IslandStyle.rate,
                                                         unit: IslandStyle.rateUnit), x: x + 14, in: bounds)
        }
    }
}

/// Monochrome switch with its label; an accent colour would break the scheme.
final class MonoSwitch: NSButton {
    static let size = NSSize(width: 68, height: 16)

    convenience init(label: String) {
        self.init(frame: NSRect(origin: .zero, size: Self.size))
        setButtonType(.switch)
        title = label
        isBordered = false
        focusRingType = .none
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel("Show beside notch")
    }

    override func accessibilityValue() -> Any? { state == .on ? 1 : 0 }

    override func draw(_ dirtyRect: NSRect) {
        let on = state == .on
        let track = NSRect(x: bounds.maxX - 22, y: ((bounds.height - 12) / 2).rounded(), width: 22, height: 12)
        IslandStyle.drawCentered(IslandStyle.text(title, IslandStyle.footer, IslandStyle.secondary),
                                 x: track.minX - 6, in: bounds, alignRight: true)
        NSColor(white: 1, alpha: on ? 0.72 : 0.18).setFill()
        NSBezierPath(roundedRect: track, xRadius: 6, yRadius: 6).fill()
        (on ? NSColor.black : NSColor(white: 1, alpha: 0.8)).setFill()
        NSBezierPath(ovalIn: NSRect(x: on ? track.maxX - 10.5 : track.minX + 1.5, y: track.minY + 1.5, width: 9, height: 9)).fill()
    }
}

/// Quiet text action that brightens under the pointer.
final class TextButton: NSButton {
    private var hovering = false { didSet { needsDisplay = true } }
    private var area: NSTrackingArea?

    convenience init(label: String) {
        self.init(frame: .zero)
        title = label
        isBordered = false
        focusRingType = .none
        setAccessibilityRole(.button)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let color = hovering || isHighlighted ? IslandStyle.primary : IslandStyle.secondary
        IslandStyle.drawCentered(IslandStyle.text(title, IslandStyle.footer, color), x: bounds.maxX, in: bounds, alignRight: true)
    }
}

/// Fixed layout: samples update values in place without re-layout, so 1 Hz
/// updates never disturb a running transition.
final class IslandContentView: NSView {
    static let padding: CGFloat = 16
    static let columnGap: CGFloat = 12
    static let metricsTop: CGFloat = 14
    static let networkTop: CGFloat = metricsTop + MetricView.height + 14
    static let footerTop: CGFloat = networkTop + NetworkView.height + 12
    static let footerHeight: CGFloat = 16
    static let height: CGFloat = footerTop + footerHeight + 12

    let cpu = MetricView(caption: "CPU", name: "CPU")
    let gpu = MetricView(caption: "GPU", name: "GPU")
    let ram = MetricView(caption: "RAM ≈", name: "RAM estimated")
    let network = NetworkView(frame: .zero)
    let notchSwitch = MonoSwitch(label: "Notch")
    let quitButton = TextButton(label: "Quit")
    var onQuit: (() -> Void)?
    var onNotchToggle: ((Bool) -> Void)?

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        wantsLayer = true
        canDrawSubviewsIntoLayer = true
        ram.toolTip = "Estimated usage: active, wired and compressed memory pages. Not memory pressure."
        notchSwitch.target = self
        notchSwitch.action = #selector(notchToggled)
        notchSwitch.isHidden = true
        quitButton.target = self
        quitButton.action = #selector(quitClicked)
        quitButton.setAccessibilityLabel("Quit tinyStats")
        quitButton.toolTip = "Quit tinyStats (⌘Q)"
        [cpu, gpu, ram, network, notchSwitch, quitButton].forEach(addSubview)
        layout(width: width)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func layout(width: CGFloat) {
        setFrameSize(NSSize(width: width, height: Self.height))
        let inner = width - 2 * Self.padding
        let column = ((inner - 2 * Self.columnGap) / 3).rounded(.down)
        for (index, view) in [cpu, gpu, ram].enumerated() {
            view.frame = NSRect(x: Self.padding + CGFloat(index) * (column + Self.columnGap), y: Self.metricsTop,
                                width: column, height: MetricView.height)
        }
        network.frame = NSRect(x: Self.padding, y: Self.networkTop, width: inner, height: NetworkView.height)
        quitButton.frame = NSRect(x: width - Self.padding - 60, y: Self.footerTop, width: 60, height: Self.footerHeight)
        notchSwitch.frame = NSRect(x: quitButton.frame.minX - 14 - MonoSwitch.size.width, y: Self.footerTop,
                                   width: MonoSwitch.size.width, height: Self.footerHeight)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
        let mark = NSMutableAttributedString(attributedString: IslandStyle.text("tiny", IslandStyle.footer, IslandStyle.tertiary))
        mark.append(IslandStyle.text("Stats", NSFont.systemFont(ofSize: 11, weight: .semibold), IslandStyle.secondary))
        let size = mark.size()
        mark.draw(in: NSRect(x: Self.padding, y: Self.footerTop + ((Self.footerHeight - ceil(size.height)) / 2).rounded(),
                             width: ceil(size.width), height: ceil(size.height)))
    }

    func update(cpu: Double?, gpu: Double?, ram: Double?, net: NetworkRates?) {
        self.cpu.value = cpu
        self.gpu.value = gpu
        self.ram.value = ram
        network.rates = net
    }

    /// The switch exists only while a connected display has a usable housing.
    func setNotchOption(available: Bool, enabled: Bool) {
        notchSwitch.state = enabled ? .on : .off
        notchSwitch.isEnabled = available
        notchSwitch.isHidden = !available
    }

    @objc private func quitClicked() { onQuit?() }
    @objc private func notchToggled() { onNotchToggle?(notchSwitch.state == .on) }
}

// MARK: - Details island

/// Draws the silhouette for the current progress, fading it between
/// transparent and black, and reveals the content inside the body as it opens.
final class IslandView: NSView {
    let content: IslandContentView
    private let clip = NSView()
    private(set) var layout: IslandLayout?
    private(set) var progress: CGFloat = 0

    init(content: IslandContentView) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        clip.wantsLayer = true
        clip.clipsToBounds = true
        clip.autoresizesSubviews = false
        clip.layer?.masksToBounds = true
        clip.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(clip)
        clip.addSubview(content)
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    func configure(_ layout: IslandLayout) {
        self.layout = layout
        clip.layer?.maskedCorners = layout.isFloating
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        frame = NSRect(origin: .zero, size: layout.frame.size)
        content.layout(width: layout.width)
        setProgress(progress)
    }

    func setProgress(_ value: CGFloat) {
        progress = value
        guard let layout else { return }
        needsDisplay = true
        let body = layout.bodyRect(at: value)
        clip.isHidden = body.height < 1
        clip.frame = body
        clip.layer?.cornerRadius = layout.shape(at: value).radius
        let final = layout.finalBodyRect
        content.setFrameOrigin(NSPoint(x: final.minX - body.minX,
                                       y: final.maxY - body.minY - content.frame.height + Choreography.contentDrop(value)))
        content.alphaValue = Choreography.contentAlpha(value)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let layout else { return }
        NSColor.black.withAlphaComponent(Choreography.backgroundAlpha(progress)).setFill()
        layout.path(at: progress).fill()
    }

    func shapeContains(_ point: NSPoint) -> Bool { layout?.path(at: progress).contains(point) ?? false }
}

final class IslandPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        allowsToolTipsWhenApplicationIsInactive = true
        appearance = NSAppearance(named: .darkAqua)
        setAccessibilityLabel("tinyStats")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// The only details presenter: grows the island out of its source and back,
/// driven by one spring on the display link. Reversals retarget in flight.
final class IslandPresenter: NSObject {
    let view: IslandView
    let panel = IslandPanel()
    private(set) var spring = Spring()
    private(set) var isPresented = false
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var fadeToken = 0
    private(set) var sourceRect = NSRect.zero
    var onProgress: ((CGFloat) -> Void)?
    var onPresentedChange: ((Bool) -> Void)?
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(content: IslandContentView) {
        view = IslandView(content: content)
        super.init()
        panel.contentView = view
        panel.onCancel = { [weak self] in self?.close() }
    }

    /// `source` is the clickable origin in screen coordinates; clicks there
    /// belong to its own toggle and never count as outside clicks.
    func open(layout: IslandLayout, source: NSRect) {
        guard !isPresented else { return }
        isPresented = true
        sourceRect = source
        let still = reduceMotion()
        if !panel.isVisible {
            // A reversal keeps the geometry already in flight.
            view.configure(layout)
            panel.setFrame(layout.frame, display: false)
            spring.snap(to: 0)
            apply(0)
            panel.alphaValue = still ? 0 : 1
        }
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        onPresentedChange?(true)
        if still {
            spring.snap(to: 1)
            apply(1)
            fade(to: 1, completion: nil)
        } else {
            fadeToken += 1
            panel.alphaValue = 1
            spring.retarget(1, Spring.opening)
            run()
        }
    }

    func close(animated: Bool = true) {
        if isPresented {
            isPresented = false
            removeMonitors()
            panel.ignoresMouseEvents = true
            onPresentedChange?(false)
        } else if animated || !panel.isVisible {
            return
        }
        guard animated else { finishClose(); return }
        if reduceMotion() {
            fade(to: 0) { [weak self] in self?.finishClose() }
        } else {
            fadeToken += 1
            panel.alphaValue = 1
            spring.retarget(0, Spring.closing)
            run()
        }
    }

    private func finishClose() {
        guard !isPresented else { return }
        link?.isPaused = true
        fadeToken += 1
        spring.snap(to: 0)
        apply(0)
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func apply(_ progress: CGFloat) {
        view.setProgress(progress)
        onProgress?(progress)
    }

    private func run() {
        if link == nil {
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        guard let link, link.isPaused else { return }
        lastTick = CACurrentMediaTime()
        link.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        // Step by presented frame time; callback time jitters from frame to frame.
        let now = link.targetTimestamp
        spring.advance(by: now - lastTick)
        lastTick = now
        apply(CGFloat(spring.value))
        guard spring.isSettled else { return }
        link.isPaused = true
        if spring.target == 0 { finishClose() }
    }

    private func fade(to alpha: CGFloat, completion: (() -> Void)?) {
        link?.isPaused = true
        fadeToken += 1
        let token = fadeToken
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = alpha
        } completionHandler: { [weak self] in
            guard let self, self.fadeToken == token else { return }
            completion?()
        }
    }

    enum Route: Equatable { case pass, close, consumeAndClose, quit }

    /// Event routing while presented. Clicks on the source pass through to its
    /// own toggle (never swallowed, never a second toggle); clicks inside the
    /// silhouette stay; anything else closes. Escape closes, ⌘Q quits.
    static func route(keyCode: UInt16?, command: Bool, characters: String?,
                      inPanel: Bool, insideShape: Bool, inSource: Bool) -> Route {
        if let keyCode {
            if keyCode == 53 { return .consumeAndClose }
            if command, characters?.lowercased() == "q" { return .quit }
            return .pass
        }
        if inPanel { return insideShape ? .pass : .close }
        return inSource ? .pass : .close
    }

    func handleLocal(_ event: NSEvent) -> NSEvent? {
        let key = event.type == .keyDown
        let inPanel = event.window === panel
        switch Self.route(keyCode: key ? event.keyCode : nil, command: event.modifierFlags.contains(.command),
                          characters: key ? event.charactersIgnoringModifiers : nil, inPanel: inPanel,
                          insideShape: inPanel && view.shapeContains(event.locationInWindow),
                          inSource: sourceRect.contains(NSEvent.mouseLocation)) {
        case .pass: return event
        case .close: close(); return event
        case .consumeAndClose: close(); return nil
        case .quit: NSApp.terminate(nil); return nil
        }
    }

    func handleOutside(at point: NSPoint) {
        if Self.route(keyCode: nil, command: false, characters: nil, inPanel: false, insideShape: false,
                      inSource: sourceRect.contains(point)) == .close { close() }
    }

    private func installMonitors() {
        removeMonitors()
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown],
                                                        handler: { [weak self] event in self?.handleLocal(event) ?? event }) {
            monitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                                                          handler: { [weak self] _ in self?.handleOutside(at: NSEvent.mouseLocation) }) {
            monitors.append(global)
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            // Another app came forward (⌘Tab, Dock); our own key focus does not count.
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if activated?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.close() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in self?.close() })
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
    }

    deinit { removeMonitors() }
}

// MARK: - Notch wing window

/// Draws the wing and the indicator white on black.
final class WingView: NSView {
    var wing: NotchWing? { didSet { needsDisplay = true } }
    var attach: CGFloat = 0 { didSet { if attach != oldValue { needsDisplay = true } } }
    var indicator: NSImage? { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let wing else { return }
        // The strip behind the housing answers only while the details hang below.
        if wing.hitRect.contains(convert(event.locationInWindow, from: nil)) || attach > 0 { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let wing else { return }
        NSColor.black.setFill()
        wing.path(attach: attach).fill()
        guard let indicator, let context = NSGraphicsContext.current else { return }
        let target = wing.indicatorRect
        context.saveGraphicsState()
        // Tint the template: keep its alpha, replace its colour with white.
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

final class WingPanel: NSPanel {
    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 32),
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
        allowsToolTipsWhenApplicationIsInactive = true
        contentView = WingView(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
    }

    var wingView: WingView { contentView as! WingView }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Keep the frame at the top edge beside the housing instead of below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func place(_ wing: NotchWing) {
        wingView.wing = wing
        setFrame(wing.frame, display: false)
        wingView.frame = NSRect(origin: .zero, size: wing.frame.size)
        follow(attach: 0)
    }

    func follow(attach: CGFloat) {
        wingView.attach = attach
    }
}

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
    let content = IslandContentView(width: IslandLayout.menuBarWidth)
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
        content.onQuit = { NSApp.terminate(nil) }
        content.onNotchToggle = { [weak self] enabled in
            UserDefaults.standard.set(enabled, forKey: Self.notchDefaultsKey)
            self?.updatePlacement()
        }
        wingPanel.wingView.setAccessibilityLabel("tinyStats")
        wingPanel.wingView.onClick = { [weak self] in self?.toggleDetails() }
        presenter.onProgress = { [weak self] progress in
            guard let self, self.wing != nil else { return }
            // Only join the lower corner; the compact wing never changes width.
            // A card floating under the status item leaves the wing alone.
            let attached = self.presenter.view.layout?.isFloating == false
            self.wingPanel.follow(attach: attached ? Choreography.attach(progress) : 0)
        }
        presenter.onPresentedChange = { [weak self] shown in
            let highlighted = shown && self?.presenter.view.layout?.isFloating == true
            // After the button's own mouse-up handling, which resets its highlight.
            DispatchQueue.main.async { self?.status.button?.highlight(highlighted) }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        updatePlacement()
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func screensChanged(_ notification: Notification) { updatePlacement() }

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
        let cpu = metrics.cpu()
        let gpu = metrics.gpu()
        let ram = metrics.ram()
        let rates = metrics.network()
        content.update(cpu: cpu, gpu: gpu, ram: ram, net: rates)
        let summary = Format.summary(cpu: cpu, gpu: gpu, ram: ram, net: rates)
        let image = MenuBarIndicators.image(cpu: cpu, gpu: gpu, ram: ram, net: rates)
        status.button?.image = image
        status.button?.toolTip = summary
        status.button?.setAccessibilityValue(summary)
        wingPanel.wingView.indicator = image
        wingPanel.wingView.toolTip = summary
        wingPanel.wingView.setAccessibilityValue(summary)
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

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
}

let app = NSApplication.shared
if let running = SingleInstance.runningInstance() {
    FileHandle.standardError.write(Data("tinyStats is already running (PID \(running)).\n".utf8))
    exit(0)
}
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
