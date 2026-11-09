import AppKit

// MARK: - Menu bar indicators

/// What sits beside the bars: two rates, or one chosen value.
enum MenuBarReadout: Equatable {
    case rates(up: Double?, down: Double?)
    case value(String, charging: Bool)
}

// Three bars, left to right, matching the three tiles in the details. No
// letters: the position names the bar; tooltip and VoiceOver carry the full
// names. Rates are bytes per second, upload above download.
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
    /// A single value has the column to itself, so it can be read at a glance.
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    static let boltSize = NSSize(width: 5, height: 8)

    /// Track of bar 0, 1 or 2, counted from the left.
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

    /// Whole numbers from 10 up, one decimal below; nil when missing.
    static func compactNumber(_ value: Double?, locale: Locale = .current) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value < 10 ? 1 : 0
        return formatter.string(from: NSNumber(value: value))
    }

    /// Upload on top, download below; each row keeps its own measured rate.
    static func rateRows(up: Double?, down: Double?) -> [(arrow: String, text: String, y: CGFloat)] {
        [("↑", compactRate(up), 11), ("↓", compactRate(down), 0)]
    }

    /// Lightning bolt shared by the menu bar and the details.
    static func drawBolt(in box: NSRect, color: NSColor, flipped: Bool = false) {
        let shape: [(CGFloat, CGFloat)] = [(0.62, 1), (0.05, 0.42), (0.44, 0.42), (0.36, 0), (0.95, 0.6), (0.55, 0.6)]
        let path = NSBezierPath()
        for (index, point) in shape.enumerated() {
            let location = NSPoint(x: box.minX + point.0 * box.width,
                                   y: box.minY + (flipped ? 1 - point.1 : point.1) * box.height)
            if index == 0 { path.move(to: location) } else { path.line(to: location) }
        }
        path.close()
        color.setFill()
        path.fill()
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

    static func image(bars values: [Double?], readout: MenuBarReadout) -> NSImage {
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
            if case let .value(text, charging) = readout {
                let attributes: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.black]
                let textSize = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: NSPoint(x: size.width - textSize.width, y: ((size.height - textSize.height) / 2).rounded()),
                                        withAttributes: attributes)
                // Only "100%" is too wide for a bolt, and that battery is all but done charging.
                let boltX = size.width - textSize.width - boltSize.width - 1
                if charging, boltX >= barsWidth + 2 {
                    drawBolt(in: NSRect(x: boltX, y: ((size.height - boltSize.height) / 2).rounded(),
                                        width: boltSize.width, height: boltSize.height), color: .black)
                }
                return true
            }
            guard case let .rates(up, down) = readout else { return true }
            let rows = rateRows(up: up, down: down)
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
