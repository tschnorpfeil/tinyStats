import Foundation

// MARK: - Metric catalogue

/// Columns of the list under the tiles and sections of the menu bar picker.
enum MetricCategory: String, CaseIterable {
    case power = "Power", storage = "Storage", system = "System"
}

/// Text and one fill value per metric. Gauges have a natural 0...100 % scale,
/// so only they can fill a top tile and its menu bar bar.
enum Metric: String, CaseIterable {
    case cpu, gpu, ram, battery, disk, network, usage, charging, diskActivity, swap

    static let gauges: [Metric] = [.cpu, .gpu, .ram, .battery, .disk]

    var isGauge: Bool { Self.gauges.contains(self) }
    var needsBattery: Bool { self == .battery || self == .usage || self == .charging }

    static func available(hasBattery: Bool) -> [Metric] { allCases.filter { hasBattery || !$0.needsBattery } }

    /// Nil only for network, which has its own tray.
    var category: MetricCategory? {
        switch self {
        case .battery, .usage, .charging: return .power
        case .disk, .diskActivity: return .storage
        case .cpu, .gpu, .ram, .swap: return .system
        case .network: return nil
        }
    }

    /// Categories in display order, leaving out any with nothing to show.
    static func grouped(_ metrics: [Metric]) -> [(category: MetricCategory, metrics: [Metric])] {
        MetricCategory.allCases.compactMap { category -> (category: MetricCategory, metrics: [Metric])? in
            let members = metrics.filter { $0.category == category }
            return members.isEmpty ? nil : (category, members)
        }
    }

    var name: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ram: return "RAM"
        case .battery: return "Battery"
        case .disk: return "Disk"
        case .network: return "Network"
        case .usage: return "Power Usage"
        case .charging: return "Charging"
        case .diskActivity: return "Disk Activity"
        case .swap: return "Swap"
        }
    }

    var caption: String { self == .ram ? "RAM ≈" : name.uppercased() }

    func fraction(_ s: Sample) -> Double? {
        switch self {
        case .cpu: return s.cpu
        case .gpu: return s.gpu
        case .ram: return s.ram
        case .battery: return s.battery?.fraction
        case .disk: return s.disk?.usedFraction
        default: return nil
        }
    }

    func isCharging(_ s: Sample) -> Bool { self == .battery && s.battery?.state == .charging }

    /// Rows for the list under the tiles; disk activity takes two.
    func cells(_ s: Sample) -> [(label: String, value: String, bolt: Bool)] {
        switch self {
        case .disk: return [("Free", Format.bytes(s.disk?.freeBytes), false)]
        case .network: return []
        case .usage: return [("Usage", Format.watts(s.battery?.usageWatts), false)]
        case .charging: return [("Charging", Format.watts(s.battery?.chargeWatts), false)]
        case .diskActivity:
            return [("Read", Format.rate(s.diskIO?.readBytesPerSecond), false),
                    ("Write", Format.rate(s.diskIO?.writeBytesPerSecond), false)]
        case .swap: return [("Swap", Format.bytes(s.swapUsedBytes), false)]
        default: return [(name, Format.percent(fraction(s)), isCharging(s))]
        }
    }

    func readout(_ s: Sample) -> MenuBarReadout {
        func compactWatts(_ value: Double?) -> String {
            MenuBarIndicators.compactNumber(value).map { $0 + "W" } ?? "—"
        }
        switch self {
        case .network: return .rates(up: s.net?.uploadBytesPerSecond, down: s.net?.downloadBytesPerSecond)
        case .diskActivity: return .rates(up: s.diskIO?.writeBytesPerSecond, down: s.diskIO?.readBytesPerSecond)
        case .usage: return .value(compactWatts(s.battery?.usageWatts), charging: false)
        case .charging: return .value(compactWatts(s.battery?.chargeWatts), charging: false)
        case .swap: return .value(MenuBarIndicators.compactRate(s.swapUsedBytes), charging: false)
        default: return .value(Format.percent(fraction(s)).replacingOccurrences(of: " ", with: ""), charging: isCharging(s))
        }
    }

    /// Full sentence fragment for tooltips and VoiceOver.
    func spoken(_ s: Sample) -> String {
        switch self {
        case .ram: return "RAM estimated \(Format.percent(s.ram))"
        case .battery:
            var parts = ["Battery \(Format.percent(s.battery?.fraction))"]
            switch s.battery?.state {
            case .charging: parts.append("charging")
            case .onAC: parts.append("on AC power")
            case .discharging: parts.append("on battery")
            case nil: break
            }
            if let minutes = s.battery?.minutesRemaining {
                let time = "\(minutes / 60):" + String(format: "%02d", minutes % 60)
                parts.append(s.battery?.state == .charging ? "\(time) until full" : "\(time) remaining")
            }
            return parts.joined(separator: ", ")
        case .disk: return "Disk \(Format.percent(s.disk?.usedFraction)) used, \(Format.bytes(s.disk?.freeBytes)) free"
        case .network: return "Upload \(Format.rate(s.net?.uploadBytesPerSecond)) · Download \(Format.rate(s.net?.downloadBytesPerSecond))"
        case .usage: return "Power usage \(Format.watts(s.battery?.usageWatts))"
        case .charging: return "Charging \(Format.watts(s.battery?.chargeWatts))"
        case .diskActivity: return "Disk read \(Format.rate(s.diskIO?.readBytesPerSecond)) · Disk write \(Format.rate(s.diskIO?.writeBytesPerSecond))"
        case .swap: return "Swap used \(Format.bytes(s.swapUsedBytes))"
        default: return "\(name) \(Format.percent(fraction(s)))"
        }
    }
}

/// Which gauges fill the three top positions and what sits beside the bars.
struct MetricLayout: Equatable {
    static let topKey = "topMetrics"
    static let menuBarKey = "menuBarMetric"
    static let standardTop: [Metric] = [.cpu, .gpu, .ram]

    private(set) var top: [Metric] = standardTop
    private(set) var menuBar: Metric = .network

    init() {}

    /// Anything stored that is unknown, repeated or unsupported on this Mac is dropped.
    init(storedTop: [String]?, storedMenuBar: String?, hasBattery: Bool) {
        let usable = Metric.gauges.filter { hasBattery || !$0.needsBattery }
        var picked: [Metric] = []
        for raw in storedTop ?? [] {
            if let metric = Metric(rawValue: raw), usable.contains(metric), !picked.contains(metric), picked.count < 3 {
                picked.append(metric)
            }
        }
        for metric in usable where picked.count < 3 && !picked.contains(metric) { picked.append(metric) }
        top = picked
        if let metric = storedMenuBar.flatMap(Metric.init(rawValue:)), hasBattery || !metric.needsBattery { menuBar = metric }
    }

    /// Picking a gauge already shown elsewhere swaps the two, so all three stay different.
    mutating func setTop(_ metric: Metric, at slot: Int) {
        guard metric.isGauge, top.indices.contains(slot) else { return }
        if let other = top.firstIndex(of: metric) { top[other] = top[slot] }
        top[slot] = metric
    }

    mutating func setMenuBar(_ metric: Metric) { menuBar = metric }

    /// Everything not on a tile, so each metric appears exactly once. Network has its own tray.
    func listed(hasBattery: Bool) -> [Metric] {
        Metric.available(hasBattery: hasBattery).filter { !top.contains($0) && $0 != .network }
    }

    func save(to defaults: UserDefaults) {
        defaults.set(top.map(\.rawValue), forKey: Self.topKey)
        defaults.set(menuBar.rawValue, forKey: Self.menuBarKey)
    }

    static func stored(in defaults: UserDefaults, hasBattery: Bool) -> MetricLayout {
        MetricLayout(storedTop: defaults.stringArray(forKey: topKey) ?? standardTop.map(\.rawValue),
                     storedMenuBar: defaults.string(forKey: menuBarKey), hasBattery: hasBattery)
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
        scaled(bps, units: ["B/s", "KB/s", "MB/s", "GB/s"], wholeBase: true) ?? "—"
    }
    /// Three-digit sizes drop the decimal; it says nothing at that scale.
    static func bytes(_ count: Double?) -> String {
        scaled(count, units: ["B", "KB", "MB", "GB", "TB"], wholeFrom: 100, wholeBase: true) ?? "—"
    }
    static func watts(_ value: Double?) -> String { scaled(value, units: ["W"], wholeFrom: 100) ?? "—" }

    /// Number and unit for a reading, nil when it is missing or negative. The
    /// unit steps by 1000; unit and precision are chosen after rounding, so
    /// 999 950 B/s reads "1,0 MB/s" and 99,96 W "100 W", never "1.000,0 KB/s"
    /// or "100,0 W". One decimal below `wholeFrom`, none from there on or in
    /// the first unit when `wholeBase`. `compact` drops a trailing zero
    /// decimal, grouping and the space before the unit.
    static func scaled(_ raw: Double?, units: [String], wholeFrom: Double = 1000, wholeBase: Bool = false,
                       compact: Bool = false, locale: Locale = .current) -> String? {
        guard let raw, raw.isFinite, raw >= 0 else { return nil }
        var value = raw, unit = 0
        func rounded(_ digits: Int) -> Double {
            let scale = digits == 0 ? 1 : 10.0
            return (value * scale).rounded() / scale
        }
        while true {
            let digits = (wholeBase && unit == 0) || rounded(1) >= wholeFrom ? 0 : 1
            let shown = rounded(digits)
            if shown < 1000 || unit == units.count - 1 {
                // FormatStyle keeps its formatters cached; samples arrive every second.
                let style = FloatingPointFormatStyle<Double>.number.locale(locale)
                let number = compact ? shown.formatted(style.precision(.fractionLength(0...digits)).grouping(.never))
                                     : shown.formatted(style.precision(.fractionLength(digits)))
                return number + (compact ? "" : " ") + units[unit]
            }
            value /= 1000
            unit += 1
        }
    }

    /// Splits "8,2 KB/s" or "23 %" into number and unit.
    static func split(_ text: String) -> (number: String, unit: String) {
        guard let space = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }

    static func summary(_ sample: Sample, hasBattery: Bool) -> String {
        Metric.available(hasBattery: hasBattery).map { $0.spoken(sample) }.joined(separator: " · ")
            .replacingOccurrences(of: "—", with: "Not available")
    }
}
