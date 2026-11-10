import AppKit

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
    static let listLabel = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let listValue = rounded(12, .semibold)
    static let boltSize = NSSize(width: 6, height: 9)

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

    /// Tile captions and category headings.
    static func heading(_ string: String) -> NSAttributedString { text(string, caption, secondary, kern: 0.4) }

    /// Number with a smaller unit on the same baseline; a dim dash when missing.
    static func measure(_ formatted: String, number: NSFont, unit: NSFont) -> NSAttributedString {
        let parts = Format.split(formatted)
        let result = NSMutableAttributedString(attributedString:
            text(parts.number, number, parts.unit.isEmpty ? secondary : primary))
        if !parts.unit.isEmpty { result.append(text("\u{2009}" + parts.unit, unit, secondary)) }
        return result
    }

    /// Label with a charging bolt after it when `bolt`.
    static func drawLabel(_ label: NSAttributedString, at origin: NSPoint, bolt: Bool) {
        label.draw(at: origin)
        guard bolt else { return }
        MenuBarIndicators.drawBolt(in: NSRect(origin: NSPoint(x: origin.x + ceil(label.size().width) + 3, y: origin.y + 2),
                                              size: boltSize), color: secondary, flipped: true)
    }

    /// SF Symbol, centred vertically in `row` of a flipped view.
    static func drawSymbol(_ name: String, _ configuration: NSImage.SymbolConfiguration, x: CGFloat, in row: NSRect,
                           alignRight: Bool = false) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        else { return }
        image.draw(in: centered(image.size, x: x, in: row, alignRight: alignRight),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    static func drawCentered(_ text: NSAttributedString, x: CGFloat, in row: NSRect, alignRight: Bool = false) {
        let size = text.size()
        text.draw(in: centered(NSSize(width: ceil(size.width), height: ceil(size.height)), x: x, in: row, alignRight: alignRight))
    }

    /// Starts at `x`, or ends there when `alignRight`; whole-point vertical centring keeps text crisp.
    private static func centered(_ size: NSSize, x: CGFloat, in row: NSRect, alignRight: Bool) -> NSRect {
        NSRect(x: alignRight ? x - size.width : x, y: row.minY + ((row.height - size.height) / 2).rounded(),
               width: size.width, height: size.height)
    }
}

/// Flipped view that draws its text itself and reads as one text to VoiceOver.
class ReadoutView: NSView {
    init(label: String) {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
}

/// Caption, value and a thin proportional meter for one gauge.
final class MetricView: ReadoutView {
    static let height: CGFloat = 50
    var metric: Metric { didSet { if metric != oldValue { describeMetric(); needsDisplay = true } } }
    var sample = Sample() { didSet { if sample != oldValue { needsDisplay = true } } }
    var value: Double? { metric.fraction(sample) }
    var charging: Bool { metric.isCharging(sample) }

    init(metric: Metric) {
        self.metric = metric
        super.init(label: metric.name)
        describeMetric()
    }

    required init?(coder: NSCoder) { nil }

    override func accessibilityValue() -> Any? {
        Format.percent(value).replacingOccurrences(of: "—", with: "Not available") + (charging ? ", charging" : "")
    }

    private func describeMetric() {
        setAccessibilityLabel(metric == .ram ? "RAM estimated" : metric.name)
        switch metric {
        case .ram: toolTip = "Estimated usage: app, wired and compressed memory, like Memory Used in Activity Monitor. Not memory pressure."
        case .disk: toolTip = "Used space on the startup disk."
        default: toolTip = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        IslandStyle.drawLabel(IslandStyle.heading(metric.caption), at: .zero, bolt: charging)
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
final class NetworkView: ReadoutView {
    static let height: CGFloat = 30
    var rates: NetworkRates? { didSet { needsDisplay = true } }
    private static let arrow = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [IslandStyle.secondary]))

    convenience init() { self.init(label: "Network") }

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
            IslandStyle.drawSymbol(entry.symbol, Self.arrow, x: x, in: bounds)
            IslandStyle.drawCentered(IslandStyle.measure(Format.rate(entry.value), number: IslandStyle.rate,
                                                         unit: IslandStyle.rateUnit), x: x + 14, in: bounds)
        }
    }
}

/// One labelled column per category, on the same grid as the tiles, for every
/// metric not on a tile. No category ever holds more than `rows` cells, so
/// neither a sample nor a new choice can change the height.
final class MetricListView: ReadoutView {
    static let headerHeight: CGFloat = 17
    static let rowHeight: CGFloat = 30
    static let rows = 3
    static let height: CGFloat = headerHeight + CGFloat(rows) * rowHeight
    var metrics: [Metric] = [] { didSet { if metrics != oldValue { needsDisplay = true } } }
    var sample = Sample() { didSet { if sample != oldValue { needsDisplay = true } } }

    convenience init() { self.init(label: "More metrics") }

    /// Numbers carry a smaller unit, like the tiles and tray; a missing value is a dim dash.
    static func valueText(_ text: String) -> NSAttributedString {
        IslandStyle.measure(text, number: IslandStyle.listValue, unit: IslandStyle.rateUnit)
    }

    var details: String {
        Metric.grouped(metrics).map { group in
            "\(group.category.rawValue): " + group.metrics.map { $0.spoken(sample) }.joined(separator: ", ")
        }.joined(separator: "; ").replacingOccurrences(of: "—", with: "not available")
    }

    override func accessibilityValue() -> Any? { details }
    override var toolTip: String? { get { details } set {} }

    override func draw(_ dirtyRect: NSRect) {
        let column = IslandContentView.columnWidth(inner: bounds.width)
        for (index, group) in Metric.grouped(metrics).enumerated() {
            let x = CGFloat(index) * (column + IslandContentView.columnGap)
            IslandStyle.heading(group.category.rawValue.uppercased()).draw(at: NSPoint(x: x, y: 0))
            for (row, cell) in group.metrics.flatMap({ $0.cells(sample) }).enumerated() {
                let y = Self.headerHeight + CGFloat(row) * Self.rowHeight
                IslandStyle.drawLabel(IslandStyle.text(cell.label, IslandStyle.listLabel, IslandStyle.secondary),
                                      at: NSPoint(x: x, y: y), bolt: cell.bolt)
                Self.valueText(cell.value).draw(at: NSPoint(x: x, y: y + 12))
            }
        }
    }
}

/// Quiet text action that brightens under the pointer.
final class TextButton: NSButton {
    private var hovering = false { didSet { needsDisplay = true } }
    private var symbol: String?

    convenience init(label: String, symbol: String? = nil) {
        self.init(frame: .zero)
        title = label
        self.symbol = symbol
        isBordered = false
        focusRingType = .none
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        // `.inVisibleRect` follows every frame change, so one area is enough.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let color = hovering || isHighlighted ? IslandStyle.primary : IslandStyle.secondary
        if let symbol {
            IslandStyle.drawSymbol(symbol, NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color])), x: bounds.maxX, in: bounds, alignRight: true)
            return
        }
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
    static let listTop: CGFloat = networkTop + NetworkView.height + 12
    static let footerTop: CGFloat = listTop + MetricListView.height + 8
    static let footerHeight: CGFloat = 16
    static let height: CGFloat = footerTop + footerHeight + 12

    /// The tiles and the category columns share one grid.
    static func columnWidth(inner: CGFloat) -> CGFloat { ((inner - 2 * columnGap) / 3).rounded(.down) }

    let hasBattery: Bool
    private(set) var metricLayout = MetricLayout()
    let tiles = MetricLayout.standardTop.map { MetricView(metric: $0) }
    let network = NetworkView()
    let list = MetricListView()
    let customizeButton = TextButton(label: "Settings", symbol: "gearshape")
    let quitButton = TextButton(label: "Quit")
    private var notchAvailable = false
    private var notchEnabled = false
    var onNotchToggle: ((Bool) -> Void)?
    var onLayoutChange: ((MetricLayout) -> Void)?

    init(width: CGFloat, hasBattery: Bool) {
        self.hasBattery = hasBattery
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        wantsLayer = true
        canDrawSubviewsIntoLayer = true
        customizeButton.target = self
        customizeButton.action = #selector(customizeClicked)
        customizeButton.toolTip = "Settings"
        quitButton.target = NSApplication.shared
        quitButton.action = #selector(NSApplication.terminate(_:))
        quitButton.setAccessibilityLabel("Quit tinyStats")
        quitButton.toolTip = "Quit tinyStats (⌘Q)"
        (tiles as [NSView] + [network, list, customizeButton, quitButton]).forEach(addSubview)
        list.metrics = metricLayout.listed(hasBattery: hasBattery)
        layout(width: width)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func layout(width: CGFloat) {
        setFrameSize(NSSize(width: width, height: Self.height))
        let inner = width - 2 * Self.padding
        let column = Self.columnWidth(inner: inner)
        for (index, view) in tiles.enumerated() {
            view.frame = NSRect(x: Self.padding + CGFloat(index) * (column + Self.columnGap), y: Self.metricsTop,
                                width: column, height: MetricView.height)
        }
        network.frame = NSRect(x: Self.padding, y: Self.networkTop, width: inner, height: NetworkView.height)
        list.frame = NSRect(x: Self.padding, y: Self.listTop, width: inner, height: MetricListView.height)
        quitButton.frame = NSRect(x: width - Self.padding - 30, y: Self.footerTop, width: 30, height: Self.footerHeight)
        customizeButton.frame = NSRect(x: quitButton.frame.minX - 8 - 16, y: Self.footerTop, width: 16, height: Self.footerHeight)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
        let mark = NSMutableAttributedString(attributedString: IslandStyle.text("tiny", IslandStyle.footer, IslandStyle.tertiary))
        mark.append(IslandStyle.text("Stats", NSFont.systemFont(ofSize: 11, weight: .semibold), IslandStyle.secondary))
        IslandStyle.drawCentered(mark, x: Self.padding,
                                 in: NSRect(x: 0, y: Self.footerTop, width: bounds.width, height: Self.footerHeight))
    }

    func update(_ sample: Sample) {
        tiles.forEach { $0.sample = sample }
        network.rates = sample.net
        list.sample = sample
    }

    /// The set of cells stays the same size, so the island keeps its frame.
    func setMetricLayout(_ layout: MetricLayout) {
        metricLayout = layout
        for (tile, metric) in zip(tiles, layout.top) { tile.metric = metric }
        list.metrics = layout.listed(hasBattery: hasBattery)
    }

    private static let menuBarSlot = 3
    static let notchOptionTitle = "Show Beside Notch"

    /// One native menu: a submenu per tile, one for the menu bar, the notch
    /// option where a display has one, and a way back to the default metrics.
    func customizationMenu() -> NSMenu {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        menu.autoenablesItems = false
        func submenu(_ title: String, slot: Int, current: Metric, choices: [Metric], sections: Bool = false) {
            let parent = NSMenuItem(title: "\(title): \(current.name)", action: nil, keyEquivalent: "")
            let choicesMenu = NSMenu()
            choicesMenu.autoenablesItems = false
            var section: MetricCategory?
            for metric in choices {
                if sections, let category = metric.category, category != section {
                    choicesMenu.addItem(.sectionHeader(title: category.rawValue))
                    section = category
                }
                let item = NSMenuItem(title: metric.name, action: #selector(metricPicked(_:)), keyEquivalent: "")
                item.target = self
                item.tag = slot
                item.representedObject = metric
                item.state = metric == current ? .on : .off
                choicesMenu.addItem(item)
            }
            parent.submenu = choicesMenu
            menu.addItem(parent)
        }
        for (slot, title) in ["Top Left", "Top Middle", "Top Right"].enumerated() {
            submenu(title, slot: slot, current: metricLayout.top[slot], choices: Metric.gauges(hasBattery: hasBattery))
        }
        menu.addItem(.separator())
        let others = Metric.available(hasBattery: hasBattery).filter { $0 != .network }
        submenu("Menu Bar", slot: Self.menuBarSlot, current: metricLayout.menuBar,
                choices: [.network] + Metric.grouped(others).flatMap { $0.metrics }, sections: true)
        if notchAvailable {
            let notch = NSMenuItem(title: Self.notchOptionTitle, action: #selector(notchToggled), keyEquivalent: "")
            notch.target = self
            notch.state = notchEnabled ? .on : .off
            menu.addItem(notch)
        }
        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset to Defaults", action: #selector(resetPicked), keyEquivalent: "")
        reset.target = self
        reset.isEnabled = metricLayout != MetricLayout()
        menu.addItem(reset)
        menu.addItem(.separator())
        // tinyStats itself makes no network connections; the browser shows the latest release.
        let updates = NSMenuItem(title: Self.updatesTitle, action: #selector(updatesPicked), keyEquivalent: "")
        updates.target = self
        updates.toolTip = Self.versionLine
        menu.addItem(updates)
        return menu
    }

    static let updatesTitle = "Check for Updates…"
    static let releasesURL = URL(string: "https://github.com/tschnorpfeil/tinyStats/releases/latest")!
    static var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "Installed: tinyStats \($0)" } ?? "Installed: development build"
    }

    @objc private func updatesPicked() { NSWorkspace.shared.open(Self.releasesURL) }

    private func change(_ layout: MetricLayout) {
        guard layout != metricLayout else { return }
        setMetricLayout(layout)
        onLayoutChange?(layout)
    }

    @objc private func metricPicked(_ item: NSMenuItem) {
        guard let metric = item.representedObject as? Metric else { return }
        var layout = metricLayout
        if item.tag == Self.menuBarSlot { layout.menuBar = metric } else { layout.setTop(metric, at: item.tag) }
        change(layout)
    }

    @objc private func resetPicked() { change(MetricLayout()) }

    @objc private func customizeClicked() {
        customizationMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: customizeButton.bounds.maxY + 4), in: customizeButton)
    }

    /// The menu offers this only while a connected display has a usable housing.
    func setNotchOption(available: Bool, enabled: Bool) {
        notchAvailable = available
        notchEnabled = enabled
    }

    @objc private func notchToggled() {
        notchEnabled.toggle()
        onNotchToggle?(notchEnabled)
    }
}
