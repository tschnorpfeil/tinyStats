import AppKit

// MARK: Live samples (measurement semantics unchanged)

let metrics = Metrics()
assert(metrics.cpu() == nil, "CPU first sample must be unavailable")
assert(metrics.network() == nil, "Network first sample must establish baseline")
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
assert(network!.downloadBytesPerSecond >= 0 && network!.uploadBytesPerSecond >= 0)
assert(metrics.ram().map { (0...1).contains($0) } == true)
metrics.restartBaselines()
assert(metrics.cpu() == nil && metrics.network() == nil, "After a pause in sampling every rate starts a new baseline")

// MARK: Counters, GPU and memory as pure functions

var counted = CounterRates<String>()
assert(counted.update(["en0": (100, 10)], at: 1) == nil, "First reading is a baseline")
assert(counted.update(["en0": (300, 70)], at: 3)! == (100, 30), "Rate is the delta over the elapsed time")
assert(counted.update(["en0": (400, 80), "en1": (5, 5)], at: 4) == nil, "A new interface starts a new baseline")
assert(counted.update(["en0": (500, 90), "en1": (6, 6)], at: 5)! == (101, 11), "Rates sum over all keys")
assert(counted.update(["en0": (10, 95), "en1": (7, 7)], at: 6) == nil, "A falling counter is a reset, never a spike")
assert(counted.update(["en0": (20, 96), "en2": (7, 7)], at: 7) == nil, "Same count but other keys: new baseline")
assert(counted.update(["en0": (30, 97), "en2": (8, 8)], at: 7) == nil, "No time passed: no rate")
assert(counted.update([:], at: 8) == nil && counted.update(["en0": (40, 98), "en2": (9, 9)], at: 9) == nil,
       "Nothing counted drops the baseline")
assert(counted.update(["en0": (UInt64(1) << 40, 98), "en2": (9, 9)], at: 10)! == (Double((UInt64(1) << 40) - 40), 0),
       "Counters are 64-bit: beyond 4 GiB nothing wraps")
assert(Metrics.busiest([12, 80, 30]) == 0.8, "Several GPUs read as the busiest one, not their sum")
assert(Metrics.busiest([]) == nil && Metrics.busiest([.nan, 150, -1]) == nil && Metrics.busiest([.nan, 40]) == 0.4)
var vm = vm_statistics64()
vm.internal_page_count = 600; vm.purgeable_count = 100; vm.wire_count = 200; vm.compressor_page_count = 100
vm.active_count = 900; vm.external_page_count = 300
assert(Metrics.memoryUsed(vm, pageSize: 4096, total: 1000 * 4096) == 0.8,
       "Memory Used: app (internal minus purgeable) + wired + compressed; file cache does not count")
vm.purgeable_count = 700
assert(Metrics.memoryUsed(vm, pageSize: 4096, total: 1000 * 4096) == 0.3 && Metrics.memoryUsed(vm, pageSize: 4096, total: 0) == nil)

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
// Unit and precision follow the rounded value, so no boundary reads "1.000,0 KB/s" or "100,0 W".
assert(Format.rate(999.6).hasSuffix(" KB/s") && Format.rate(999_950).hasSuffix(" MB/s") && Format.rate(999_949).hasSuffix(" KB/s"))
assert(Format.watts(99.96) == "100 W" && Format.watts(100) == "100 W" && Format.bytes(99_960_000_000) == "100 GB")
let de = Locale(identifier: "de_DE"), us = Locale(identifier: "en_US")
assert(Format.scaled(999_950, units: ["B/s", "KB/s", "MB/s"], wholeBase: true, locale: de) == "1,0 MB/s")
assert(Format.scaled(99.94, units: ["W"], wholeFrom: 100, locale: us) == "99.9 W")
assert(Format.scaled(1234, units: ["W"], wholeFrom: 100, locale: de) == "1.234 W", "Large values keep grouping")
assert(MenuBarIndicators.compactNumber(9.96, locale: de) == "10" && MenuBarIndicators.compactNumber(9.94, locale: de) == "9,9" &&
       MenuBarIndicators.compactNumber(2, locale: de) == "2" && MenuBarIndicators.compactNumber(1500, locale: de) == "1500")
assert(MenuBarIndicators.compactRate(999_950, locale: de) == "1M" && MenuBarIndicators.compactRate(9_960, locale: us) == "10K" &&
       MenuBarIndicators.compactRate(9_940, locale: de) == "9,9K" && MenuBarIndicators.compactRate(999.6, locale: us) == "1K")
assert(Format.split("23 %") == ("23", "%") && Format.split("8,2 KB/s") == ("8,2", "KB/s") && Format.split("—") == ("—", ""))
let summary = Format.summary(Sample(cpu: nil, gpu: 0, ram: 1, net: nil), hasBattery: true)
assert(summary.contains("CPU Not available") && summary.contains("GPU 0 %") && summary.contains("Download Not available"))
let ordered = Format.summary(Sample(cpu: 0, gpu: 0, ram: 0, net: NetworkRates(downloadBytesPerSecond: 2_000, uploadBytesPerSecond: 3_000_000)), hasBattery: true)
assert(ordered.contains("Upload 3,0 MB/s · Download 2,0 KB/s") || ordered.contains("Upload 3.0 MB/s · Download 2.0 KB/s"),
       "Upload is read first and keeps its own rate")
print("PASS: live CPU/RAM/network samples, baseline regression, formatting incl. missing vs zero")

let app = NSApplication.shared

func indicatorImage(cpu: Double?, gpu: Double?, ram: Double?, net: NetworkRates?) -> NSImage {
    MenuBarIndicators.image(bars: [cpu, gpu, ram], readout: Metric.network.readout(Sample(net: net)))
}

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
    let image = indicatorImage(cpu: value, gpu: value, ram: value, net: nil)
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
let rows = MenuBarIndicators.rateRows(up: 1_500_000, down: 0)
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
let fullBars = alphaMap(indicatorImage(cpu: 1, gpu: 1, ram: 1, net: nil))
var runs: [Int] = [], inRun = false
for px in 0..<Int(MenuBarIndicators.barsWidth * 2) {
    let column = ink(fullBars, NSRect(x: CGFloat(px) / 2, y: 4, width: 0.5, height: 14)).mean
    if column > 0.85 { if !inRun { runs.append(0) }; runs[runs.count - 1] += 1; inRun = true }
    else { assert(column < 0.01, "Bars have clean gaps"); inRun = false }
}
assert(runs == [8, 8, 8], "Exactly three narrow bars, each \(MenuBarIndicators.barWidth) pt")
assert(ink(fullBars, NSRect(x: MenuBarIndicators.barsWidth, y: 0, width: MenuBarIndicators.groupGap, height: 22)).max == 0,
       "Nothing between the bars and the rates")
let mixed = alphaMap(indicatorImage(cpu: 1, gpu: 0, ram: nil, net: nil))
let cpuBar = MenuBarIndicators.track(0), gpuBar = MenuBarIndicators.track(1), ramBar = MenuBarIndicators.track(2)
assert(ink(mixed, cpuBar.insetBy(dx: 1, dy: 2)).mean > 0.95, "CPU (left) full at 100 %")
let gpuInk = ink(mixed, gpuBar.insetBy(dx: 1, dy: 2))
assert(gpuInk.max > 0.15 && gpuInk.max < 0.35, "GPU (middle) at 0 %: the empty track, nothing filled")
assert(ink(mixed, NSRect(x: ramBar.minX, y: ramBar.minY, width: ramBar.width, height: 5)).max == 0 &&
       ink(mixed, NSRect(x: ramBar.minX, y: ramBar.maxY - 5, width: ramBar.width, height: 5)).max == 0 &&
       ink(mixed, NSRect(x: ramBar.minX, y: ramBar.midY - 1, width: ramBar.width, height: 2)).max > 0.5,
       "RAM (right) missing: a dash instead of the track, distinct from 0 %")
let half = alphaMap(indicatorImage(cpu: 0.5, gpu: nil, ram: nil, net: nil))
assert(ink(half, NSRect(x: cpuBar.minX + 1, y: cpuBar.minY + 1, width: 2, height: 5)).mean > 0.95 &&
       ink(half, NSRect(x: cpuBar.minX + 1, y: cpuBar.maxY - 6, width: 2, height: 5)).max < 0.35, "Fill height follows the value")
let rates = alphaMap(indicatorImage(cpu: nil, gpu: nil, ram: nil,
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
// A built-in display below an external primary sits at a negative origin.
let builtInScreen = NSRect(x: 234, y: -982, width: 1512, height: 982)
let builtInWing = NotchWing.make(screenFrame: builtInScreen, leftArea: NSRect(x: 234, y: -32, width: 663.5, height: 32),
                                 rightArea: NSRect(x: 1082.5, y: -32, width: 663.5, height: 32), topInset: 32)!
assert(builtInWing.notch == NSRect(x: 897.5, y: -32, width: 185, height: 32) && builtInWing.frame.maxY == 0,
       "A notch on a secondary display keeps its wing at that display's top edge")
assert(builtInScreen.contains(IslandLayout.notch(builtInWing, height: IslandContentView.height).frame),
       "The attached details stay on the notched secondary display")
let externalPrimary = NSRect(x: 0, y: 0, width: 1920, height: 1200)
assert(builtInWing.needsStatusItem(screens: [externalPrimary, builtInScreen], separateSpaces: true),
       "The external menu bar keeps the status item beside a wing on the built-in display")
assert(builtInWing.needsStatusItem(screens: [externalPrimary, builtInScreen], separateSpaces: false),
       "A primary display without the wing keeps the status item")
assert(!builtInWing.needsStatusItem(screens: [builtInScreen], separateSpaces: true),
       "The built-in display alone needs only the wing")
assert(!builtInWing.needsStatusItem(screens: [builtInScreen, externalPrimary], separateSpaces: false),
       "Without separate Spaces a secondary display has no menu bar to fill")
let notchedScreens = NSScreen.screens.filter { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }
if notchedScreens.isEmpty {
    assert(NotchWing.firstAvailable(on: NSScreen.screens) == nil, "No notch, no wing")
} else if let liveWing = NotchWing.firstAvailable(on: NSScreen.screens) {
    assert(notchedScreens.contains { $0.frame.contains(liveWing.frame) }, "The wing belongs to a display with a notch")
    print("INFO: wing on a notched display (\(NSScreen.screens.count) connected), frame \(liveWing.frame)")
}
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
wingView.indicator = indicatorImage(cpu: 1, gpu: 0.5, ram: nil,
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
assert(Choreography.widthProgress(0.8) == 1 && Choreography.contentAlpha(0.55) == 0 && Choreography.contentAlpha(0.95) == 1)
assert(Choreography.attach(0) == 0 && Choreography.attach(0.3) == 1 && Choreography.contentDrop(1) == 0)
assert(Choreography.backgroundAlpha(0) == 0 && Choreography.backgroundAlpha(1.02) == 1, "Background runs from transparent to black")
var lastBackground: CGFloat = -1
for step in 0...103 {
    let p = CGFloat(step) / 100
    let alpha = Choreography.backgroundAlpha(p)
    assert(alpha >= lastBackground, "Background fade never flickers")
    assert(Choreography.contentAlpha(p) == 0 || alpha == 1, "Content appears only over a fully black background")
    lastBackground = alpha
}

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
func settleFrame(_ values: [Double], at target: Double) -> Int {
    (values.lastIndex(where: { $0 != target }) ?? -1) + 1
}
let opening = simulate([(1, Spring.opening, 1.5)])
assert(opening.allSatisfy { (0...1).contains($0) }, "Opening never overshoots")
for (a, b) in zip(opening, opening.dropFirst()) { assert(b >= a, "Opening never rebounds") }
assert(opening.firstIndex(where: { $0 >= 0.95 })! <= 15, "Opening reaches 95 % within 250 ms")
assert(settleFrame(opening, at: 1) <= 30, "Opening settles exactly within 500 ms")
let closing = Array(simulate([(1, Spring.opening, 1.5), (0, Spring.closing, 1)]).suffix(61))
assert(closing.allSatisfy { (0...1).contains($0) }, "Closing never undershoots")
for (a, b) in zip(closing, closing.dropFirst()) { assert(b <= a, "Closing never rebounds") }
assert(closing.firstIndex(where: { $0 <= 0.05 })! <= 12, "Closing reaches 5 % within 200 ms")
assert(settleFrame(closing, at: 0) <= 24, "Closing settles exactly within 400 ms")
assert(Spring.closing.response < Spring.opening.response, "Closing is quicker than opening")
let reversal = simulate([(1, Spring.opening, 0.12), (0, Spring.closing, 0.1), (1, Spring.opening, 1.5)])
for (a, b) in zip(reversal, reversal.dropFirst()) { assert(abs(b - a) <= 0.12, "Reversal stays continuous") }
assert(reversal.allSatisfy { (0...1).contains($0) }, "Reversal never leaves 0...1")
assert(settleFrame(reversal, at: 1) <= 12 + 6 + 30, "Reversal settles within 500 ms of the last retarget")
let closeReversal = simulate([(1, Spring.opening, 1), (0, Spring.closing, 0.08), (1, Spring.opening, 1)])
assert(closeReversal.allSatisfy { (0...1).contains($0) } && closeReversal.last == 1, "Reopening mid-close never overshoots")
var flicker = Spring()
for i in 0..<120 {
    flicker.retarget(Double(i / 3 % 2 == 0 ? 1 : 0), i / 3 % 2 == 0 ? Spring.opening : Spring.closing)
    flicker.advance(by: 1.0 / 120)
    assert((0...1).contains(flicker.value), "Rapid retargeting never leaves 0...1")
}
var stalled = Spring()
stalled.retarget(1, Spring.opening)
stalled.advance(by: 2)
assert(stalled.value < 0.5, "A stalled frame slows the motion instead of jumping to the end")
print("PASS: spring no-overshoot open/close/reversal, settle times, choreography ranges, stall handling")

// MARK: Content: fixed layout, fits all states, no re-layout on samples

for width in [IslandLayout.minimumWidth, notchLayout.width, IslandLayout.menuBarWidth] {
    let content = IslandContentView(width: width, hasBattery: true)
    content.setNotchOption(available: true, enabled: true)
    let column = content.tiles[0].frame.width
    let widest = IslandStyle.measure(Format.percent(1), number: IslandStyle.value, unit: IslandStyle.valueUnit).size().width
    assert(widest <= column, "100 % fits a column at width \(width)")
    let rate = IslandStyle.measure(Format.rate(999_949_999), number: IslandStyle.rate, unit: IslandStyle.rateUnit).size().width
    assert(25 + rate <= content.network.frame.width / 2 - 4, "Longest rate fits half the tray at width \(width)")
    assert(content.customizeButton.frame.maxX <= content.quitButton.frame.minX && content.customizeButton.frame.minX >= 16 + 60,
           "Footer items do not collide at width \(width)")
    assert(content.list.frame.minX == content.tiles[0].frame.minX && IslandContentView.columnWidth(inner: content.list.frame.width) == column,
           "Category columns line up under the tiles at width \(width)")
    let frames = content.subviews.map(\.frame)
    for sample in [(nil, nil, nil, nil), (0.0, 0.0, 0.0, NetworkRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)),
                   (1.0, 0.99, 1.0, NetworkRates(downloadBytesPerSecond: 999_499_999, uploadBytesPerSecond: 1e12))] as [(Double?, Double?, Double?, NetworkRates?)] {
        content.update(Sample(cpu: sample.0, gpu: sample.1, ram: sample.2, net: sample.3))
        assert(content.subviews.map(\.frame) == frames, "Samples never re-layout")
    }
    for view in content.subviews { assert(content.bounds.contains(view.frame)) }
}
let controls = IslandContentView(width: notchLayout.width, hasBattery: true)
func notchOption() -> NSMenuItem? { controls.customizationMenu().items.first { $0.title == IslandContentView.notchOptionTitle } }
controls.setNotchOption(available: false, enabled: true)
assert(notchOption() == nil, "Without a housing the menu does not offer the notch")
controls.setNotchOption(available: true, enabled: false)
assert(notchOption()?.state == .off && notchOption()?.isEnabled == true)
var toggled: Bool?
controls.onNotchToggle = { toggled = $0 }
let notchMenu = controls.customizationMenu()
notchMenu.performActionForItem(at: notchMenu.indexOfItem(withTitle: IslandContentView.notchOptionTitle))
assert(toggled == true && notchOption()?.state == .on, "The menu item turns it on and shows its new state")
let offMenu = controls.customizationMenu()
offMenu.performActionForItem(at: offMenu.indexOfItem(withTitle: IslandContentView.notchOptionTitle))
assert(toggled == false && notchOption()?.state == .off, "The same item turns it back off")
assert(notchMenu.items.map(\.title).firstIndex(of: IslandContentView.notchOptionTitle) == 5 && notchMenu.items[4].title.hasPrefix("Menu Bar"),
       "The option sits directly below the menu bar choice")
var quit = 0
controls.onQuit = { quit += 1 }
controls.quitButton.performClick(nil)
assert(quit == 1 && controls.quitButton.accessibilityRole() == .button)
controls.update(Sample(cpu: nil, gpu: 0, ram: 0.5, net: nil))
assert(controls.tiles[0].accessibilityValue() as? String == "Not available" && controls.tiles[1].accessibilityValue() as? String == "0 %")
assert((controls.network.accessibilityValue() as? String)?.contains("not available") == true)
let entries = NetworkView.entries(NetworkRates(downloadBytesPerSecond: 1, uploadBytesPerSecond: 2))
assert(entries.map(\.name) == ["Upload", "Download"] && entries.map(\.symbol) == ["arrow.up", "arrow.down"] &&
       entries.map(\.value) == [2, 1], "Tray reads upload first (left), each with its own rate")
controls.update(Sample(cpu: 0, gpu: 0, ram: 0, net: NetworkRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 1_000)))
assert((controls.network.accessibilityValue() as? String)?.hasPrefix("Upload 1") == true)
print("PASS: content fits min/notch/menu-bar widths, no re-layout on samples, notch option, quit, accessibility values")

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

let presenter = IslandPresenter(content: IslandContentView(width: notchLayout.width, hasBattery: true))
let panel = presenter.panel
assert(panel.contentView === presenter.view && !presenter.isPresented && presenter.spring.isSettled)
assert(panel.styleMask.contains(.nonactivatingPanel) && panel.canBecomeKey && !panel.canBecomeMain)
assert(panel.level == .statusBar && panel.animationBehavior == .none && !panel.collectionBehavior.contains(.fullScreenAuxiliary))
assert(panel.appearance?.name == .darkAqua && !panel.isOpaque && panel.backgroundColor == .clear)
var cancelled = 0
panel.onCancel = { cancelled += 1 }
panel.cancelOperation(nil)
assert(cancelled == 1, "Escape through the responder chain also closes")
func key(_ code: UInt16, _ characters: String) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                     characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
}
assert(presenter.localHandler(key(53, "\u{1b}")) == nil, "The installed monitor swallows Escape instead of passing it on")
let letter = key(0, "a")
assert(presenter.localHandler(letter) === letter, "Other keys pass through")

// Reopened mid-close from another source or display: the new geometry, not the old one.
let farScreen = NSRect(x: -40_000, y: -40_000, width: 2560, height: 1440)
func farLayout(_ dx: CGFloat) -> IslandLayout {
    IslandLayout.menuBar(anchor: NSRect(x: farScreen.minX + 2000 + dx, y: farScreen.maxY - 27, width: 92, height: 24),
                         screen: farScreen.offsetBy(dx: dx, dy: 0), visibleTop: farScreen.maxY - 30, height: height)
}
let reopening = IslandPresenter(content: IslandContentView(width: IslandLayout.menuBarWidth, hasBattery: true))
reopening.reduceMotion = { true }
reopening.open(layout: farLayout(0), source: .zero)
reopening.close()
assert(!reopening.isPresented && reopening.panel.isVisible, "Still fading out")
reopening.open(layout: farLayout(2560), source: .zero)
assert(reopening.view.layout == farLayout(2560) && reopening.panel.frame == farLayout(2560).frame,
       "Reopening with a different layout configures it anew")
reopening.close(animated: false)
assert(!reopening.panel.isVisible)
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

let islandContent = IslandContentView(width: notchLayout.width, hasBattery: true)
islandContent.setNotchOption(available: true, enabled: true)
islandContent.update(Sample(cpu: 0.23, gpu: 0.07, ram: 0.79, net: NetworkRates(downloadBytesPerSecond: 8_200, uploadBytesPerSecond: 4_100)))
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
let fadingBody = notchLayout.bodyRect(at: 0.3)
let fadingPixels = pixels(of: island)
let fadingAlpha = color(fadingPixels, fadingBody.midX, fadingPixels.size.height - fadingBody.midY).alphaComponent
assert(abs(fadingAlpha - Choreography.backgroundAlpha(0.3)) < 0.03 && fadingAlpha > 0.1 && fadingAlpha < 0.9,
       "Silhouette renders translucent while it fades, got \(fadingAlpha)")
print("PASS: island render monochrome, convex corners, content hidden while closed and early in the motion")

let capTestPoint = NSPoint(x: body.minX + 1, y: notchLayout.attachY - notchLayout.frame.minY + 5)
assert(notchLayout.path(at: 1).contains(capTestPoint), "Housing lower-left rounded gap is filled above the attachment line")
assert(!notchLayout.path(at: 0).contains(capTestPoint), "No housing cap remains when collapsed")
assert(!notchLayout.path(at: 1).contains(NSPoint(x: body.minX - 1, y: capTestPoint.y)), "Cap never protrudes left of the physical notch")
assert(!barLayout.path(at: 1).contains(NSPoint(x: barLayout.finalBodyRect.midX, y: barLayout.frame.height + 1)), "Normal menu bar gets no housing cap")
print("PASS: expanded housing corner gap filled, collapsed and menu-bar silhouettes unchanged")

let floatingContent = IslandContentView(width: barLayout.width, hasBattery: true)
floatingContent.update(Sample(cpu: 0.09, gpu: 0, ram: 0.55, net: NetworkRates(downloadBytesPerSecond: 1_100, uploadBytesPerSecond: 3_100)))
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

// MARK: New metrics: readings, catalogue, customization

let probe = Metrics()
_ = probe.diskActivity()
Thread.sleep(forTimeInterval: 0.2)
let liveDisk = probe.diskActivity()
assert(liveDisk != nil && liveDisk!.readBytesPerSecond >= 0 && liveDisk!.writeBytesPerSecond >= 0, "Second disk sample yields rates")
assert(probe.diskSpace().flatMap(\.usedFraction).map { (0...1).contains($0) } == true, "Startup disk is measurable")
assert(probe.swapUsed().map { $0 >= 0 } == true)
let liveSample = probe.sample()
assert((liveSample.battery != nil) == Metrics.hasBattery, "Battery appears exactly when this Mac has one")
if let battery = liveSample.battery {
    assert(battery.fraction.map { (0...1).contains($0) } == true)
    print("INFO: battery \(battery)")
}

// A real reading from this Mac: 35 W system load, battery supplying 3.8 W, stored as a wrapped unsigned.
let wrappedPower = Int64(truncatingIfNeeded: UInt64(18446744073709547805))
assert(wrappedPower == -3811)
let onACPower = BatteryStatus.power(state: .onAC, systemLoadMilliwatts: 34979, batteryMilliwatts: wrappedPower, millivolts: 12000, milliamps: -300)
assert(onACPower.usage == 34.979 && onACPower.charge == 0, "Usage is the whole Mac; 0 W into the battery unless charging")
let chargingPower = BatteryStatus.power(state: .charging, systemLoadMilliwatts: 20000, batteryMilliwatts: 25000, millivolts: 12000, milliamps: 2000)
assert(chargingPower.usage == 20 && chargingPower.charge == 25, "Telemetry wins over voltage times current")
let fallbackPower = BatteryStatus.power(state: .discharging, systemLoadMilliwatts: nil, batteryMilliwatts: nil, millivolts: 12000, milliamps: -1000)
assert(fallbackPower.usage == 12 && fallbackPower.charge == 0, "Discharge current is signed; usage is its magnitude")
assert(BatteryStatus.power(state: .charging, systemLoadMilliwatts: nil, batteryMilliwatts: wrappedPower, millivolts: nil, milliamps: nil).charge == 0,
       "A negative reading is never a charge rate")
assert(BatteryStatus.power(state: .charging, systemLoadMilliwatts: nil, batteryMilliwatts: nil, millivolts: nil, milliamps: nil).charge == nil,
       "Charging with no reading is unknown, not 0 W")
assert(DiskSpace(totalBytes: 100, freeBytes: 25).usedFraction == 0.75 && DiskSpace(totalBytes: 0, freeBytes: 0).usedFraction == nil)

assert(Format.bytes(412_000_000_000) == "412 GB" && Format.bytes(nil) == "—" && Format.bytes(0) == "0 B" && Format.bytes(24_000_000_000).hasSuffix(" GB") && Format.bytes(2e12).hasSuffix(" TB"))
assert(Format.watts(nil) == "—" && Format.watts(.nan) == "—" && Format.watts(0).hasSuffix(" W"))

let plugged = Sample(battery: BatteryStatus(fraction: 1, state: .onAC, usageWatts: 35, chargeWatts: 0))
assert(Metric.charging.cells(plugged)[0].value == Format.watts(0) && Metric.usage.cells(plugged)[0].value == Format.watts(35), "Both rows always read in watts")
assert(Metric.charging.readout(plugged) == .value("0W", charging: false))
let chargingSample = Sample(battery: BatteryStatus(fraction: 0.84, state: .charging, minutesRemaining: 80, usageWatts: 20, chargeWatts: 23.1))
assert(Metric.charging.cells(chargingSample)[0].value == Format.watts(23.1))
assert(Metric.battery.isCharging(chargingSample) && Metric.battery.cells(chargingSample)[0].bolt)
assert(Metric.battery.readout(chargingSample) == .value("84%", charging: true))
assert(Metric.battery.spoken(chargingSample) == "Battery 84 %, charging, 1:20 until full")
assert(Metric.charging.cells(Sample())[0].value == "—", "No battery reading is not the same as not charging")

assert(!Metric.available(hasBattery: false).contains(where: \.needsBattery), "Desktops are not offered battery metrics")
assert(Format.summary(Sample(), hasBattery: false).contains("Battery") == false)

var chosen = MetricLayout()
assert(chosen.top == [.cpu, .gpu, .ram] && chosen.menuBar == .network, "Unchanged for anyone who never customizes")
chosen.setTop(.battery, at: 1)
assert(chosen.top == [.cpu, .battery, .ram])
chosen.setTop(.cpu, at: 2)
assert(chosen.top == [.ram, .battery, .cpu], "Picking a shown gauge swaps, so all three stay different")
chosen.setTop(.network, at: 0)
assert(chosen.top == [.ram, .battery, .cpu], "Rates have no scale, so they cannot fill a bar")
chosen.setTop(.disk, at: 9)
assert(chosen.top == [.ram, .battery, .cpu])
assert(MetricLayout(storedTop: ["disk", "disk", "nonsense", "cpu"], storedMenuBar: "swap", hasBattery: true).top == [.disk, .cpu, .gpu])
assert(MetricLayout(storedTop: ["disk", "disk", "nonsense", "cpu"], storedMenuBar: "swap", hasBattery: true).menuBar == .swap)
assert(MetricLayout(storedTop: nil, storedMenuBar: "load", hasBattery: true).menuBar == .network, "A saved metric that no longer exists falls back to network")
let movedToDesktop = MetricLayout(storedTop: ["battery", "disk", "cpu"], storedMenuBar: "usage", hasBattery: false)
assert(movedToDesktop.top == [.disk, .cpu, .gpu] && movedToDesktop.menuBar == .network, "Settings for a battery fall back on a desktop")

let suite = "tinystats.checks.\(ProcessInfo.processInfo.processIdentifier)"
let defaults = UserDefaults(suiteName: suite)!
assert(MetricLayout.stored(in: defaults, hasBattery: true) == MetricLayout(), "First launch shows the original metrics")
var saved = MetricLayout()
saved.setTop(.disk, at: 0)
saved.setMenuBar(.battery)
saved.save(to: defaults)
assert(MetricLayout.stored(in: defaults, hasBattery: true) == saved, "A choice survives a restart")
defaults.removePersistentDomain(forName: suite)

// Related metrics sit together, in the same order everywhere.
let standardGroups = Metric.grouped(MetricLayout().listed(hasBattery: true))
assert(standardGroups.map { $0.category } == [.power, .storage, .system])
assert(standardGroups.map { $0.metrics } == [[.battery, .usage, .charging], [.disk, .diskActivity], [.swap]])
assert(Metric.grouped(MetricLayout(storedTop: nil, storedMenuBar: nil, hasBattery: false).listed(hasBattery: false)).map { $0.category } == [.storage, .system],
       "No empty Power column on a desktop")
assert(Metric.allCases.allSatisfy { ($0.category == nil) == ($0 == .network) }, "Only network, with its own tray, has no category")
let freeCell = Metric.disk.cells(Sample(disk: DiskSpace(totalBytes: 994_000_000_000, freeBytes: 412_000_000_000)))[0]
assert(freeCell.label == "Free" && freeCell.value == "412 GB", "Under the Storage heading the row only needs to say what it counts")
let spokenList = MetricListView(frame: .zero)
spokenList.metrics = MetricLayout().listed(hasBattery: true)
spokenList.sample = chargingSample
assert(spokenList.details.hasPrefix("Power: Battery 84 %") && spokenList.details.contains("; Storage: ") && spokenList.details.contains("; System: Swap"),
       "VoiceOver and the tooltip name the categories too")

// Every arrangement of gauges on the tiles fits: no column outgrows the panel.
for hasBattery in [true, false] {
    let gauges = Metric.gauges.filter { hasBattery || !$0.needsBattery }
    for first in gauges { for second in gauges where second != first { for third in gauges where third != first && third != second {
        let layout = MetricLayout(storedTop: [first, second, third].map(\.rawValue), storedMenuBar: nil, hasBattery: hasBattery)
        assert(layout.top == [first, second, third])
        let listed = layout.listed(hasBattery: hasBattery)
        assert(Set(layout.top + listed) == Set(Metric.available(hasBattery: hasBattery).filter { $0 != .network }), "Each metric appears once, wherever it is")
        assert(layout.top.allSatisfy { !listed.contains($0) }, "Never on a tile and in the list")
        for group in Metric.grouped(listed) {
            assert(group.metrics.flatMap { $0.cells(Sample()) }.count <= MetricListView.rows,
                   "\(group.category) fits its column for \(layout.top), so the open island keeps its frame")
        }
        let view = IslandContentView(width: IslandLayout.minimumWidth, hasBattery: hasBattery)
        view.setMetricLayout(layout)
        assert(view.frame.height == IslandContentView.height)
        for tile in view.tiles {
            let caption = IslandStyle.text(tile.metric.caption, IslandStyle.caption, IslandStyle.secondary, kern: 0.4).size().width
            assert(caption + 3 + MetricView.boltSize.width <= tile.frame.width, "\(tile.metric) caption and bolt fit a tile")
        }
    } } }
}

let widestSample = Sample(cpu: 1, gpu: 1, ram: 1, battery: BatteryStatus(fraction: 1, state: .charging, usageWatts: 99.9, chargeWatts: 99.9),
                          disk: DiskSpace(totalBytes: 2e15, freeBytes: 999_400_000_000),
                          diskIO: DiskRates(readBytesPerSecond: 999_900_000, writeBytesPerSecond: 999_900_000),
                          swapUsedBytes: 999_900_000_000)
let narrowestColumn = IslandContentView.columnWidth(inner: IslandLayout.minimumWidth - 2 * IslandContentView.padding)
for category in MetricCategory.allCases {
    let header = IslandStyle.text(category.rawValue.uppercased(), IslandStyle.caption, IslandStyle.secondary, kern: 0.4).size().width
    assert(header <= narrowestColumn, "\(category) heading fits a column at the narrowest width")
}
for metric in Metric.allCases {
    for cell in metric.cells(widestSample) {
        let label = IslandStyle.text(cell.label, IslandStyle.listLabel, IslandStyle.secondary).size().width
        let value = MetricListView.valueText(cell.value).size().width
        assert(label + (cell.bolt ? 3 + MetricView.boltSize.width : 0) <= narrowestColumn && value <= narrowestColumn,
               "\(cell.label) \(cell.value) fits a column at the narrowest width (\(narrowestColumn), value \(value))")
    }
}

// The menu bar's single value must fit the column the network rates already used.
for locale in [Locale(identifier: "de_DE"), Locale(identifier: "en_US")] {
    for value in [0.0, 9.94, 9.96, 99.9, 999.4] {
        let text = (MenuBarIndicators.compactNumber(value, locale: locale)! + "W") as NSString
        assert(text.size(withAttributes: [.font: MenuBarIndicators.valueFont]).width <= rateColumn, "\(text) fits")
    }
}
for text in ["100%", "≥1T", "999M", "—"] {
    let width = (text as NSString).size(withAttributes: [.font: MenuBarIndicators.valueFont]).width
    assert(width <= rateColumn, "\(text) fits the column")
}
let single = alphaMap(MenuBarIndicators.image(bars: [1, 1, 1], readout: .value("84%", charging: false)))
assert(single.size == indicatorSize, "Choosing a value never changes the indicator's width")
assert(ink(single, NSRect(x: rateX, y: 0, width: indicatorSize.width - rateX, height: 22)).max > 0.5, "The value is drawn")
assert(ink(single, NSRect(x: MenuBarIndicators.barsWidth, y: 0, width: MenuBarIndicators.groupGap, height: 22)).max == 0)
let idle = ink(alphaMap(MenuBarIndicators.image(bars: [0, 0, 0], readout: .value("84%", charging: false))), NSRect(x: rateX, y: 0, width: 8, height: 22)).max
let bolted = ink(alphaMap(MenuBarIndicators.image(bars: [0, 0, 0], readout: .value("84%", charging: true))), NSRect(x: rateX, y: 0, width: 8, height: 22)).max
assert(idle == 0 && bolted > 0.5, "Charging adds a bolt left of a short value")
let fullCharge = alphaMap(MenuBarIndicators.image(bars: [0, 0, 0], readout: .value("100%", charging: true)))
assert(ink(fullCharge, NSRect(x: MenuBarIndicators.barsWidth, y: 0, width: 2, height: 22)).max == 0, "A wide value never pushes a bolt into the bars")

// The real menu, driven the way a click drives it.
let customizing = IslandContentView(width: IslandLayout.menuBarWidth, hasBattery: true)
var reported: MetricLayout?
customizing.onLayoutChange = { reported = $0 }
customizing.update(chargingSample)
func menuItem(_ section: String, _ name: String) -> (NSMenu, Int) {
    let parent = customizing.customizationMenu().items.first { $0.title.hasPrefix(section) }!
    let index = parent.submenu!.items.firstIndex { $0.title == name }!
    return (parent.submenu!, index)
}
let opened = customizing.customizationMenu()
assert(opened.items.map(\.title).prefix(3) == ["Top Left: CPU", "Top Middle: GPU", "Top Right: RAM"] && opened.items[4].title == "Menu Bar: Network")
assert(opened.items.last?.title == "Reset to Defaults" && opened.items.last?.isEnabled == false, "Nothing to reset yet")
assert(opened.items[0].submenu!.items.map(\.title) == ["CPU", "GPU", "RAM", "Battery", "Disk"], "Tiles offer gauges only")
assert(opened.items[0].submenu!.items[0].state == .on && opened.items[0].submenu!.items[1].state == .off)
let barPicker = opened.items[4].submenu!.items
assert(barPicker.map(\.title) == ["Network", "Power", "Battery", "Power Usage", "Charging", "Storage", "Disk", "Disk Activity", "System", "CPU", "GPU", "RAM", "Swap"],
       "The menu bar picker uses the same categories as the list")
assert(barPicker.filter(\.isSectionHeader).map(\.title) == ["Power", "Storage", "System"] && barPicker.filter { !$0.isSectionHeader }.count == Metric.allCases.count,
       "Headings are headings; every metric stays selectable")
let (leftMenu, batteryIndex) = menuItem("Top Left", "Battery")
leftMenu.performActionForItem(at: batteryIndex)
assert(customizing.metricLayout.top[0] == .battery && reported?.top[0] == .battery)
assert(customizing.tiles[0].metric == .battery && customizing.tiles[0].charging && customizing.tiles[0].value == 0.84, "The tile shows the last reading at once")
assert(customizing.tiles[0].accessibilityValue() as? String == "84 %, charging")
assert(customizing.list.metrics.contains(.cpu) && !customizing.list.metrics.contains(.battery), "The displaced gauge moves to the list")
let (barMenu, swapIndex) = menuItem("Menu Bar", "Swap")
barMenu.performActionForItem(at: swapIndex)
assert(customizing.metricLayout.menuBar == .swap && reported?.menuBar == .swap)
assert(customizing.customizationMenu().items[4].title == "Menu Bar: Swap")
let reset = customizing.customizationMenu().items.last!
assert(reset.isEnabled)
_ = (reset.target as! NSObject).perform(reset.action, with: reset)
assert(customizing.metricLayout == MetricLayout() && reported == MetricLayout())
let desktopMenu = IslandContentView(width: IslandLayout.menuBarWidth, hasBattery: false).customizationMenu()
assert(desktopMenu.items[0].submenu!.items.map(\.title) == ["CPU", "GPU", "RAM", "Disk"])
assert(desktopMenu.items[4].submenu!.items.filter(\.isSectionHeader).map(\.title) == ["Storage", "System"], "No empty Power section on a desktop")
assert(customizing.customizeButton.accessibilityRole() == .button && customizing.customizeButton.accessibilityLabel() == "Settings")
print("PASS: battery, power, disk, swap; customization menu, swaps, persistence, every position fits")
