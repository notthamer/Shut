import AppKit
import SwiftUI

/// Hosts any SwiftUI content in a floating, borderless, non-activating panel that
/// collapses to a small circle and remembers where it was.
///
/// Toggle it from a menu item or the ⌃⌥T hot key. The host calls
/// `setHiddenForTransition` so the panel never sits on top of a real transition.
@MainActor
public final class TunerPanelController {
    public let panel: NSPanel
    private let hosting: NSHostingView<AnyView>
    private var content: AnyView
    private var hotKey: HotKey?
    private var hiddenForTransition = false
    private var wasVisibleBeforeTransition = false
    private(set) var isCollapsed = false
    private var expandedFrame: NSRect?
    private let frameKey: String

    public static let defaultSize = NSSize(width: TunerTheme.panelWidth, height: 640)

    /// - Parameter width: 280 for dials only; wider when the host injects a preview column.
    public init(title: String, content: AnyView, width: CGFloat = TunerTheme.panelWidth, frameKey: String = "tuner.panel.frame") {
        self.content = content
        self.frameKey = frameKey
        hosting = FirstMouseHostingView(rootView: content)
        hosting.sizingOptions = []
        let size = NSSize(width: width, height: Self.defaultSize.height)
        panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel, .resizable, .utilityWindow],
                             backing: .buffered, defer: false)
        panel.title = title
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: TunerTheme.collapsedSize, height: TunerTheme.collapsedSize)

        let container = PanelChrome(frame: NSRect(origin: .zero, size: size))
        container.hosting = hosting
        container.install(hosting)
        panel.contentView = container

        if let saved = UserDefaults.standard.string(forKey: frameKey), !saved.isEmpty {
            let frame = NSRectFromString(saved)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { panel.setFrame(frame, display: false) }
            else { positionNearTopRight() }
        } else {
            positionNearTopRight()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            self?.saveFrame()
        }
    }

    public func setContent(_ content: AnyView) {
        self.content = content
        if !isCollapsed { hosting.rootView = content }
    }

    /// Called with true/false as the panel appears and disappears; hosts use it
    /// to show a Dock icon only while the panel is up.
    public var onVisibilityChanged: ((Bool) -> Void)?

    public var isVisible: Bool { panel.isVisible }
    public func show() { panel.makeKeyAndOrderFront(nil); onVisibilityChanged?(true) }
    public func hide() { panel.orderOut(nil); onVisibilityChanged?(false) }
    public func toggle() { panel.isVisible ? hide() : show() }

    /// The host calls this when a real lid transition starts and ends.
    public func setHiddenForTransition(_ hidden: Bool) {
        if hidden {
            guard !hiddenForTransition else { return }
            hiddenForTransition = true
            wasVisibleBeforeTransition = panel.isVisible
            if wasVisibleBeforeTransition { hide() }
        } else {
            guard hiddenForTransition else { return }
            hiddenForTransition = false
            if wasVisibleBeforeTransition { show() }
        }
    }

    /// Registers a system-wide hot key (default ⌃⌥T) that toggles the panel.
    public func registerHotKey(keyCode: UInt32 = HotKey.keyT, modifiers: UInt32 = HotKey.controlOption) {
        hotKey = HotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in self?.toggle() }
    }

    /// Collapse to a 42-pt circle at the panel's top-right corner, or expand back.
    public func toggleCollapsed() {
        isCollapsed.toggle()
        let chrome = panel.contentView as? PanelChrome
        let target: NSRect
        if isCollapsed {
            expandedFrame = panel.frame
            let size = TunerTheme.collapsedSize
            target = NSRect(x: panel.frame.maxX - size, y: panel.frame.maxY - size, width: size, height: size)
        } else {
            target = expandedFrame.map { NSRect(x: panel.frame.maxX - $0.width, y: panel.frame.maxY - $0.height, width: $0.width, height: $0.height) }
                ?? NSRect(origin: panel.frame.origin, size: Self.defaultSize)
        }
        let collapsed = isCollapsed
        // Dia motion: the content crossfades; the frame simply changes.
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = (reduce ? 0 : 0.1) * TunerTheme.motionScale
            hosting.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                chrome?.isCollapsed = collapsed
                self.hosting.rootView = collapsed ? AnyView(CollapsedBubble { [weak self] in self?.toggleCollapsed() }) : self.content
                self.panel.setFrame(target, display: true)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = (reduce ? 0 : 0.2) * TunerTheme.motionScale
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
                    self.hosting.animator().alphaValue = 1
                }
            }
        })
    }

    private func saveFrame() {
        guard !isCollapsed else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameKey)
    }

    private func positionNearTopRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 16, y: visible.maxY - panel.frame.height - 16))
    }
}

/// A borderless panel that can take keyboard focus. Plain borderless windows
/// refuse to become key, and AppKit then swallows every click trying to make
/// them key, so nothing inside them works.
public final class KeyablePanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
    public override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        appearance = TunerTheme.appearance   // light glass, whatever the system appearance
    }
}

/// A hosting view whose content responds to the very first click even when its
/// window isn't key yet, the way menu bar panels are expected to. A mouse-down
/// inside it never moves the window: with `isMovableByWindowBackground` the
/// window would otherwise follow a slider drag. Windows that need to be moved
/// by their body use `WindowDragHandle` behind a header instead.
public final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
}

/// A transparent view that drags its window when pressed: the grip behind a
/// panel's header.
public struct WindowDragHandle: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    public func updateNSView(_ nsView: DragHandleView, context: Context) {}

    public final class DragHandleView: NSView {
        public override var mouseDownCanMoveWindow: Bool { false }
        public override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

/// The window chrome for every Shut panel: a sheet of Bone paper over a
/// behind-window blur (the reference's glass nav bar), a one-point Silver
/// border, 24-pt corners. A circle when collapsed. Public so a host can give
/// other floating windows the same material. The window's own shadow is the
/// only shadow: nothing inside casts one.
public final class PanelChrome: NSView {
    var hosting: NSHostingView<AnyView>?
    public var isCollapsed = false { didSet { updateShape() } }
    private let blur = NSVisualEffectView()
    private let tint = CALayer()
    private var accessibilityObserver: NSObjectProtocol?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        appearance = TunerTheme.appearance
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = TunerTheme.appearance
        blur.frame = bounds
        blur.autoresizingMask = [.width, .height]
        super.addSubview(blur)

        tint.zPosition = 1
        layer?.addSublayer(tint)

        applyAccessibility()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAccessibility() }
        }
        updateShape()
    }

    /// Reduce Transparency: no blur, solid Bone. Increase Contrast: a Carbon edge.
    private func applyAccessibility() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        blur.isHidden = reduce
        tint.backgroundColor = NSColor(red: 0.973, green: 0.973, blue: 0.973, alpha: reduce ? 1 : 0.95).cgColor   // Bone
        layer?.borderColor = (contrast ? NSColor(red: 0.388, green: 0.388, blue: 0.388, alpha: 1)
                                       : NSColor(red: 0.776, green: 0.776, blue: 0.776, alpha: 1)).cgColor   // Carbon / Silver
        hosting?.needsDisplay = true
    }

    /// Puts the content above the paper. Use this rather than addSubview.
    public func install(_ content: NSView) {
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.zPosition = 10
        addSubview(content, positioned: .above, relativeTo: blur)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    public override func layout() {
        super.layout()
        updateShape()
    }

    private func updateShape() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = isCollapsed ? min(bounds.width, bounds.height) / 2 : TunerTheme.panelRadius
        tint.frame = bounds
        CATransaction.commit()
    }
}

/// The 42-pt "mixer" bubble shown while collapsed.
struct CollapsedBubble: View {
    let expand: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var pressed = false

    var body: some View {
        ZStack {
            Color.clear
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.ink)
        }
        .opacity(pressed ? 0.55 : 1)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded { g in pressed = false; if hypot(g.translation.width, g.translation.height) < 8 { expand() } })
        .tunerAnimation(TunerTheme.quick, value: pressed)
        .tunerThemed()
    }
}
