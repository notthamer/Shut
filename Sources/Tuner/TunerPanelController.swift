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
        hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        let size = NSSize(width: width, height: Self.defaultSize.height)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
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
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
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
    public func show() { panel.orderFront(nil); onVisibilityChanged?(true) }
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
        if isCollapsed {
            expandedFrame = panel.frame
            let size = TunerTheme.collapsedSize
            let frame = NSRect(x: panel.frame.maxX - size, y: panel.frame.maxY - size, width: size, height: size)
            chrome?.isCollapsed = true
            hosting.rootView = AnyView(CollapsedBubble { [weak self] in self?.toggleCollapsed() })
            panel.setFrame(frame, display: true, animate: true)
        } else {
            chrome?.isCollapsed = false
            hosting.rootView = content
            let target = expandedFrame.map { NSRect(x: panel.frame.maxX - $0.width, y: panel.frame.maxY - $0.height, width: $0.width, height: $0.height) }
                ?? NSRect(origin: panel.frame.origin, size: Self.defaultSize)
            panel.setFrame(target, display: true, animate: true)
        }
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

/// Rounded panel background with a hairline border; a circle when collapsed.
final class PanelChrome: NSView {
    var hosting: NSHostingView<AnyView>?
    var isCollapsed = false { didSet { needsDisplay = true; updateMask() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        updateMask()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        updateMask()
    }

    private func updateMask() {
        layer?.cornerRadius = isCollapsed ? bounds.width / 2 : TunerTheme.panelRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
    }
}

/// The 42-pt "mixer" bubble shown while collapsed.
struct CollapsedBubble: View {
    let expand: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var pressed = false

    var body: some View {
        ZStack {
            theme.panel
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textRoot)
        }
        .scaleEffect(pressed ? 0.9 : 1)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded { g in pressed = false; if hypot(g.translation.width, g.translation.height) < 8 { expand() } })
        .tunerAnimation(TunerTheme.quick, value: pressed)
        .tunerThemed()
    }
}
