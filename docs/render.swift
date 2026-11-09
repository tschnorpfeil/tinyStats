// AppKit renderings with fixed sample values; no screen capture or live measurements.
let renderApp = NSApplication.shared
renderApp.appearance = NSAppearance(named: .darkAqua)
let rates = NetworkRates(downloadBytesPerSecond: 1_200_000, uploadBytesPerSecond: 84_000)
let indicator = MenuBarIndicators.image(cpu: 0.23, gpu: 0.07, ram: 0.62, net: rates)
let canvasSize = NSSize(width: 480, height: 230)

final class PreviewCanvas: NSView {
    var housing: NSRect?
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.35, alpha: 1),
                   ending: NSColor(srgbRed: 0.34, green: 0.40, blue: 0.53, alpha: 1))!
            .draw(in: bounds, angle: -65)
        NSColor.white.withAlphaComponent(0.04).setFill()
        NSRect(x: 0, y: bounds.maxY - 32, width: bounds.width, height: 32).fill()
        if let housing {
            NSColor.black.setFill()
            let path = NSBezierPath(roundedRect: housing, xRadius: 14.6, yRadius: 14.6)
            path.appendRect(NSRect(x: housing.minX, y: housing.midY, width: housing.width, height: housing.height / 2))
            path.fill()
        }
    }
}
func writePreview(notch: Bool, collapsed: Bool = false, to path: String) throws {
    let canvasSize = collapsed ? NSSize(width: 480, height: 88) : canvasSize
    let barBottom = canvasSize.height - 32
    let canvas = PreviewCanvas(frame: NSRect(origin: .zero, size: canvasSize))
    canvas.appearance = NSAppearance(named: .darkAqua)
    let wing = NotchWing(notch: NSRect(x: 114, y: barBottom, width: 179, height: 32))
    let anchor = NSRect(x: 207, y: barBottom, width: 66, height: 32)
    let layout = notch ? IslandLayout.notch(wing, height: IslandContentView.height)
        : IslandLayout.menuBar(anchor: anchor, screen: canvas.bounds, visibleTop: barBottom, height: IslandContentView.height)
    let content = IslandContentView(width: layout.width)
    content.setNotchOption(available: notch, enabled: notch)
    content.update(cpu: 0.23, gpu: 0.07, ram: 0.62, net: rates)
    let island = IslandView(content: content)
    island.configure(layout)
    island.setProgress(collapsed ? 0 : 1)
    island.setFrameOrigin(layout.frame.origin)
    canvas.addSubview(island)
    if notch {
        canvas.housing = wing.notch
        let view = WingView(frame: wing.frame)
        view.wing = wing
        view.attach = collapsed ? 0 : 1
        view.indicator = indicator
        canvas.addSubview(view)
    } else {
        let view = NSImageView(frame: NSRect(x: anchor.midX - 29, y: barBottom + 5, width: 58, height: 22))
        view.image = indicator
        view.contentTintColor = .white
        canvas.addSubview(view)
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasSize.width * 2), pixelsHigh: Int(canvasSize.height * 2),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvasSize
    canvas.cacheDisplay(in: canvas.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
try writePreview(notch: true, to: "docs/images/notch.png")
try writePreview(notch: false, to: "docs/images/menu-bar.png")
try writePreview(notch: true, collapsed: true, to: "docs/images/notch-collapsed.png")
