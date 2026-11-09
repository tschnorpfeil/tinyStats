import AppKit

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
        let top = notch.maxY - frame.minY, edge = edgeX, flare = Self.topFlare
        let radius = Self.bottomRadius * (1 - min(1, max(0, attach)))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: top))
        path.line(to: NSPoint(x: edge + flare, y: top))
        path.appendArc(withCenter: NSPoint(x: edge + flare, y: top - flare), radius: flare,
                       startAngle: 90, endAngle: 180, clockwise: false)
        path.line(to: NSPoint(x: edge, y: bottomY + radius))
        if radius > 0.01 {
            path.appendArc(withCenter: NSPoint(x: edge - radius, y: bottomY + radius), radius: radius,
                           startAngle: 0, endAngle: 270, clockwise: true)
        }
        path.line(to: NSPoint(x: 0, y: bottomY))
        path.close()
        return path
    }
}

/// Where the details hang and how they grow out of their source. Global
/// coordinates; `path`, `bodyRect` and `finalBodyRect` use window coordinates.
struct IslandLayout: Equatable {
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
    var housingCapHeight: CGFloat = 0
    var isFloating: Bool = false

    /// Exact union of housing and compact wing: neither outer edge moves.
    /// Overlap the fractional lower edge to avoid a seam between windows.
    static func notch(_ wing: NotchWing, height: CGFloat) -> IslandLayout {
        IslandLayout(attachY: wing.notch.minY.rounded(.up), source: wing.notch.maxX...wing.wingMaxX,
                     final: wing.notch.minX...wing.wingMaxX, height: height, housingCapHeight: wing.notch.maxY - wing.notch.minY.rounded(.up))
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
                            height: height, isFloating: true)
    }

    var width: CGFloat { final.upperBound - final.lowerBound }

    /// Whole-point frame; notch mode also covers the housing cutout above the attach line.
    var frame: NSRect {
        let minX = min(source.lowerBound, final.lowerBound).rounded(.down)
        let maxX = max(source.upperBound, final.upperBound).rounded(.up)
        let top = (attachY + housingCapHeight).rounded(.up)
        let bottom = (attachY - height - Self.headroom).rounded(.down)
        return NSRect(x: minX, y: bottom, width: maxX - minX, height: top - bottom)
    }

    struct Shape: Equatable {
        var minX: CGFloat, maxX: CGFloat, height: CGFloat, radius: CGFloat
    }

    func shape(at progress: CGFloat) -> Shape {
        let grow = Choreography.widthProgress(progress)
        let minX = source.lowerBound + (final.lowerBound - source.lowerBound) * grow
        let maxX = source.upperBound + (final.upperBound - source.upperBound) * grow
        let h = min(height + Self.headroom, max(0, height * progress))
        return Shape(minX: minX, maxX: maxX, height: h, radius: min(Self.cornerRadius, (maxX - minX) / 2, h))
    }

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
        path.move(to: NSPoint(x: left, y: top))
        path.line(to: NSPoint(x: right, y: top))
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
        path.close()
        // Fill the housing's lower-left rounded cutout as the island reaches
        // its left edge. The cap stays strictly inside the housing bounds;
        // the wing's visible width and the content position do not change.
        let capRight = min(source.lowerBound, s.maxX) - frame.minX
        if housingCapHeight > 0, capRight > left {
            path.appendRect(NSRect(x: left, y: top, width: capRight - left, height: housingCapHeight))
        }
        return path
    }
}

// MARK: - Motion

/// Pure functions of the presentation progress (0 closed, 1 open; the
/// spring keeps it inside that range). Drawing, reversals and render checks share them.
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

/// Critically damped spring on the progress (Apple's `duration`/`bounce`
/// model with bounce 0, i.e. `.smooth(duration:)`): it eases out without any
/// overshoot or rebound, and the value is clamped to 0...1 as a hard guard.
/// Retargeting keeps value and velocity, so a reversal continues from
/// wherever the shape is.
struct Spring {
    struct Parameters: Equatable {
        /// Perceptual duration: one undamped period, 2π / ω.
        var response: Double
        /// Damping ratio ζ; 1 is critical damping, the fastest motion that
        /// never overshoots.
        var damping: Double
    }
    // From rest, critical damping reaches 95 % after 0.755 × response and
    // settles below half a per-mille after 1.47 × response. Opening: 95 % at
    // ~240 ms; closing is quicker: 95 % at ~180 ms. The choreography fades the
    // content in over the last part of opening and out first when closing.
    static let opening = Parameters(response: 0.32, damping: 1)
    static let closing = Parameters(response: 0.24, damping: 1)

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
            // Hard guard against any overshoot, including fast double reversals.
            if value < 0 || value > 1 {
                value = min(max(value, 0), 1)
                velocity = 0
            }
            remaining -= step
        }
        // Snap once the remainder is below a third of a point on the widest panel.
        if abs(value - target) < 0.001, abs(velocity) < 0.05 {
            value = target
            velocity = 0
        }
    }
}
