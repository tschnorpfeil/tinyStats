extension Metrics {
    var networkBaselineTimeForCheck: TimeInterval? { prevNetTime }
}

let metrics = Metrics()
assert(metrics.cpu() == nil, "CPU first sample must be unavailable")
assert(metrics.network() == nil, "Network first sample must establish baseline")
let firstBaseline = metrics.networkBaselineTimeForCheck
Thread.sleep(forTimeInterval: 0.05)
assert(metrics.cpu().map { (0...1).contains($0) } == true)
let network = metrics.network()
assert(network != nil, "This Mac must expose en interfaces")
assert(metrics.networkBaselineTimeForCheck! > firstBaseline!, "Successful network sample must advance baseline")
assert(network!.downloadBytesPerSecond >= 0 && network!.uploadBytesPerSecond >= 0)
assert(metrics.ram().map { (0...1).contains($0) } == true)
assert(StatusViewController.percent(nil) == "—")
assert(StatusViewController.percent(0) == "0 %")
assert(StatusViewController.percent(1) == "100 %")
assert(StatusViewController.formatRate(nil) == "—")
assert(StatusViewController.formatRate(.nan) == "—")
assert(StatusViewController.formatRate(-1) == "—")
assert(StatusViewController.formatRate(0) == "0 B/s")
assert(StatusViewController.formatRate(1500).hasSuffix(" KB/s"))
assert(StatusViewController.formatRate(1_500_000).hasSuffix(" MB/s"))
assert(StatusViewController.formatRate(1_500_000_000).hasSuffix(" GB/s"))
let app = NSApplication.shared
let controller = StatusViewController()
controller.updateMetrics(cpu: nil, gpu: nil, ram: nil, net: nil)
assert(controller.preferredContentSize.width == 300)
assert(controller.preferredContentSize.height > 200)
controller.updateMetrics(cpu: 1, gpu: 1, ram: 1, net: NetworkRates(downloadBytesPerSecond: 999_999_999, uploadBytesPerSecond: 0))
controller.view.layoutSubtreeIfNeeded()
print("PASS: CPU/RAM live samples, network baseline regression, formatting, popover construction")
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
for value: Double? in [nil, 0, 0.07, 0.81, 1, .nan] {
    let image = MenuBarIndicators.image(cpu: value, gpu: value, ram: value, net: nil)
    assert(image.isTemplate && image.size == NSSize(width: 88, height: 22))
    assert(image.tiffRepresentation != nil, "Indicator must actually rasterize")
}
for rate in [0.0, 999, 999_499, 999_500, 999_499_999, 999_500_000, 999_499_999_999, 999_500_000_000, 1e12] {
    let text = MenuBarIndicators.compactRate(rate) as NSString
    assert(text.size(withAttributes: [.font: MenuBarIndicators.rateFont]).width <= 27,
           "Network label must fit in its reserved width")
}
print("PASS: menu bar templates rasterize; compact units, promotion, missing values and text widths")

assert(MenuBarIndicators.compactRate(999_500_000_000) == "1T")
for label in ["C", "G", "R"] {
    assert((label as NSString).size(withAttributes: [.font: MenuBarIndicators.labelFont]).width <= 9)
}
print("PASS: metric initials fit 9pt labels; worst-case rates fit tight 27pt field")

for locale in [Locale(identifier: "de_DE"), Locale(identifier: "en_US")] {
    for rate in [999.0, 1500, 999499, 999500, 9_940_000, 999_499_999, 999_499_999_999, 999_500_000_000, 1e12] {
        let text = MenuBarIndicators.compactRate(rate, locale: locale) as NSString
        let width = text.size(withAttributes: [.font: MenuBarIndicators.rateFont]).width
        let arrowWidth = ("↓" as NSString).size(withAttributes: [.font: MenuBarIndicators.rateFont]).width
        assert(width + arrowWidth + 2 <= 36, "Arrow and localized rate need at least 2pt separation")
    }
}
print("PASS: de_DE/en_US network labels fit 36pt block with 2pt arrow gap")

// Notch geometry: real scout values of this Mac, no notch, too little space, non-zero origin.
let scoutScreen = NSRect(x: 0, y: 0, width: 1470, height: 956)
let scoutRight = NSRect(x: 824.5, y: 924, width: 645.5, height: 32)
assert(NotchGeometry.overlayFrame(screenFrame: scoutScreen, rightArea: scoutRight, topInset: 32)
       == NSRect(x: 824.5, y: 924, width: 108, height: 32), "Overlay must sit flush right of the notch")
assert(NotchGeometry.overlayFrame(screenFrame: scoutScreen, rightArea: nil, topInset: 0) == nil)
assert(NotchGeometry.overlayFrame(screenFrame: scoutScreen, rightArea: nil, topInset: 32) == nil)
assert(NotchGeometry.overlayFrame(screenFrame: scoutScreen, rightArea: scoutRight, topInset: 0) == nil)
assert(NotchGeometry.overlayFrame(screenFrame: scoutScreen, rightArea: .zero, topInset: 32) == nil)
assert(NotchGeometry.overlayFrame(screenFrame: scoutScreen, rightArea: NSRect(x: 0, y: 924, width: 1470, height: 32), topInset: 32) == nil,
       "Area starting at the screen's left edge is not beside a notch")
assert(NotchGeometry.overlayFrame(screenFrame: scoutScreen, rightArea: NSRect(x: 1370.5, y: 924, width: 99.5, height: 32), topInset: 32) == nil,
       "Too narrow right area must fall back")
assert(NotchGeometry.overlayFrame(screenFrame: scoutScreen, rightArea: NSRect(x: 1362, y: 924, width: 108, height: 32), topInset: 32)
       == NSRect(x: 1362, y: 924, width: 108, height: 32), "Exact fit is allowed")
assert(NotchGeometry.overlayFrame(screenFrame: scoutScreen, rightArea: scoutRight, topInset: 20) == nil, "Too low notch must fall back")
assert(NotchGeometry.overlayFrame(screenFrame: scoutScreen, rightArea: NSRect(x: 824.5, y: 800, width: 645.5, height: 32), topInset: 32) == nil,
       "Area away from the top edge must fall back")
let tallScreen = NSRect(x: 0, y: 0, width: 1728, height: 1117)
let tall = NotchGeometry.overlayFrame(screenFrame: tallScreen, rightArea: NSRect(x: 952, y: 1079, width: 776, height: 38), topInset: 38)
assert(tall == NSRect(x: 952, y: 1079, width: 108, height: 38), "Height follows the real notch height")
assert(NotchGeometry.contentRect(in: NSRect(x: 0, y: 0, width: 108, height: 38)) == NSRect(x: 10, y: 8, width: 88, height: 22))
assert(NotchGeometry.contentRect(in: NSRect(x: 0, y: 0, width: 108, height: 32)) == NSRect(x: 10, y: 5, width: 88, height: 22))
let shifted = NSRect(x: -1470, y: 300, width: 1470, height: 956)
assert(NotchGeometry.overlayFrame(screenFrame: shifted, rightArea: scoutRight.offsetBy(dx: -1470, dy: 300), topInset: 32)
       == NSRect(x: -645.5, y: 1224, width: 108, height: 32), "Non-zero screen origin must be honoured")
assert(NotchGeometry.overlayFrame(screenFrame: shifted, rightArea: scoutRight, topInset: 32) == nil,
       "Area outside the given screen must not be used")
print("PASS: notch frame for scout values, no notch, too little space, taller notch, non-zero origin")

let shape = NotchGeometry.shapePath(in: NSRect(x: 0, y: 0, width: 108, height: 32))
assert(shape.contains(NSPoint(x: 0.2, y: 0.2)) && shape.contains(NSPoint(x: 0.2, y: 31.8)), "Left corners stay square")
assert(!shape.contains(NSPoint(x: 107.8, y: 0.2)) && !shape.contains(NSPoint(x: 107.8, y: 31.8)), "Right corners are rounded")
assert(shape.contains(NSPoint(x: 107.8, y: 16)) && shape.contains(NSPoint(x: 54, y: 31.8)))

let panel = NotchOverlayPanel()
assert(panel.styleMask.contains(.borderless) && panel.styleMask.contains(.nonactivatingPanel))
assert(!panel.isOpaque && panel.backgroundColor == .clear && !panel.hasShadow && !panel.hidesOnDeactivate)
assert(panel.level == .statusBar && !panel.canBecomeKey)
assert(panel.collectionBehavior.contains(.stationary) && !panel.collectionBehavior.contains(.fullScreenAuxiliary))
let requested = NSRect(x: 824.5, y: 924, width: 108, height: 32)
assert(panel.constrainFrameRect(requested, to: nil) == requested)
var clicks = 0
panel.overlayView.onClick = { clicks += 1 }
assert(panel.overlayView.accessibilityRole() == .button && panel.overlayView.accessibilityPerformPress() && clicks == 1)
print("PASS: notch shape corners; borderless non-activating status-level panel without full-screen auxiliary")

// Native offscreen render of the overlay view (not a live on-screen check).
let overlay = NotchOverlayView(frame: NSRect(x: 0, y: 0, width: 108, height: 32))
overlay.indicator = MenuBarIndicators.image(cpu: 1, gpu: 0.5, ram: nil,
                                            net: NetworkRates(downloadBytesPerSecond: 1_500_000, uploadBytesPerSecond: 0))
let rep = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds)!
overlay.cacheDisplay(in: overlay.bounds, to: rep)
let pxScale = CGFloat(rep.pixelsWide) / overlay.bounds.width
func pixel(_ x: CGFloat, _ yFromTop: CGFloat) -> NSColor {
    rep.colorAt(x: Int(x * pxScale), y: Int(yFromTop * pxScale))!.usingColorSpace(.deviceRGB)!
}
func isBlack(_ c: NSColor) -> Bool { c.alphaComponent > 0.99 && c.redComponent < 0.01 && c.greenComponent < 0.01 && c.blueComponent < 0.01 }
assert(isBlack(pixel(0, 0)) && isBlack(pixel(0, 31.9)), "Left edge must be solid black to the notch")
assert(pixel(107.9, 0).alphaComponent < 0.01 && pixel(107.9, 31.9).alphaComponent < 0.01, "Rounded right corners transparent")
assert(isBlack(pixel(4, 16)) && isBlack(pixel(104, 16)), "Padding stays black")
var white = 0, colored = 0
for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    if c.alphaComponent > 0.99, c.redComponent > 0.95, c.greenComponent > 0.95, c.blueComponent > 0.95 { white += 1 }
    if abs(c.redComponent - c.greenComponent) > 0.02 || abs(c.greenComponent - c.blueComponent) > 0.02 { colored += 1 }
} }
assert(white > 100, "Indicator must render white on black")
assert(colored == 0, "Overlay must stay monochrome")
print("PASS: offscreen overlay render white on black, square left edge, transparent rounded right corners (\(white) white px)")

controller.setNotchOption(available: false, enabled: true)
let compactHeight = controller.preferredContentSize.height
assert(controller.notchToggle.isHidden && !controller.notchToggle.isEnabled)
controller.setNotchOption(available: true, enabled: false)
assert(!controller.notchToggle.isHidden && controller.notchToggle.isEnabled && controller.notchToggle.state == .off)
assert(controller.preferredContentSize.height > compactHeight, "Visible checkbox must grow the popover")
var toggled: Bool?
controller.onNotchToggle = { toggled = $0 }
controller.notchToggle.performClick(nil)
assert(toggled == true && controller.notchToggle.state == .on)
controller.setNotchOption(available: false, enabled: true)
assert(controller.notchToggle.isHidden && controller.preferredContentSize.height == compactHeight)
print("PASS: notch checkbox hidden without notch, toggles and resizes popover")
