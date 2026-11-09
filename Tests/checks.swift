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
assert(summary.contains("CPU Not available") && summary.contains("GPU 0 %") && summary.contains("Download Not available"))
let ordered = Format.summary(cpu: 0, gpu: 0, ram: 0, net: NetworkRates(downloadBytesPerSecond: 2_000, uploadBytesPerSecond: 3_000_000))
assert(ordered.hasSuffix("Upload 3,0 MB/s · Download 2,0 KB/s") || ordered.hasSuffix("Upload 3.0 MB/s · Download 2.0 KB/s"),
       "Upload is read first and keeps its own rate")
print("PASS: live CPU/RAM/network samples, baseline regression, formatting incl. missing vs zero")

let app = NSApplication.shared

// MARK: Menu bar indicators: three bars without letters, then upload over download

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
let indicatorSize = MenuBarIndicators.size
assert(indicatorSize.width == MenuBarIndicators.barsWidth + MenuBarIndicators.groupGap + MenuBarIndicators.rateColumn &&
       indicatorSize.width <= 60, "Without letters the image is bars, one gap and the rate column, nothing else")
assert(NotchWing.wingWidth == NotchWing.indicatorInset + indicatorSize.width + 10, "The wing shrinks with the image")
for value: Double? in [nil, 0, 0.07, 0.81, 1, .nan] {
    let image = MenuBarIndicators.image(cpu: value, gpu: value, ram: value, net: nil)
    assert(image.isTemplate && image.size == indicatorSize)
}
let rateColumn = MenuBarIndicators.rateColumn
for locale in [Locale(identifier: "de_DE"), Locale(identifier: "en_US")] {
    for rate in [0.0, 999, 1500, 999_499, 999_500, 9_940_000, 999_499_999, 999_499_999_999, 999_500_000_000, 1e12] {
        let text = MenuBarIndicators.compactRate(rate, locale: locale) as NSString
        let width = text.size(withAttributes: [.font: MenuBarIndicators.rateFont]).width
        let arrowWidth = MenuBarIndicators.arrowSize.width
        assert(width + arrowWidth + 2 <= rateColumn, "Arrow and localized rate need at least 2pt separation")
    }
}
let rows = MenuBarIndicators.rateRows(NetworkRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 1_500_000))
assert(rows.count == 2 && rows[0].arrow == "↑" && rows[0].y > rows[1].y && rows[1].arrow == "↓",
       "Upload row on top, download row below")
assert(rows[0].text == MenuBarIndicators.compactRate(1_500_000) && rows[1].text == "0B", "Rows keep their own measured rate")

/// Alpha of the template at 2x; `ink` averages it over a rect in image points.
func alphaMap(_ image: NSImage) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: Int(image.size.height * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
func ink(_ rep: NSBitmapImageRep, _ rect: NSRect) -> (mean: CGFloat, max: CGFloat) {
    var sum: CGFloat = 0, peak: CGFloat = 0, count: CGFloat = 0
    let top = rep.size.height
    for py in Int((top - rect.maxY) * 2)..<Int((top - rect.minY) * 2) {
        for px in Int(rect.minX * 2)..<Int(rect.maxX * 2) {
            let a = rep.colorAt(x: px, y: py)!.alphaComponent
            sum += a; peak = max(peak, a); count += 1
        }
    }
    return (sum / max(count, 1), peak)
}
let fullBars = alphaMap(MenuBarIndicators.image(cpu: 1, gpu: 1, ram: 1, net: nil))
var runs: [Int] = [], inRun = false
for px in 0..<Int(MenuBarIndicators.barsWidth * 2) {
    let column = ink(fullBars, NSRect(x: CGFloat(px) / 2, y: 4, width: 0.5, height: 14)).mean
    if column > 0.85 { if !inRun { runs.append(0) }; runs[runs.count - 1] += 1; inRun = true }
    else { assert(column < 0.01, "Bars have clean gaps"); inRun = false }
}
assert(runs == [8, 8, 8], "Exactly three narrow bars, each \(MenuBarIndicators.barWidth) pt")
assert(ink(fullBars, NSRect(x: MenuBarIndicators.barsWidth, y: 0, width: MenuBarIndicators.groupGap, height: 22)).max == 0,
       "Nothing between the bars and the rates")
let mixed = alphaMap(MenuBarIndicators.image(cpu: 1, gpu: 0, ram: nil, net: nil))
let cpuBar = MenuBarIndicators.track(0), gpuBar = MenuBarIndicators.track(1), ramBar = MenuBarIndicators.track(2)
assert(ink(mixed, cpuBar.insetBy(dx: 1, dy: 2)).mean > 0.95, "CPU (left) full at 100 %")
let gpuInk = ink(mixed, gpuBar.insetBy(dx: 1, dy: 2))
assert(gpuInk.max > 0.15 && gpuInk.max < 0.35, "GPU (middle) at 0 %: the empty track, nothing filled")
assert(ink(mixed, NSRect(x: ramBar.minX, y: ramBar.minY, width: ramBar.width, height: 5)).max == 0 &&
       ink(mixed, NSRect(x: ramBar.minX, y: ramBar.maxY - 5, width: ramBar.width, height: 5)).max == 0 &&
       ink(mixed, NSRect(x: ramBar.minX, y: ramBar.midY - 1, width: ramBar.width, height: 2)).max > 0.5,
       "RAM (right) missing: a dash instead of the track, distinct from 0 %")
let half = alphaMap(MenuBarIndicators.image(cpu: 0.5, gpu: nil, ram: nil, net: nil))
assert(ink(half, NSRect(x: cpuBar.minX + 1, y: cpuBar.minY + 1, width: 2, height: 5)).mean > 0.95 &&
       ink(half, NSRect(x: cpuBar.minX + 1, y: cpuBar.maxY - 6, width: 2, height: 5)).max < 0.35, "Fill height follows the value")
let rates = alphaMap(MenuBarIndicators.image(cpu: nil, gpu: nil, ram: nil,
                                             net: NetworkRates(downloadBytesPerSecond: 999_000_000, uploadBytesPerSecond: 0)))
let rateX = MenuBarIndicators.barsWidth + MenuBarIndicators.groupGap
func inkWidth(_ y: CGFloat) -> CGFloat {
    var columns: CGFloat = 0
    for px in Int(rateX * 2)..<Int(indicatorSize.width * 2) where ink(rates, NSRect(x: CGFloat(px) / 2, y: y, width: 0.5, height: 11)).max > 0.3 {
        columns += 0.5
    }
    return columns
}
assert(inkWidth(11) < inkWidth(0), "Upload (0B, top) and download (999M, bottom) drawn in their own rows")
print("PASS: indicator without letters: three bars CPU/GPU/RAM left to right, nil vs 0 in pixels, compact rates, upload above download")

// MARK: Notch wing geometry (this Mac: 1470 x 956, housing 645.5...824.5, safe area 32 pt)

let scoutScreen = NSRect(x: 0, y: 0, width: 1470, height: 956)
let scoutLeft = NSRect(x: 0, y: 924, width: 645.5, height: 32)
let scoutRight = NSRect(x: 824.5, y: 924, width: 645.5, height: 32)
let publicWing = NotchWing.make(screenFrame: scoutScreen, leftArea: scoutLeft, rightArea: scoutRight, topInset: 32)!
assert(publicWing.notch == NSRect(x: 645.5, y: 924, width: 179, height: 32), "Without an outline: the public values")
assert(publicWing.frame == NSRect(x: 788, y: 924, width: 118, height: 32) && publicWing.bottomY == 0)

/// Display outline like this Mac's `bezelPath` (global points): housing sides at
/// the public edges, lower edge at `bottom`, rounded lower corners whose control
/// points dip below that edge (continuous corners), concave top shoulders.
func outline(_ screen: NSRect, left: CGFloat, right: CGFloat, bottom: CGFloat, dip: CGFloat = 0.09) -> NSBezierPath {
    let top = screen.maxY, r: CGFloat = 14.6, shoulder: CGFloat = 6.9
    let path = NSBezierPath()
    path.move(to: NSPoint(x: screen.minX, y: screen.minY))
    path.line(to: NSPoint(x: screen.maxX, y: screen.minY))
    path.line(to: NSPoint(x: screen.maxX, y: top))
    path.line(to: NSPoint(x: right + shoulder, y: top))
    path.curve(to: NSPoint(x: right, y: top - shoulder), controlPoint1: NSPoint(x: right + 2, y: top),
               controlPoint2: NSPoint(x: right, y: top - 2))
    path.line(to: NSPoint(x: right, y: bottom + r))
    path.curve(to: NSPoint(x: right - r, y: bottom), controlPoint1: NSPoint(x: right, y: bottom + 5),
               controlPoint2: NSPoint(x: right - 8, y: bottom - dip))
    path.line(to: NSPoint(x: left + r, y: bottom))
    path.curve(to: NSPoint(x: left, y: bottom + r), controlPoint1: NSPoint(x: left + 8, y: bottom - dip),
               controlPoint2: NSPoint(x: left, y: bottom + 5))
    path.line(to: NSPoint(x: left, y: top - shoulder))
    path.curve(to: NSPoint(x: left - shoulder, y: top), controlPoint1: NSPoint(x: left, y: top - 2),
               controlPoint2: NSPoint(x: left - 2, y: top))
    path.line(to: NSPoint(x: screen.minX, y: top))
    path.close()
    return path
}
let housingBottom: CGFloat = 923.8335
let scoutOutline = outline(scoutScreen, left: 645.42, right: 824.58, bottom: housingBottom)
let publicNotch = publicWing.notch
assert(HousingOutline.bottom(in: scoutOutline, screenFrame: scoutScreen, notch: publicNotch) == housingBottom,
       "Lower edge from the outline's vertices")
assert(HousingOutline.bottom(in: outline(scoutScreen, left: 645.42, right: 824.58, bottom: housingBottom, dip: 3),
                             screenFrame: scoutScreen, notch: publicNotch) == housingBottom, "Control points never count")
let shiftedScreen = scoutScreen.offsetBy(dx: -1470, dy: 300)
assert(HousingOutline.bottom(in: scoutOutline, screenFrame: shiftedScreen, notch: publicNotch.offsetBy(dx: -1470, dy: 300))
       == housingBottom + 300, "Screen-local outline moved to global coordinates")
assert(HousingOutline.bottom(in: NSBezierPath(rect: scoutScreen), screenFrame: scoutScreen, notch: publicNotch) == nil,
       "An outline without a housing is ignored")
assert(HousingOutline.bottom(in: outline(scoutScreen, left: 645.42, right: 824.58, bottom: 922), screenFrame: scoutScreen,
                             notch: publicNotch) == nil, "An outline that disagrees with the safe area is ignored")
assert(HousingOutline.bottom(in: scoutOutline, screenFrame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
                             notch: publicNotch) == nil, "An outline for another screen size is ignored")
if let screen = NSScreen.screens.first, let live = HousingOutline.outline(of: screen),
   let liveWing = NotchWing.make(screenFrame: screen.frame, leftArea: screen.auxiliaryTopLeftArea,
                                 rightArea: screen.auxiliaryTopRightArea, topInset: screen.safeAreaInsets.top, outline: live) {
    let safeBottom = screen.frame.maxY - screen.safeAreaInsets.top
    assert(abs(liveWing.notch.minY - safeBottom) <= 1)
    print("INFO: this display's housing lower edge \(liveWing.notch.minY) pt (safe area \(safeBottom)), wing frame \(liveWing.frame)")
}

let wing = NotchWing.make(screenFrame: scoutScreen, leftArea: scoutLeft, rightArea: scoutRight, topInset: 32, outline: scoutOutline)!
assert(wing.notch == NSRect(x: 645.5, y: housingBottom, width: 179, height: 956 - housingBottom))
assert(wing.wingMaxX == 824.5 + NotchWing.wingWidth)
assert(wing.frame == NSRect(x: 788, y: 923, width: 118, height: 33),
       "Whole-point window from the point row holding the housing's lower edge to the top")
assert(wing.frame.minY + wing.bottomY == housingBottom && wing.frame.maxY == scoutScreen.maxY,
       "Lower edge exactly on the housing's lower edge, not on the rounded safe area")
assert(wing.frame.minX > wing.notch.minX && wing.frame.minX < wing.notch.maxX,
       "The overlap strip stays behind the housing and never reaches the app menus left of it")
assert(wing.frame.minX + wing.junctionX == wing.notch.maxX && wing.frame.minX + wing.edgeX == wing.wingMaxX,
       "Drawing offsets keep the half-point housing edge exact")
assert(wing.frame.maxX >= wing.wingMaxX + NotchWing.topFlare && wing.frame.maxX <= scoutRight.maxX)
assert(wing.frame.minY + wing.indicatorRect.minY == publicWing.frame.minY + publicWing.indicatorRect.minY &&
       wing.indicatorRect.minX == wing.junctionX + NotchWing.indicatorInset, "The indicator does not move")
assert(wing.hitRect.minY == wing.bottomY, "Hit area is the visible wing")

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
                      rightArea: NSRect(x: 1400, y: 924, width: 70, height: 32), topInset: 32) == nil,
       "Too little room right of the housing must fall back")
let tallWing = NotchWing.make(screenFrame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
                              leftArea: NSRect(x: 0, y: 1079, width: 776, height: 38),
                              rightArea: NSRect(x: 952, y: 1079, width: 776, height: 38), topInset: 38)!
assert(tallWing.notch.height == 38 && tallWing.indicatorRect.minY == 8, "Height follows the real housing")
let shiftedWing = NotchWing.make(screenFrame: shiftedScreen, leftArea: scoutLeft.offsetBy(dx: -1470, dy: 300),
                                 rightArea: scoutRight.offsetBy(dx: -1470, dy: 300), topInset: 32,
                                 outline: outline(NSRect(origin: .zero, size: scoutScreen.size), left: 645.42, right: 824.58,
                                                  bottom: housingBottom))!
assert(shiftedWing.frame == wing.frame.offsetBy(dx: -1470, dy: 300) && shiftedWing.bottomY == wing.bottomY,
       "Non-zero screen origin must be honoured")
for candidate in [wing, publicWing, tallWing, shiftedWing] {
    for f in [candidate.frame, candidate.frame] {
        assert(f.minX == f.minX.rounded() && f.width == f.width.rounded() && f.minY == f.minY.rounded() && f.height == f.height.rounded())
    }
}
assert(NotchWing.make(screenFrame: shiftedScreen, leftArea: scoutLeft,
                      rightArea: scoutRight, topInset: 32) == nil, "Areas outside the given screen must not be used")
print("PASS: housing lower edge from the outline (vertices, local/global, rejects), wing frames, indicator fixed, fallbacks")

// MARK: User acceptance: concave upper-right attachment, seamless lower-left into the housing, flush lower edge

let edge = wing.edgeX
let flare = NotchWing.topFlare
let wingTop = wing.frame.height
let lowerEdge = wing.bottomY
let closedWing = wing.path(attach: 0)
assert(closedWing.contains(NSPoint(x: edge - 0.4, y: wingTop - 0.4)), "No convex radius at the upper-right corner")
assert(closedWing.contains(NSPoint(x: edge + 0.1 * flare, y: wingTop - 0.1 * flare)) &&
       !closedWing.contains(NSPoint(x: edge + 0.35 * flare, y: wingTop - 0.35 * flare)) &&
       closedWing.contains(NSPoint(x: edge + 0.5 * flare, y: wingTop - 0.2)),
       "Upper-right corner is a reverse (concave) curve flaring along the top edge")
assert(!closedWing.contains(NSPoint(x: edge + 0.5, y: wingTop / 2)), "Straight right edge below the flare")
assert(!closedWing.contains(NSPoint(x: edge - 0.4, y: lowerEdge + 0.4)), "Free lower-right corner is convex")
assert(wing.path(attach: 1).contains(NSPoint(x: edge - 0.4, y: lowerEdge + 0.4)), "Squared while details hang below it")
for x in stride(from: CGFloat(0.5), through: edge - NotchWing.bottomRadius - 0.5, by: 0.5) {
    assert(closedWing.contains(NSPoint(x: x, y: lowerEdge + 0.05)) && !closedWing.contains(NSPoint(x: x, y: lowerEdge - 0.05)),
           "Lower edge runs straight through the junction exactly on the housing's lower edge")
}
assert(NotchWing.notchOverlap >= wing.notch.height / 2, "Overlap exceeds any plausible lower housing radius")
let spreadWing = wing.path(attach: 1)
let openEdge = wing.wingMaxX - wing.frame.minX
assert(spreadWing.contains(NSPoint(x: openEdge - 0.4, y: lowerEdge + 0.4)) && !spreadWing.contains(NSPoint(x: openEdge + 0.5, y: wingTop / 2)) &&
       spreadWing.contains(NSPoint(x: openEdge + 0.1 * flare, y: wingTop - 0.1 * flare)), "Attached wing keeps the flare and the straight edge")

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
assert(color(wingPixels, edge + 1.5, wingTop / 2).alphaComponent < 0.01, "Rendered straight right edge")
let lowRow = wingTop - lowerEdge - 0.3
assert(isBlack(color(wingPixels, wing.junctionX - 4, lowRow)) && isBlack(color(wingPixels, wing.junctionX + 4, lowRow)),
       "Rendered lower edge continuous across the junction")
assert(color(wingPixels, edge - 0.2, wingTop - lowerEdge - 0.2).alphaComponent < 0.01, "Rendered convex free lower-right corner")
// The partly covered pixel row places the antialiased edge where the housing ends (within 1/20 pt).
for x in [wing.junctionX - 4, wing.junctionX + 2, edge - NotchWing.bottomRadius - 2] {
    var covered: CGFloat = 0
    for row in 0..<wingPixels.pixelsHigh { covered += wingPixels.colorAt(x: Int(x * 2), y: row)!.alphaComponent / 2 }
    assert(abs(covered - (wingTop - lowerEdge)) < 0.05, "Rendered lower edge at the housing's lower edge (x \(x))")
}
let wingCensus = census(wingPixels)
assert(wingCensus.white > 100 && wingCensus.colored == 0, "Wing renders white on black, monochrome")
print("PASS: concave upper-right flare, straight lower edge through the housing, flush with its real lower edge, convex free corner")

// MARK: Details layout

let height = IslandContentView.height
let notchLayout = IslandLayout.notch(wing, height: height)
assert(notchLayout.attachY == wing.notch.minY.rounded(.up) && notchLayout.attachY - wing.notch.minY < 1,
       "Top edge on the first whole point above the housing's lower edge: hidden behind housing and wing")
assert(abs(notchLayout.frame.maxY - wing.notch.maxY) <= 1,
       "Open window reaches behind the housing to fill its rounded lower-left cutout")
assert(notchLayout.final.lowerBound == wing.notch.minX && notchLayout.final.upperBound == wing.wingMaxX)
assert(notchLayout.final.upperBound == wing.wingMaxX && notchLayout.rightFillet == 0, "Right edge continues the fixed wing")
assert(notchLayout.final.lowerBound == wing.notch.minX && notchLayout.leftFillet == 0,
       "Expanded left edge exactly matches the notch, with no inset or protruding fillet")
assert(notchLayout.width == wing.notch.width + NotchWing.wingWidth && notchLayout.width >= IslandLayout.minimumWidth)
assert(notchLayout.frame.minX + notchLayout.finalBodyRect.maxX == wing.wingMaxX,
       "Expanded right edge equals the unchanged compact wing")
let startShape = notchLayout.shape(at: 0)
assert(startShape.height == 0 && startShape.minX == wing.notch.maxX && startShape.maxX == wing.wingMaxX,
       "Motion starts as the compact wing itself")
for step in 0...103 {
    let p = CGFloat(step) / 100
    assert(abs(notchLayout.shape(at: p).maxX - wing.wingMaxX) < 1e-9,
           "Wing and body share one right edge throughout the motion (p \(p))")
}
let openShape = notchLayout.shape(at: 1)
assert(openShape.minX == notchLayout.final.lowerBound && openShape.maxX == notchLayout.final.upperBound &&
       openShape.height == height && openShape.radius == IslandLayout.cornerRadius && openShape.leftFillet == 0)
assert(NotchWing.make(screenFrame: NSRect(x: 0, y: 0, width: 1024, height: 665),
                      leftArea: NSRect(x: 0, y: 633, width: 450, height: 32),
                      rightArea: NSRect(x: 574, y: 633, width: 450, height: 32), topInset: 32) == nil,
       "Use normal menu bar if exact notch+wing width cannot hold readable content")
let publicLayout = IslandLayout.notch(publicWing, height: height)
assert(publicLayout.attachY == publicWing.notch.minY && publicLayout.width == notchLayout.width, "Same island width without an outline")

for layout in [notchLayout, publicLayout] {
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
assert(full.contains(NSPoint(x: body.minX + 0.3, y: body.maxY - 0.3)) &&
       !full.contains(NSPoint(x: body.minX - 0.3, y: body.maxY - 0.3)), "Top left stays inside the notch's exact left boundary")

let external = NSRect(x: 0, y: 0, width: 2560, height: 1440)
let anchor = NSRect(x: 2000, y: 1413, width: 92, height: 24)
let barLayout = IslandLayout.menuBar(anchor: anchor, screen: external, visibleTop: 1410, height: height)
assert(barLayout.attachY == 1404 && barLayout.frame.maxY <= anchor.minY, "Attached at the bar edge, never over the status item")
assert(barLayout.isFloating && barLayout.leftFillet == 0 && barLayout.rightFillet == 0 && barLayout.width == IslandLayout.menuBarWidth)
assert(abs((barLayout.final.lowerBound + barLayout.final.upperBound) / 2 - anchor.midX) <= 0.5, "Centred under the item")
assert(IslandLayout.menuBar(anchor: anchor, screen: external, visibleTop: 1440, height: height).attachY == anchor.minY - 6,
       "Auto-hidden bar: attach to the button edge")
let edgeLayout = IslandLayout.menuBar(anchor: NSRect(x: 2500, y: 1413, width: 56, height: 24), screen: external,
                                      visibleTop: 1410, height: height)
assert(edgeLayout.frame.maxX <= external.maxX - IslandLayout.screenMargin,
       "Floating card stays inside the display at the screen edge")
let floatingBody = barLayout.finalBodyRect
let floatingPath = barLayout.path(at: 1)
for point in [NSPoint(x: floatingBody.minX + 0.5, y: floatingBody.maxY - 0.5),
              NSPoint(x: floatingBody.maxX - 0.5, y: floatingBody.maxY - 0.5)] {
    assert(!floatingPath.contains(point), "Normal menu bar uses convex rounded top corners, not notch shoulders")
}
assert(!notchLayout.isFloating && notchLayout.housingCapHeight > 0, "Notch mode keeps its integrated shape")

let second = external.offsetBy(dx: -2560, dy: 0)
let secondLayout = IslandLayout.menuBar(anchor: anchor.offsetBy(dx: -2560, dy: 0), screen: second, visibleTop: 1410, height: height)
assert(secondLayout.frame == barLayout.frame.offsetBy(dx: -2560, dy: 0), "Secondary-screen origin honoured")
print("PASS: island hangs from the housing, shares the fixed wing's right edge, fillets/corners, bounds, fallback clamp")

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
assert(controls.cpu.accessibilityValue() as? String == "Not available" && controls.gpu.accessibilityValue() as? String == "0 %")
assert((controls.network.accessibilityValue() as? String)?.contains("not available") == true)
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
let compactFrame = wingPanel.frame
for step in 0...103 {
    wingPanel.follow(attach: Choreography.attach(CGFloat(step) / 100))
    assert(wingPanel.frame == compactFrame && wingPanel.wingView.frame.size == compactFrame.size,
           "Opening the details never widens or resizes the menu bar widget")
}
wingPanel.follow(attach: 0)

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
let now = Date()
assert(!SingleInstance.shouldYield(ownLaunch: now, otherLaunches: []), "Alone: start")
assert(SingleInstance.shouldYield(ownLaunch: now, otherLaunches: [now.addingTimeInterval(-60)]), "Older instance wins")
assert(!SingleInstance.shouldYield(ownLaunch: now, otherLaunches: [now.addingTimeInterval(1)]),
       "A simultaneous later launch yields to this one, never both")
assert(SingleInstance.shouldYield(ownLaunch: nil, otherLaunches: [nil]), "Unknown dates: avoid a duplicate")
let buildScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
assert(buildScript.contains("<key>CFBundleIdentifier</key><string>\(SingleInstance.bundleIdentifier)</string>"),
       "Single-instance check uses the bundle identifier the build writes")
print("PASS: routing (Escape, ⌘Q, inside, outside, source), wing hit paths, panels non-activating, single instance")

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
if let destination = ProcessInfo.processInfo.environment["TINYSTATS_RENDER_PATH"] {
    try! islandPixels.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
}
assert(isBlack(color(islandPixels, body.midX, islandPixels.size.height - body.minY - 2)), "Black body")
assert(color(islandPixels, body.minX + 1, islandPixels.size.height - body.minY - 1).alphaComponent < 0.01, "Transparent outside the convex corner")
let islandCensus = census(islandPixels)
assert(islandCensus.white > 300 && islandCensus.colored == 0, "Content renders white on black, monochrome")
island.setProgress(0.3)
assert(islandContent.alphaValue == 0, "Content waits until the body has room")
print("PASS: island render monochrome, convex corners, content hidden while closed and early in the motion")

let capTestPoint = NSPoint(x: body.minX + 1, y: notchLayout.attachY - notchLayout.frame.minY + 5)
assert(notchLayout.path(at: 1).contains(capTestPoint), "Housing lower-left rounded gap is filled above the attachment line")
assert(!notchLayout.path(at: 0).contains(capTestPoint), "No housing cap remains when collapsed")
assert(!notchLayout.path(at: 1).contains(NSPoint(x: body.minX - 1, y: capTestPoint.y)), "Cap never protrudes left of the physical notch")
assert(!barLayout.path(at: 1).contains(NSPoint(x: barLayout.finalBodyRect.midX, y: barLayout.frame.height + 1)), "Normal menu bar gets no housing cap")
print("PASS: expanded housing corner gap filled, collapsed and menu-bar silhouettes unchanged")

let floatingContent = IslandContentView(width: barLayout.width)
floatingContent.update(cpu: 0.09, gpu: 0, ram: 0.55, net: NetworkRates(downloadBytesPerSecond: 1_100, uploadBytesPerSecond: 3_100))
let floatingView = IslandView(content: floatingContent)
floatingView.configure(barLayout)
floatingView.setProgress(1)
let floatingPixels = pixels(of: floatingView)
assert(color(floatingPixels, floatingBody.minX + 1, floatingPixels.size.height - floatingBody.maxY + 1).alphaComponent < 0.01,
       "Content clipping preserves rounded top corners in the actual menu-bar render")
if let target = ProcessInfo.processInfo.environment["TINYSTATS_FLOATING_RENDER_PATH"] {
    try! floatingPixels.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: target))
}
print("PASS: normal menu bar floats 6pt below source with rounded corners; notch geometry retained")
