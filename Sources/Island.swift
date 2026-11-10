import AppKit
import QuartzCore

// MARK: - Details island

/// Draws the silhouette for the current progress, fading it between
/// transparent and black, and reveals the content inside the body as it opens.
final class IslandView: NSView {
    private let content: IslandContentView
    private let clip = NSView()
    private(set) var layout: IslandLayout?
    private(set) var progress: CGFloat = 0

    init(content: IslandContentView) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        clip.wantsLayer = true
        clip.clipsToBounds = true
        clip.autoresizesSubviews = false
        clip.layer?.masksToBounds = true
        addSubview(clip)
        clip.addSubview(content)
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    func configure(_ layout: IslandLayout) {
        self.layout = layout
        clip.layer?.maskedCorners = layout.isFloating
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        frame = NSRect(origin: .zero, size: layout.frame.size)
        content.layout(width: layout.width)
        setProgress(progress)
    }

    func setProgress(_ value: CGFloat) {
        progress = value
        guard let layout else { return }
        needsDisplay = true
        let body = layout.bodyRect(at: value)
        clip.isHidden = body.height < 1
        clip.frame = body
        clip.layer?.cornerRadius = layout.shape(at: value).radius
        let final = layout.finalBodyRect
        content.setFrameOrigin(NSPoint(x: final.minX - body.minX,
                                       y: final.maxY - body.minY - content.frame.height + Choreography.contentDrop(value)))
        content.alphaValue = Choreography.contentAlpha(value)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let layout else { return }
        // The notch is solid black, so its extension is too; only the floating card fades in.
        NSColor.black.withAlphaComponent(layout.isFloating ? Choreography.backgroundAlpha(progress) : 1).setFill()
        layout.path(at: progress).fill()
    }

    func shapeContains(_ point: NSPoint) -> Bool { layout?.path(at: progress).contains(point) ?? false }
}

/// Clear, borderless, non-activating window at menu bar level on every Space.
/// Never pushed below the menu bar: the wing and the island live in it.
class OverlayPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        allowsToolTipsWhenApplicationIsInactive = true
        self.contentView = contentView
    }

    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Becomes key so Escape and ⌘Q reach it, without activating the app.
final class IslandPanel: OverlayPanel {
    var onCancel: (() -> Void)?

    override init(contentView: NSView) {
        super.init(contentView: contentView)
        appearance = NSAppearance(named: .darkAqua)
        setAccessibilityLabel("tinyStats")
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// The only details presenter: grows the island out of its source and back,
/// driven by one spring on the display link. Reversals retarget in flight.
final class IslandPresenter: NSObject {
    let view: IslandView
    let panel: IslandPanel
    private(set) var spring = Spring()
    private(set) var isPresented = false
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var fadeToken = 0
    private var sourceRect = NSRect.zero
    var onProgress: ((CGFloat) -> Void)?
    var onPresentedChange: ((Bool) -> Void)?
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(content: IslandContentView) {
        view = IslandView(content: content)
        panel = IslandPanel(contentView: view)
        super.init()
        panel.onCancel = { [weak self] in self?.close() }
    }

    /// `source` is the clickable origin in screen coordinates; clicks there
    /// belong to its own toggle and never count as outside clicks.
    func open(layout: IslandLayout, source: NSRect) {
        guard !isPresented else { return }
        isPresented = true
        sourceRect = source
        let still = reduceMotion()
        if !panel.isVisible || view.layout != layout {
            // A reversal keeps the geometry already in flight; a different
            // source or display grows anew from its own.
            view.configure(layout)
            panel.setFrame(layout.frame, display: false)
            spring.snap(to: 0)
            apply(0)
            panel.alphaValue = still ? 0 : 1
        }
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        onPresentedChange?(true)
        if still {
            spring.snap(to: 1)
            apply(1)
            fade(to: 1, completion: nil)
        } else {
            animate(to: 1, Spring.opening)
        }
    }

    func close(animated: Bool = true) {
        if isPresented {
            isPresented = false
            removeMonitors()
            panel.ignoresMouseEvents = true
            onPresentedChange?(false)
        } else if animated || !panel.isVisible {
            return
        }
        guard animated else { finishClose(); return }
        if reduceMotion() {
            fade(to: 0) { [weak self] in self?.finishClose() }
        } else {
            animate(to: 0, Spring.closing)
        }
    }

    private func finishClose() {
        guard !isPresented else { return }
        link?.isPaused = true
        fadeToken += 1
        spring.snap(to: 0)
        apply(0)
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func apply(_ progress: CGFloat) {
        view.setProgress(progress)
        onProgress?(progress)
    }

    /// Cancels a pending fade and lets the spring carry the shape to `target`.
    private func animate(to target: Double, _ parameters: Spring.Parameters) {
        fadeToken += 1
        panel.alphaValue = 1
        spring.retarget(target, parameters)
        if link == nil {
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        guard let link, link.isPaused else { return }
        lastTick = CACurrentMediaTime()
        link.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        // Step by presented frame time; callback time jitters from frame to frame.
        let now = link.targetTimestamp
        spring.advance(by: now - lastTick)
        lastTick = now
        apply(CGFloat(spring.value))
        guard spring.isSettled else { return }
        link.isPaused = true
        if spring.target == 0 { finishClose() }
    }

    private func fade(to alpha: CGFloat, completion: (() -> Void)?) {
        link?.isPaused = true
        fadeToken += 1
        let token = fadeToken
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = alpha
        } completionHandler: { [weak self] in
            guard let self, self.fadeToken == token else { return }
            completion?()
        }
    }

    enum Route: Equatable { case pass, close, consumeAndClose, quit }

    /// Event routing while presented. Clicks on the source pass through to its
    /// own toggle (never swallowed, never a second toggle); clicks inside the
    /// silhouette stay; anything else closes. Escape closes, ⌘Q quits.
    static func route(keyCode: UInt16?, command: Bool, characters: String?,
                      inPanel: Bool, insideShape: Bool, inSource: Bool) -> Route {
        if let keyCode {
            if keyCode == 53 { return .consumeAndClose }
            if command, characters?.lowercased() == "q" { return .quit }
            return .pass
        }
        if inPanel { return insideShape ? .pass : .close }
        return inSource ? .pass : .close
    }

    /// The local monitor's handler, installed as is; returning nil swallows the event.
    private(set) lazy var localHandler: (NSEvent) -> NSEvent? = { [weak self] event in
        guard let self else { return event }
        let key = event.type == .keyDown
        let inPanel = event.window === panel
        switch Self.route(keyCode: key ? event.keyCode : nil, command: event.modifierFlags.contains(.command),
                          characters: key ? event.charactersIgnoringModifiers : nil, inPanel: inPanel,
                          insideShape: inPanel && view.shapeContains(event.locationInWindow),
                          inSource: sourceRect.contains(NSEvent.mouseLocation)) {
        case .pass: return event
        case .close: close(); return event
        case .consumeAndClose: close(); return nil
        case .quit: NSApp.terminate(nil); return nil
        }
    }

    private func installMonitors() {
        removeMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors = [
            NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: localHandler),
            // Clicks in other apps are always outside the panel; only the source keeps them.
            NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
                guard let self, !sourceRect.contains(NSEvent.mouseLocation) else { return }
                close()
            },
        ].compactMap { $0 }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            // Another app came forward (⌘Tab, Dock); our own key focus does not count.
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if activated?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.close() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in self?.close() })
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
    }

    deinit { removeMonitors() }
}

// MARK: - Notch wing window

/// Draws the wing and the indicator white on black.
final class WingView: NSView {
    var wing: NotchWing? { didSet { needsDisplay = true } }
    var attach: CGFloat = 0 { didSet { if attach != oldValue { needsDisplay = true } } }
    /// Radius (width) and rise (height) of the lower-right corner while the
    /// island hangs below; nil draws the corner from `attach` alone.
    var corner: NSSize? { didSet { if corner != oldValue { needsDisplay = true } } }
    var indicator: NSImage? { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let wing else { return }
        // The strip behind the housing answers only while the details hang below.
        if wing.hitRect.contains(convert(event.locationInWindow, from: nil)) || attach > 0 { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let wing else { return }
        NSColor.black.setFill()
        (corner.map { wing.path(radius: $0.width, rise: $0.height) } ?? wing.path(attach: attach)).fill()
        guard let indicator, let context = NSGraphicsContext.current else { return }
        let target = wing.indicatorRect
        context.saveGraphicsState()
        // Tint the template: keep its alpha, replace its colour with white.
        context.cgContext.beginTransparencyLayer(in: target, auxiliaryInfo: nil)
        indicator.draw(in: target)
        NSColor.white.setFill()
        target.fill(using: .sourceAtop)
        context.cgContext.endTransparencyLayer()
        context.restoreGraphicsState()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

/// Never key: a click on the wing leaves focus where it was.
final class WingPanel: OverlayPanel {
    let wingView = WingView()

    init() { super.init(contentView: wingView) }

    override var canBecomeKey: Bool { false }

    func place(_ wing: NotchWing) {
        wingView.wing = wing
        wingView.attach = 0
        setFrame(wing.frame, display: false)
    }
}
