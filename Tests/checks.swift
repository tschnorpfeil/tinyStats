extension Metrics {
    var networkBaselineTimeForCheck: TimeInterval? { prevNetTime }
}

// MARK: Live samples (measurement semantics unchanged)

let metrics = Metrics()
assert(metrics.cpu() == nil, "CPU first sample must be unavailable")
assert(metrics.network() == nil, "Network first sample must establish baseline")
let firstBaseline = metrics.networkBaselineTimeForCheck
// CPU stays nil until the kernel has counted at least one tick; wait for it
// instead of assuming one within 50 ms. The value itself is still checked.
var cpuSample: Double?
for _ in 0..<40 where cpuSample == nil {
    Thread.sleep(forTimeInterval: 0.05)
    cpuSample = metrics.cpu()
}
assert(cpuSample.map { (0...1).contains($0) } == true, "CPU sample must arrive and stay within 0...1")
let network = metrics.network()
assert(network != nil, "This Mac must expose en interfaces")
assert(metrics.networkBaselineTimeForCheck! > firstBaseline!, "Successful network sample must advance baseline")
assert(network!.downloadBytesPerSecond >= 0 && network!.uploadBytesPerSecond >= 0)
assert(metrics.ram().map { (0...1).contains($0) } == true)

// MARK: Formatting

assert(Format.percent(nil) == "—")
assert(Format.percent(.nan) == "—")
assert(Format.percent(0) == "0 %")
assert(Format.percent(1) == "100 %")
assert(Format.rate(nil) == "—")
assert(Format.rate(.nan) == "—")
assert(Format.rate(-1) == "—")
assert(Format.rate(0) == "0 B/s")
assert(Format.rate(1500).hasSuffix(" KB/s"))
assert(Format.rate(1_500_000).hasSuffix(" MB/s"))
assert(Format.rate(1_500_000_000).hasSuffix(" GB/s"))
assert(Format.split("23 %") == ("23", "%") && Format.split("8,2 KB/s") == ("8,2", "KB/s") && Format.split("—") == ("—", ""))
let summary = Format.summary(cpu: nil, gpu: 0, ram: 1, net: nil)
assert(summary.contains("CPU Nicht verfügbar") && summary.contains("GPU 0 %") && summary.contains("Download Nicht verfügbar"))
let ordered = Format.summary(cpu: 0, gpu: 0, ram: 0, net: NetworkRates(downloadBytesPerSecond: 2_000, uploadBytesPerSecond: 3_000_000))
assert(ordered.hasSuffix("Upload 3,0 MB/s · Download 2,0 KB/s") || ordered.hasSuffix("Upload 3.0 MB/s · Download 2.0 KB/s"),
       "Upload is read first and keeps its own rate")
print("PASS: live CPU/RAM/network samples, baseline regression, formatting incl. missing vs zero")

let app = NSApplication.shared

// MARK: Menu bar indicators (unchanged renderer)

assert(MenuBarIndicators.compactRate(nil) == "—")
assert(MenuBarIndicators.compactRate(.nan) == "—")
assert(MenuBarIndicators.compactRate(-1) == "—")
assert(MenuBarIndicators.compactRate(0) == "0B")
assert(MenuBarIndicators.compactRate(500) == "500B")
assert(MenuBarIndicators.compactRate(1500).hasSuffix("K"))
assert(MenuBarIndicators.compactRate(999_500).hasSuffix("M"))
assert(MenuBarIndicators.compactRate(1_500_000).hasSuffix("M"))
assert(MenuBarIndicators.compactRate(1_500_000_000).hasSuffix("G"))
assert(MenuBarIndicators.compactRate(1_000_000_000_000) == "≥1T")
assert(MenuBarIndicators.compactRate(999_500_000_000) == "1T")
for value: Double? in [nil, 0, 0.07, 0.81, 1, .nan] {
    let image = MenuBarIndicators.image(cpu: value, gpu: value, ram: value, net: nil)
    assert(image.isTemplate && image.size == NSSize(width: 88, height: 22))
    assert(image.tiffRepresentation != nil, "Indicator must actually rasterize")
}
for label in ["C", "G", "R"] {
    assert((label as NSString).size(withAttributes: [.font: MenuBarIndicators.labelFont]).width <= 9)
}
for locale in [Locale(identifier: "de_DE"), Locale(identifier: "en_US")] {
    for rate in [0.0, 999, 1500, 999_499, 999_500, 9_940_000, 999_499_999, 999_499_999_999, 999_500_000_000, 1e12] {
        let text = MenuBarIndicators.compactRate(rate, locale: locale) as NSString
        let width = text.size(withAttributes: [.font: MenuBarIndicators.rateFont]).width
        let arrowWidth = ("↓" as NSString).size(withAttributes: [.font: MenuBarIndicators.rateFont]).width
        assert(width <= 27 && width + arrowWidth + 2 <= 36, "Arrow and localized rate need at least 2pt separation")
    }
}
let rows = MenuBarIndicators.rateRows(NetworkRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 1_500_000))
assert(rows.count == 2 && rows[0].arrow == "↑" && rows[0].y > rows[1].y && rows[1].arrow == "↓",
       "Upload row on top, download row below")
assert(rows[0].text == MenuBarIndicators.compactRate(1_500_000) && rows[1].text == "0B", "Rows keep their own measured rate")
print("PASS: menu bar templates rasterize; compact units, promotion, missing values, de/en text widths, upload above download")

// MARK: Notch wing geometry (this Mac: 1470 x 956, housing 645.5...824.5, 32 pt)

let scoutScreen = NSRect(x: 0, y: 0, width: 1470, height: 956)
let scoutLeft = NSRect(x: 0, y: 924, width: 645.5, height: 32)
let scoutRight = NSRect(x: 824.5, y: 924, width: 645.5, height: 32)
let wing = NotchWing.make(screenFrame: scoutScreen, leftArea: scoutLeft, rightArea: scoutRight, topInset: 32)!
assert(wing.notch == NSRect(x: 645.5, y: 924, width: 179, height: 32))
assert(wing.wingMaxX == 824.5 + NotchWing.wingWidth && NotchWing.wingWidth == 104)
assert(wing.frame.minY == 924 && wing.frame.maxY == scoutScreen.maxY)
assert(wing.frame.minX > wing.notch.minX && wing.frame.minX < wing.notch.maxX,
       "The overlap strip stays behind the housing and never reaches the app menus left of it")
assert(wing.frame == NSRect(x: 788, y: 924, width: 148, height: 32), "Whole-point window frame (AppKit rounds origins)")
assert(wing.frame.minX + wing.junctionX == wing.notch.maxX && wing.frame.minX + wing.edgeX == wing.wingMaxX,
       "Drawing offsets keep the half-point housing edge exact")
assert(wing.frame.maxX >= wing.wingMaxX + NotchWing.topFlare && wing.frame.maxX <= scoutRight.maxX)
assert(wing.indicatorRect.minX == wing.junctionX + NotchWing.indicatorInset && wing.indicatorRect.minY == 5)
assert(NotchWing.make(screenFrame: scoutScreen, leftArea: nil, rightArea: nil, topInset: 0) == nil)
assert(NotchWing.make(screenFrame: scoutScreen, leftArea: nil, rightArea: scoutRight, topInset: 32) == nil)
assert(NotchWing.make(screenFrame: scoutScreen, leftArea: scoutLeft, rightArea: scoutRight, topInset: 0) == nil)
assert(NotchWing.make(screenFrame: scoutScreen, leftArea: scoutLeft, rightArea: .zero, topInset: 32) == nil)
assert(NotchWing.make(screenFrame: scoutScreen, leftArea: scoutLeft, rightArea: scoutRight, topInset: 20) == nil,
       "Too low a safe area must fall back")
assert(NotchWing.make(screenFrame: scoutScreen, leftArea: scoutLeft,
                      rightArea: NSRect(x: 824.5, y: 800, width: 645.5, height: 32), topInset: 32) == nil,
       "Area away from the top edge must fall back")
assert(NotchWing.make(screenFrame: scoutScreen, leftArea: NSRect(x: 0, y: 924, width: 700, height: 32),
                      rightArea: NSRect(x: 740, y: 924, width: 730, height: 32), topInset: 32) == nil,
       "A gap narrower than a camera housing is not a notch")
assert(NotchWing.make(screenFrame: scoutScreen, leftArea: scoutLeft,
                      rightArea: NSRect(x: 1370, y: 924, width: 100, height: 32), topInset: 32) == nil,
       "Too little room right of the housing must fall back")
let tallWing = NotchWing.make(screenFrame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
                              leftArea: NSRect(x: 0, y: 1079, width: 776, height: 38),
                              rightArea: NSRect(x: 952, y: 1079, width: 776, height: 38), topInset: 38)!
assert(tallWing.notch.height == 38 && tallWing.indicatorRect.minY == 8, "Height follows the real housing")
let shiftedWing = NotchWing.make(screenFrame: scoutScreen.offsetBy(dx: -1470, dy: 300),
                                 leftArea: scoutLeft.offsetBy(dx: -1470, dy: 300),
                                 rightArea: scoutRight.offsetBy(dx: -1470, dy: 300), topInset: 32)!
assert(shiftedWing.frame == wing.frame.offsetBy(dx: -1470, dy: 300), "Non-zero screen origin must be honoured")
for candidate in [wing, tallWing, shiftedWing] {
    let f = candidate.frame
    assert(f.minX == f.minX.rounded() && f.width == f.width.rounded() && f.minY == f.minY.rounded())
}
assert(NotchWing.make(screenFrame: scoutScreen.offsetBy(dx: -1470, dy: 300), leftArea: scoutLeft,
                      rightArea: scoutRight, topInset: 32) == nil, "Areas outside the given screen must not be used")
print("PASS: wing frame for real housing values, overlap only behind the housing, fallbacks, taller housing, origin")

// MARK: User acceptance: concave upper-right attachment, seamless lower-left into the housing

let edge = wing.edgeX
let flare = NotchWing.topFlare
let wingHeight = wing.notch.height
let closedWing = wing.path(attach: 0)
assert(closedWing.contains(NSPoint(x: edge - 0.4, y: wingHeight - 0.4)), "No convex radius at the upper-right corner")
assert(closedWing.contains(NSPoint(x: edge + 0.1 * flare, y: wingHeight - 0.1 * flare)) &&
       !closedWing.contains(NSPoint(x: edge + 0.35 * flare, y: wingHeight - 0.35 * flare)) &&
       closedWing.contains(NSPoint(x: edge + 0.5 * flare, y: wingHeight - 0.2)),
       "Upper-right corner is a reverse (concave) curve flaring along the top edge")
assert(!closedWing.contains(NSPoint(x: edge + 0.5, y: wingHeight / 2)), "Straight right edge below the flare")
assert(!closedWing.contains(NSPoint(x: edge - 0.4, y: 0.4)), "Free lower-right corner is convex")
assert(wing.path(attach: 1).contains(NSPoint(x: edge - 0.4, y: 0.4)), "Squared while details hang below it")
for x in stride(from: CGFloat(0.5), through: edge - NotchWing.bottomRadius - 0.5, by: 0.5) {
    assert(closedWing.contains(NSPoint(x: x, y: 0.25)), "Lower edge runs straight through the housing junction")
}
assert(NotchWing.notchOverlap >= wing.notch.height / 2, "Overlap exceeds any plausible lower housing radius")

func pixels(of view: NSView, scale: CGFloat = 2) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
                               pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}
func color(_ rep: NSBitmapImageRep, _ x: CGFloat, _ yFromTop: CGFloat) -> NSColor {
    let scale = CGFloat(rep.pixelsWide) / rep.size.width
    return rep.colorAt(x: Int(x * scale), y: Int(yFromTop * scale))!.usingColorSpace(.deviceRGB)!
}
func isBlack(_ c: NSColor) -> Bool { c.alphaComponent > 0.99 && c.redComponent < 0.01 && c.greenComponent < 0.01 && c.blueComponent < 0.01 }
func census(_ rep: NSBitmapImageRep) -> (white: Int, colored: Int) {
    var white = 0, colored = 0
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        if c.alphaComponent > 0.99, c.redComponent > 0.9, c.greenComponent > 0.9, c.blueComponent > 0.9 { white += 1 }
        if abs(c.redComponent - c.greenComponent) > 0.02 || abs(c.greenComponent - c.blueComponent) > 0.02 { colored += 1 }
    } }
    return (white, colored)
}

let wingView = WingView(frame: NSRect(origin: .zero, size: wing.frame.size))
wingView.wing = wing
wingView.indicator = MenuBarIndicators.image(cpu: 1, gpu: 0.5, ram: nil,
                                            net: NetworkRates(downloadBytesPerSecond: 1_500_000, uploadBytesPerSecond: 0))
let wingPixels = pixels(of: wingView)
assert(isBlack(color(wingPixels, edge + 1, 0.2)) && color(wingPixels, edge + 4, 3).alphaComponent < 0.01,
       "Rendered flare: black along the top edge just past the wing, open inside the reverse curve")
assert(color(wingPixels, edge + 1.5, wingHeight / 2).alphaComponent < 0.01, "Rendered straight right edge")
assert(isBlack(color(wingPixels, wing.junctionX - 4, wingHeight - 0.3)) &&
       isBlack(color(wingPixels, wing.junctionX + 4, wingHeight - 0.3)), "Rendered lower edge continuous across the junction")
assert(color(wingPixels, edge - 0.2, wingHeight - 0.2).alphaComponent < 0.01, "Rendered convex free lower-right corner")
let wingCensus = census(wingPixels)
assert(wingCensus.white > 100 && wingCensus.colored == 0, "Wing renders white on black, monochrome")
print("PASS: concave upper-right flare, straight lower edge through the housing, convex free corner (path and pixels)")

// MARK: Details layout

let height = IslandContentView.height
let notchLayout = IslandLayout.notch(wing, height: height)
assert(notchLayout.attachY == wing.notch.minY && notchLayout.frame.maxY == wing.frame.minY)
assert(!notchLayout.frame.intersects(wing.frame), "Details never overlap the wing, so source clicks reach it")
assert(notchLayout.final.upperBound == wing.wingMaxX && notchLayout.rightFillet == 0, "Right edge continues the wing")
assert(notchLayout.final.lowerBound - notchLayout.leftFillet >= wing.notch.minX + 16,
       "Left fillet meets the housing's straight lower edge, clear of its own corner")
assert(notchLayout.width >= IslandLayout.minimumWidth && notchLayout.width == 255)
assert(notchLayout.frame == NSRect(x: 663, y: 770, width: 266, height: 154), "Whole-point island window")
assert(notchLayout.frame.minX + notchLayout.finalBodyRect.maxX == wing.frame.minX + wing.edgeX,
       "Island and wing right edges coincide after whole-point rounding")
let startShape = notchLayout.shape(at: 0)
assert(startShape.height == 0 && startShape.minX == wing.notch.maxX && startShape.maxX == wing.wingMaxX,
       "Motion starts as the wing itself")
let openShape = notchLayout.shape(at: 1)
assert(openShape.minX == notchLayout.final.lowerBound && openShape.maxX == notchLayout.final.upperBound &&
       openShape.height == height && openShape.radius == IslandLayout.cornerRadius && openShape.leftFillet == IslandLayout.fillet)
let narrowWing = NotchWing.make(screenFrame: NSRect(x: 0, y: 0, width: 1024, height: 665),
                                leftArea: NSRect(x: 0, y: 633, width: 450, height: 32),
                                rightArea: NSRect(x: 574, y: 633, width: 450, height: 32), topInset: 32)!
assert(IslandLayout.notch(narrowWing, height: height).width == IslandLayout.minimumWidth,
       "Large-text scaling keeps the content width")

for layout in [notchLayout] {
    let bounds = NSRect(origin: .zero, size: layout.frame.size).insetBy(dx: -0.01, dy: -0.01)
    var p: CGFloat = 0
    while p <= 1.03 {
        let path = layout.path(at: p)
        assert(path.isEmpty || bounds.contains(path.bounds), "Silhouette stays inside its window at p=\(p)")
        assert(layout.bodyRect(at: p).maxY == layout.attachY - layout.frame.minY, "Body stays attached at p=\(p)")
        p += 0.01
    }
}
let full = notchLayout.path(at: 1)
let body = notchLayout.finalBodyRect
let fillet = IslandLayout.fillet
assert(!full.contains(NSPoint(x: body.minX + 0.5, y: body.minY + 0.5)) &&
       !full.contains(NSPoint(x: body.maxX - 0.5, y: body.minY + 0.5)), "Free lower corners convex")
assert(full.contains(NSPoint(x: body.maxX - 0.3, y: body.maxY - 0.3)), "Square below the wing")
assert(full.contains(NSPoint(x: body.minX - 0.1 * fillet, y: body.maxY - 0.1 * fillet)) &&
       !full.contains(NSPoint(x: body.minX - 0.4 * fillet, y: body.maxY - 0.4 * fillet)), "Concave fillet under the housing")

let external = NSRect(x: 0, y: 0, width: 2560, height: 1440)
let anchor = NSRect(x: 2000, y: 1413, width: 92, height: 24)
let barLayout = IslandLayout.menuBar(anchor: anchor, screen: external, visibleTop: 1410, height: height)
assert(barLayout.attachY == 1410 && barLayout.frame.maxY <= anchor.minY, "Attached at the bar edge, never over the status item")
assert(barLayout.leftFillet == fillet && barLayout.rightFillet == fillet && barLayout.width == IslandLayout.menuBarWidth)
assert(abs((barLayout.final.lowerBound + barLayout.final.upperBound) / 2 - anchor.midX) <= 0.5, "Centred under the item")
assert(IslandLayout.menuBar(anchor: anchor, screen: external, visibleTop: 1440, height: height).attachY == anchor.minY,
       "Auto-hidden bar: attach to the button edge")
let edgeLayout = IslandLayout.menuBar(anchor: NSRect(x: 2500, y: 1413, width: 56, height: 24), screen: external,
                                      visibleTop: 1410, height: height)
assert(edgeLayout.frame.maxX <= external.maxX - IslandLayout.screenMargin && edgeLayout.frame.contains(
    NSPoint(x: edgeLayout.source.upperBound - 0.5, y: edgeLayout.frame.maxY - 0.5)), "Clamped at the screen edge, source still inside")
let second = external.offsetBy(dx: -2560, dy: 0)
let secondLayout = IslandLayout.menuBar(anchor: anchor.offsetBy(dx: -2560, dy: 0), screen: second, visibleTop: 1410, height: height)
assert(secondLayout.frame == barLayout.frame.offsetBy(dx: -2560, dy: 0), "Secondary-screen origin honoured")
print("PASS: island attaches without overlapping the source, fillets/corners, bounds for all progress, fallback clamp")

// MARK: Motion

var lastWidth: CGFloat = -1
for step in 0...100 {
    let w = Choreography.widthProgress(CGFloat(step) / 100)
    assert(w >= lastWidth)
    lastWidth = w
}
assert(Choreography.widthProgress(0.8) == 1 && Choreography.contentAlpha(0.45) == 0 && Choreography.contentAlpha(0.92) == 1)
assert(Choreography.attach(0) == 0 && Choreography.attach(0.12) == 1 && Choreography.contentDrop(1) == 0)

func simulate(_ phases: [(Double, Spring.Parameters, Double)]) -> [Double] {
    var spring = Spring()
    var values = [spring.value]
    for (target, parameters, duration) in phases {
        spring.retarget(target, parameters)
        for _ in 0..<Int((duration * 60).rounded()) {
            spring.advance(by: 1.0 / 60)
            values.append(spring.value)
        }
    }
    return values
}
let opening = simulate([(1, Spring.opening, 1.5)])
assert(opening.max()! <= 1.02, "Opening overshoot stays subtle")
assert(opening.firstIndex(where: { $0 >= 0.95 })! <= 18, "Opening reaches 95 % within 300 ms")
assert(opening.last == 1, "Opening settles exactly")
let closing = simulate([(1, Spring.opening, 1.5), (0, Spring.closing, 1)]).suffix(61)
assert(closing.min()! >= -0.001 && closing.last == 0, "Closing settles at zero without undershoot")
let reversal = simulate([(1, Spring.opening, 0.12), (0, Spring.closing, 0.1), (1, Spring.opening, 1.5)])
for (a, b) in zip(reversal, reversal.dropFirst()) { assert(abs(b - a) <= 0.12, "Reversal stays continuous") }
assert(reversal.last == 1)
var stalled = Spring()
stalled.retarget(1, Spring.opening)
stalled.advance(by: 2)
assert(stalled.value < 0.5, "A stalled frame slows the motion instead of jumping to the end")
print("PASS: spring opening/closing/reversal continuity, choreography ranges, stall handling")

// MARK: Content: fixed layout, fits all states, no re-layout on samples

for width in [IslandLayout.minimumWidth, notchLayout.width, IslandLayout.menuBarWidth] {
    let content = IslandContentView(width: width)
    content.setNotchOption(available: true, enabled: true)
    let column = content.cpu.frame.width
    let widest = IslandStyle.measure(Format.percent(1), number: IslandStyle.value, unit: IslandStyle.valueUnit).size().width
    assert(widest <= column, "100 % fits a column at width \(width)")
    let rate = IslandStyle.measure(Format.rate(999_949_999), number: IslandStyle.rate, unit: IslandStyle.rateUnit).size().width
    assert(25 + rate <= content.network.frame.width / 2 - 4, "Longest rate fits half the tray at width \(width)")
    assert(content.notchSwitch.frame.maxX <= content.quitButton.frame.minX && content.notchSwitch.frame.minX >= 16 + 60,
           "Footer items do not collide at width \(width)")
    let frames = content.subviews.map(\.frame)
    for sample in [(nil, nil, nil, nil), (0.0, 0.0, 0.0, NetworkRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)),
                   (1.0, 0.99, 1.0, NetworkRates(downloadBytesPerSecond: 999_499_999, uploadBytesPerSecond: 1e12))] as [(Double?, Double?, Double?, NetworkRates?)] {
        content.update(cpu: sample.0, gpu: sample.1, ram: sample.2, net: sample.3)
        assert(content.subviews.map(\.frame) == frames, "Samples never re-layout")
    }
    for view in content.subviews { assert(content.bounds.contains(view.frame)) }
}
let controls = IslandContentView(width: notchLayout.width)
controls.setNotchOption(available: false, enabled: true)
assert(controls.notchSwitch.isHidden && !controls.notchSwitch.isEnabled)
controls.setNotchOption(available: true, enabled: false)
assert(!controls.notchSwitch.isHidden && controls.notchSwitch.isEnabled && controls.notchSwitch.state == .off)
var toggled: Bool?
controls.onNotchToggle = { toggled = $0 }
controls.notchSwitch.performClick(nil)
assert(toggled == true && controls.notchSwitch.state == .on)
var quit = 0
controls.onQuit = { quit += 1 }
controls.quitButton.performClick(nil)
assert(quit == 1 && controls.notchSwitch.accessibilityRole() == .checkBox && controls.quitButton.accessibilityRole() == .button)
assert(controls.notchSwitch.accessibilityValue() as? Int == 1)
controls.update(cpu: nil, gpu: 0, ram: 0.5, net: nil)
assert(controls.cpu.accessibilityValue() as? String == "Nicht verfügbar" && controls.gpu.accessibilityValue() as? String == "0 %")
assert((controls.network.accessibilityValue() as? String)?.contains("nicht verfügbar") == true)
let entries = NetworkView.entries(NetworkRates(downloadBytesPerSecond: 1, uploadBytesPerSecond: 2))
assert(entries.map(\.name) == ["Upload", "Download"] && entries.map(\.symbol) == ["arrow.up", "arrow.down"] &&
       entries.map(\.value) == [2, 1], "Tray reads upload first (left), each with its own rate")
controls.update(cpu: 0, gpu: 0, ram: 0, net: NetworkRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 1_000))
assert((controls.network.accessibilityValue() as? String)?.hasPrefix("Upload 1") == true)
print("PASS: content fits min/notch/menu-bar widths, no re-layout on samples, switch, quit, accessibility values")

// MARK: Interaction hit paths

typealias Route = IslandPresenter.Route
assert(IslandPresenter.route(keyCode: 53, command: false, characters: nil, inPanel: true, insideShape: true, inSource: false) == .consumeAndClose)
assert(IslandPresenter.route(keyCode: 12, command: true, characters: "q", inPanel: true, insideShape: true, inSource: false) == .quit)
assert(IslandPresenter.route(keyCode: 0, command: false, characters: "a", inPanel: true, insideShape: true, inSource: false) == .pass)
assert(IslandPresenter.route(keyCode: nil, command: false, characters: nil, inPanel: true, insideShape: true, inSource: false) == .pass)
assert(IslandPresenter.route(keyCode: nil, command: false, characters: nil, inPanel: true, insideShape: false, inSource: false) == .close)
assert(IslandPresenter.route(keyCode: nil, command: false, characters: nil, inPanel: false, insideShape: false, inSource: true) == .pass,
       "A click on the source goes to its own toggle, not to outside-close")
assert(IslandPresenter.route(keyCode: nil, command: false, characters: nil, inPanel: false, insideShape: false, inSource: false) == .close)

var wingClicks = 0
wingView.onClick = { wingClicks += 1 }
func click(_ point: NSPoint) {
    wingView.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
}
wingView.attach = 0
click(NSPoint(x: wing.hitRect.midX, y: wing.hitRect.midY))
assert(wingClicks == 1, "Visible wing opens the details")
click(NSPoint(x: 10, y: 16))
assert(wingClicks == 1, "Strip behind the housing does not open the details")
wingView.attach = 1
click(NSPoint(x: 10, y: 16))
assert(wingClicks == 2, "While open, the whole band closes")
assert(wingView.accessibilityRole() == .button && wingView.accessibilityPerformPress() && wingClicks == 3)

let wingPanel = WingPanel()
assert(wingPanel.styleMask.contains(.borderless) && wingPanel.styleMask.contains(.nonactivatingPanel))
assert(!wingPanel.isOpaque && wingPanel.backgroundColor == .clear && !wingPanel.hasShadow && !wingPanel.hidesOnDeactivate)
assert(wingPanel.level == .statusBar && !wingPanel.canBecomeKey && !wingPanel.collectionBehavior.contains(.fullScreenAuxiliary))
assert(wingPanel.constrainFrameRect(wing.frame, to: nil) == wing.frame)
wingPanel.place(wing)
assert(wingPanel.frame == wing.frame && wingPanel.wingView.wing == wing)

let presenter = IslandPresenter(content: IslandContentView(width: notchLayout.width))
let panel = presenter.panel
assert(panel.contentView === presenter.view && !presenter.isPresented && presenter.spring.isSettled)
assert(panel.styleMask.contains(.nonactivatingPanel) && panel.canBecomeKey && !panel.canBecomeMain)
assert(panel.level == .statusBar && panel.animationBehavior == .none && !panel.collectionBehavior.contains(.fullScreenAuxiliary))
assert(panel.appearance?.name == .darkAqua && !panel.isOpaque && panel.backgroundColor == .clear)
var cancelled = 0
panel.onCancel = { cancelled += 1 }
panel.cancelOperation(nil)
assert(cancelled == 1, "Escape through the responder chain also closes")
print("PASS: routing (Escape, ⌘Q, inside, outside, source), wing hit paths, panels non-activating")

// MARK: Rendered island (native offscreen render, not a live capture)

let islandContent = IslandContentView(width: notchLayout.width)
islandContent.setNotchOption(available: true, enabled: true)
islandContent.update(cpu: 0.23, gpu: 0.07, ram: 0.79, net: NetworkRates(downloadBytesPerSecond: 8_200, uploadBytesPerSecond: 4_100))
let island = IslandView(content: islandContent)
island.configure(notchLayout)
island.setProgress(0)
assert(island.subviews.first!.isHidden, "Nothing to reveal while closed")
island.setProgress(1)
assert(islandContent.alphaValue == 1 && islandContent.frame.maxY == island.subviews.first!.bounds.maxY)
let islandPixels = pixels(of: island)
assert(isBlack(color(islandPixels, body.midX, islandPixels.size.height - body.minY - 2)), "Black body")
assert(color(islandPixels, body.minX + 1, islandPixels.size.height - body.minY - 1).alphaComponent < 0.01, "Transparent outside the convex corner")
let islandCensus = census(islandPixels)
assert(islandCensus.white > 300 && islandCensus.colored == 0, "Content renders white on black, monochrome")
island.setProgress(0.3)
assert(islandContent.alphaValue == 0, "Content waits until the body has room")
print("PASS: island render monochrome, convex corners, content hidden while closed and early in the motion")
