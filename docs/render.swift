import AppKit
import ImageIO

// AppKit renderings with fixed sample values; no screen capture or live measurements.
let renderApp = NSApplication.shared
renderApp.appearance = NSAppearance(named: .darkAqua)
let rates = NetworkRates(downloadBytesPerSecond: 1_200_000, uploadBytesPerSecond: 84_000)
let sample = Sample(cpu: 0.23, gpu: 0.07, ram: 0.62, net: rates,
                    battery: BatteryStatus(fraction: 0.84, state: .charging, usageWatts: 14.2, chargeWatts: 23.1),
                    disk: DiskSpace(totalBytes: 994_000_000_000, freeBytes: 412_000_000_000),
                    diskIO: DiskRates(readBytesPerSecond: 3_400_000, writeBytesPerSecond: 610_000),
                    swapUsedBytes: 1_200_000_000)
let canvasSize = NSSize(width: 480, height: 320)
let menuBarHeight: CGFloat = 32
/// Product Hunt gallery, in pixels.
let slideSize = NSSize(width: 1270, height: 760)
let iconsetPath = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") && $0.hasSuffix(".iconset") }

/// White text at a fixed origin; on gallery slides in output pixels.
struct Caption {
    var text: String
    var font: NSFont
    var color: NSColor = .white
    var origin: NSPoint
}

/// Lines stacked downward and centred on `midY`; `x` is the left edge, or the centre when `centered`.
func stack(_ lines: [(text: String, font: NSFont, color: NSColor, gap: CGFloat)], x: CGFloat, midY: CGFloat,
           centered: Bool = false) -> [Caption] {
    let sizes = lines.map { ($0.text as NSString).size(withAttributes: [.font: $0.font]) }
    var y = midY + (zip(lines, sizes).map { $0.0.gap + $0.1.height }.reduce(0, +)) / 2
    return zip(lines, sizes).map { line, size in
        y -= line.gap + size.height
        return Caption(text: line.text, font: line.font, color: line.color,
                       origin: NSPoint(x: centered ? (x - size.width / 2).rounded() : x, y: y.rounded()))
    }
}

final class PreviewCanvas: NSView {
    var housing: NSRect?
    var menuBar = true
    var captions: [Caption] = []
    /// Scenes rendered on their own, shown as rounded crops of a screen.
    var panels: [(image: NSImage, frame: NSRect)] = []
    var images: [(image: NSImage, frame: NSRect)] = []
    /// Output pixels per point; captions and panels are placed in output pixels.
    var pixelScale: CGFloat = 1

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.35, alpha: 1),
                   ending: NSColor(srgbRed: 0.34, green: 0.40, blue: 0.53, alpha: 1))!
            .draw(in: bounds, angle: -65)
        if menuBar {
            NSColor.white.withAlphaComponent(0.04).setFill()
            NSRect(x: 0, y: bounds.maxY - menuBarHeight, width: bounds.width, height: menuBarHeight).fill()
        }
        NSGraphicsContext.saveGraphicsState()
        if pixelScale != 1 {
            let transform = NSAffineTransform()
            transform.scale(by: 1 / pixelScale)
            transform.concat()
        }
        for panel in panels {
            let outline = NSBezierPath(roundedRect: panel.frame, xRadius: 22, yRadius: 22)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 40
            shadow.shadowOffset = NSSize(width: 0, height: -14)
            shadow.set()
            NSColor.black.setFill()
            outline.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            panel.image.draw(in: panel.frame)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(0.12).setStroke()
            outline.lineWidth = 2
            outline.stroke()
        }
        for image in images { image.image.draw(in: image.frame) }
        for caption in captions {
            (caption.text as NSString).draw(at: caption.origin, withAttributes: [.font: caption.font, .foregroundColor: caption.color])
        }
        NSGraphicsContext.restoreGraphicsState()
        if let housing {
            NSColor.black.setFill()
            let path = NSBezierPath(roundedRect: housing, xRadius: 14.6, yRadius: 14.6)
            path.appendRect(NSRect(x: housing.minX, y: housing.midY, width: housing.width, height: housing.height / 2))
            path.fill()
        }
    }
}

/// The real views at one moment of the transition: beside the notch, or under a status item.
struct Scene {
    var size = canvasSize
    var notch = true
    /// Left edge of the housing, or centre of the status item.
    var x: CGFloat = 114
    var progress: CGFloat = 1
    var layout = MetricLayout()

    static let housingWidth: CGFloat = 179
    var barBottom: CGFloat { size.height - menuBarHeight }
    var wing: NotchWing { NotchWing(notch: NSRect(x: x, y: barBottom, width: Self.housingWidth, height: menuBarHeight)) }
    var anchor: NSRect { NSRect(x: x - 33, y: barBottom, width: 66, height: menuBarHeight) }
    var islandLayout: IslandLayout {
        notch ? .notch(wing, height: IslandContentView.height)
            : .menuBar(anchor: anchor, screen: NSRect(origin: .zero, size: size), visibleTop: barBottom,
                       height: IslandContentView.height)
    }
}

func canvas(_ scene: Scene) -> PreviewCanvas {
    let canvas = PreviewCanvas(frame: NSRect(origin: .zero, size: scene.size))
    canvas.appearance = NSAppearance(named: .darkAqua)
    let layout = scene.islandLayout
    let content = IslandContentView(width: layout.width, hasBattery: true)
    content.setNotchOption(available: scene.notch, enabled: scene.notch)
    content.setMetricLayout(scene.layout)
    content.update(sample)
    let island = IslandView(content: content)
    island.configure(layout)
    island.setProgress(scene.progress)
    island.setFrameOrigin(layout.frame.origin)
    canvas.addSubview(island)
    let indicator = MenuBarIndicators.image(bars: scene.layout.top.map { $0.fraction(sample) },
                                            readout: scene.layout.menuBar.readout(sample))
    if scene.notch {
        canvas.housing = scene.wing.notch
        let view = WingView(frame: scene.wing.frame)
        view.wing = scene.wing
        view.attach = Choreography.attach(scene.progress)
        view.indicator = indicator
        canvas.addSubview(view)
    } else {
        let view = NSImageView(frame: NSRect(x: scene.anchor.midX - 29, y: scene.barBottom + 5, width: 58, height: 22))
        view.image = indicator
        view.contentTintColor = .white
        canvas.addSubview(view)
    }
    return canvas
}

func bitmap(pixels: NSSize, points: NSSize, alpha: Bool = true) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                               bitsPerSample: 8, samplesPerPixel: alpha ? 4 : 3, hasAlpha: alpha, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: alpha ? 0 : 32)!
    rep.size = points
    return rep
}

func render(_ view: NSView, scale: CGFloat = 2) -> NSBitmapImageRep {
    let size = view.bounds.size
    let rep = bitmap(pixels: NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded()), points: size)
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

/// Draws into a fresh bitmap with one point per pixel.
func paint(_ pixels: NSSize, alpha: Bool = true, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = bitmap(pixels: pixels, points: pixels, alpha: alpha)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) throws {
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: - README images

func writePreview(notch: Bool, collapsed: Bool = false, social: Bool = false, to path: String) throws {
    var scene = Scene(notch: notch, x: notch ? (social ? 348 : 114) : 240, progress: collapsed ? 0 : 1)
    if social { scene.size = NSSize(width: 640, height: 320) } else if collapsed { scene.size = NSSize(width: 480, height: 88) }
    let view = canvas(scene)
    if social {
        view.captions = [
            Caption(text: "tinyStats", font: .systemFont(ofSize: 43, weight: .semibold), origin: NSPoint(x: 32, y: 194)),
            Caption(text: "Your Mac, at a glance.", font: .systemFont(ofSize: 17, weight: .regular),
                    color: .white.withAlphaComponent(0.8), origin: NSPoint(x: 34, y: 162)),
            Caption(text: "CPU · GPU · RAM · Battery · Disk · Network", font: .systemFont(ofSize: 14, weight: .medium),
                    color: .white.withAlphaComponent(0.7), origin: NSPoint(x: 34, y: 42)),
        ]
    }
    try write(render(view), to: path)
}
try writePreview(notch: true, to: "docs/images/notch.png")
try writePreview(notch: false, to: "docs/images/menu-bar.png")
try writePreview(notch: true, collapsed: true, to: "docs/images/notch-collapsed.png")
try writePreview(notch: true, social: true, to: "docs/images/social-preview.png")

// MARK: - App icon

/// Fill levels of the icon's bars, in whole pixels of the 14 px track.
let iconBars: [Double] = [6.0 / 14, 11.0 / 14, 8.0 / 14]

/// The indicator's three bars, as `MenuBarIndicators` draws them, tinted white into `rect`.
func drawBars(in rect: NSRect) {
    let image = MenuBarIndicators.image(bars: iconBars, readout: .value("", charging: false))
    image.cacheMode = .never
    let track = MenuBarIndicators.track(0)
    let context = NSGraphicsContext.current!.cgContext
    context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
    image.draw(in: rect, from: NSRect(x: 0, y: track.minY, width: MenuBarIndicators.barsWidth, height: track.height),
               operation: .sourceOver, fraction: 1)
    NSColor.white.setFill()
    rect.fill(using: .sourceAtop)
    context.endTransparencyLayer()
}

/// macOS icon grid: a 824 pt rounded square on a 1024 pt canvas; `fill`
/// paints the whole canvas instead (Product Hunt rounds its thumbnails itself).
func icon(pixels: CGFloat, fill: Bool = false) -> NSBitmapImageRep {
    paint(NSSize(width: pixels, height: pixels), alpha: !fill) {
        let transform = NSAffineTransform()
        if fill {
            transform.scale(by: pixels / 824)
            transform.translateX(by: -100, yBy: -100)
        } else {
            transform.scale(by: pixels / 1024)
        }
        transform.concat()
        let shape = NSRect(x: 100, y: 100, width: 824, height: 824)
        let outline = fill ? NSBezierPath(rect: shape.insetBy(dx: -100, dy: -100))
            : NSBezierPath(roundedRect: shape, xRadius: 185.4, yRadius: 185.4)
        NSGraphicsContext.saveGraphicsState()
        if !fill {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            // Shadows ignore the transform; scale them to the rendition by hand.
            shadow.shadowBlurRadius = 20 * pixels / 1024
            shadow.shadowOffset = NSSize(width: 0, height: -10 * pixels / 1024)
            shadow.set()
        }
        NSColor.black.setFill()
        outline.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(white: 0.13, alpha: 1), ending: NSColor(white: 0, alpha: 1))!
            .draw(in: outline, angle: -90)
        // One indicator point is 24 grid points; the 16 and 32 px renditions take 32, so at
        // 32 px the bars land pixel for pixel, as in the menu bar, and stay legible at 16 px.
        let unit: CGFloat = pixels <= 32 ? 32 : 24
        let size = NSSize(width: MenuBarIndicators.barsWidth * unit, height: MenuBarIndicators.track(0).height * unit)
        drawBars(in: NSRect(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2, width: size.width, height: size.height))
    }
}

if let iconsetPath {
    try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            try write(icon(pixels: CGFloat(points * scale)),
                      to: "\(iconsetPath)/icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png")
        }
    }
}
try write(icon(pixels: 256), to: "docs/images/icon.png")
try write(icon(pixels: 240, fill: true), to: "docs/launch/thumbnail.png")

// MARK: - Product Hunt gallery

let quiet = NSColor.white.withAlphaComponent(0.8)
let subline = NSFont.systemFont(ofSize: 26, weight: .regular)

/// Headline lines, then at most one quieter line below them.
func titled(_ title: String, _ detail: String? = nil, size: CGFloat = 52, detailSize: CGFloat = 26)
    -> [(text: String, font: NSFont, color: NSColor, gap: CGFloat)] {
    title.split(separator: "\n").enumerated().map {
        (String($0.element), .systemFont(ofSize: size, weight: .semibold), .white, $0.offset == 0 ? 0 : 4)
    } + (detail.map { [($0, .systemFont(ofSize: detailSize, weight: .regular), quiet, size * 0.36)] } ?? [])
}

/// A slide whose scene fills it, `scale` output pixels per point.
func sceneSlide(_ scene: Scene, scale: CGFloat) -> PreviewCanvas {
    let view = canvas(scene)
    view.pixelScale = scale
    return view
}

/// A backdrop without a menu bar, for what is not shown at the top of a screen.
func plainSlide() -> PreviewCanvas {
    let view = PreviewCanvas(frame: NSRect(x: 0, y: 0, width: slideSize.width / 2, height: slideSize.height / 2))
    view.menuBar = false
    view.pixelScale = 2
    return view
}

/// The open details at the right, text at the left, centred on the island's body.
func detailSlide(notch: Bool, title: String, detail: String? = nil) -> PreviewCanvas {
    var scene = Scene(size: NSSize(width: slideSize.width / 2, height: slideSize.height / 2), notch: notch)
    // Right edge of the wing, or of the card.
    let right = scene.size.width - (notch ? 44 : 36)
    scene.x = notch ? right - NotchWing.wingWidth - Scene.housingWidth : right - IslandLayout.menuBarWidth / 2
    let view = sceneSlide(scene, scale: 2)
    let layout = scene.islandLayout
    view.captions = stack(titled(title, detail), x: 76, midY: (layout.frame.minY + layout.finalBodyRect.midY) * 2)
    return view
}

/// Scenes cropped like screenshots, side by side under centred text.
func panelSlide(_ scenes: [Scene], title: String, detail: String, scale: CGFloat) -> PreviewCanvas {
    let view = plainSlide()
    let gap: CGFloat = 48, bottom: CGFloat = 48
    let size = NSSize(width: scenes[0].size.width * scale, height: scenes[0].size.height * scale)
    var x = (slideSize.width - CGFloat(scenes.count) * size.width - CGFloat(scenes.count - 1) * gap) / 2
    for scene in scenes {
        let image = NSImage(size: size)
        image.addRepresentation(render(canvas(scene), scale: scale))
        view.panels.append((image, NSRect(origin: NSPoint(x: x, y: bottom), size: size)))
        x += size.width + gap
    }
    let top = bottom + size.height
    view.captions = stack(titled(title, detail), x: slideSize.width / 2,
                          midY: (top + slideSize.height) / 2, centered: true)
    return view
}

/// Lines of Swift in `Sources/`, as `wc -l` counts them.
let swiftLines = try FileManager.default.contentsOfDirectory(atPath: "Sources").filter { $0.hasSuffix(".swift") }
    .map { try String(contentsOfFile: "Sources/\($0)", encoding: .utf8).filter { $0 == "\n" }.count }.reduce(0, +)

var custom = MetricLayout()
custom.setTop(.battery, at: 1)
custom.setTop(.disk, at: 2)
let panel = Scene(size: NSSize(width: 300, height: menuBarHeight + IslandContentView.height + 22), x: 20)

let hero = sceneSlide(Scene(size: NSSize(width: slideSize.width / 3, height: slideSize.height / 3), x: 122, progress: 0), scale: 3)
hero.captions = stack(titled("tinyStats", "System stats beside your MacBook's notch.", size: 104, detailSize: 34),
                      x: slideSize.width / 2, midY: 318, centered: true)

let facts = plainSlide()
// 420 KB: `./build.sh && du -sh tinyStats.app`; update it with the app.
let factLines = ["\(swiftLines.formatted(.number.locale(Locale(identifier: "en_US")))) lines of Swift",
                 "No dependencies", "420 KB app", "No network access, no telemetry"]
let factText = titled("Small on purpose.") + factLines.enumerated().map { ($0.element, subline, quiet, $0.offset == 0 ? 30 : 14) }
let iconSide: CGFloat = 320, textWidth = factText.map { ($0.text as NSString).size(withAttributes: [.font: $0.font]).width }.max()!
let iconX = ((slideSize.width - iconSide - 24 - textWidth) / 2).rounded()
let iconImage = NSImage(size: NSSize(width: iconSide, height: iconSide))
iconImage.addRepresentation(icon(pixels: iconSide))
facts.images = [(iconImage, NSRect(x: iconX, y: (slideSize.height - iconSide) / 2, width: iconSide, height: iconSide))]
facts.captions = stack(factText, x: iconX + iconSide + 24, midY: slideSize.height / 2)

let gallery: [PreviewCanvas] = [
    hero,
    detailSlide(notch: true, title: "Click for the details.", detail: "CPU, GPU, RAM, network, battery, disk and swap."),
    detailSlide(notch: false, title: "No notch?\nIt lives in the menu bar."),
    panelSlide([panel, Scene(size: panel.size, x: panel.x, layout: custom)], title: "Pick what the three bars show.",
               detail: "Each tile can be CPU, GPU, RAM, Battery or Disk.", scale: 1.6),
    facts,
]
for (index, view) in gallery.enumerated() {
    try write(render(view, scale: view.pixelScale), to: "docs/launch/gallery-\(index + 1).png")
}

// MARK: - Demo animation

/// Open, hold, close at the notch, stepped by the app's own spring at 100 Hz
/// and played at 50 fps, so every motion gets 30+ frames at half speed.
func writeDemo(to path: String) throws {
    var frames: [(progress: CGFloat, delay: Double)] = [(0, 1.2)]
    var spring = Spring()
    for (target, parameters, hold) in [(1.0, Spring.opening, 2.4), (0.0, Spring.closing, 0.02)] {
        spring.retarget(target, parameters)
        repeat {
            spring.advance(by: 0.01)
            frames.append((CGFloat(spring.value), 0.02))
        } while !spring.isSettled
        frames[frames.count - 1].delay = hold
    }
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "com.compuserve.gif" as CFString,
                                                      frames.count, nil)!
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in frames {
        let image = render(canvas(Scene(progress: frame.progress))).cgImage!
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: frame.delay, kCGImagePropertyGIFUnclampedDelayTime: frame.delay]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    print("demo.gif: \(frames.count) frames")
}
try writeDemo(to: "docs/images/demo.gif")
