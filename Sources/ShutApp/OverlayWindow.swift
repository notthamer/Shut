import AppKit
import TransitionKit
import Tuner

/// The borderless, click-through window that covers the built-in display while
/// a transition plays. It sits at screen-saver level so it's above full-screen
/// apps and the menu bar, joins every Space, and never takes focus.
///
/// It is an `NSPanel` with `.nonactivatingPanel`, not a plain `NSWindow`, and
/// that is load-bearing. Shut is a Dock app (`.regular` activation policy) when
/// "In Dock" is on, and macOS 26 refuses to place a plain window of a Dock app
/// on another Space or over another app's full-screen Space, whatever its
/// collection behavior says: `isOnActiveSpace` stays false and nothing is drawn.
/// A non-activating panel from the same process lands on the active Space every
/// time, as does any window from a menu-bar-only (`.accessory`) app. Measured
/// with a two-process experiment; see docs/ARCHITECTURE.md, "Spaces".
final class OverlayWindow: NSPanel {
    let metalView: MetalTransitionView
    private let captionView = ClosingCaptionView()

    init(screen: NSScreen, renderer: TransitionRenderer, transition: AnyTransition, context: RenderContext) {
        metalView = MetalTransitionView(renderer: renderer, transition: transition, context: context)
        // Use the designated initializer directly. The `screen:` variant calls back
        // into it, which a Swift subclass with its own init doesn't inherit, and
        // that call traps at runtime. `screen.frame` is in global coordinates, so
        // the window lands on the right display anyway.
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = Self.everySpace
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        hidesOnDeactivate = false      // NSPanel defaults to true; the lid doesn't care who is active
        becomesKeyOnlyIfNeeded = true
        isExcludedFromWindowsMenu = true
        // The Metal view and the caption are siblings: a CAMetalLayer-backed view
        // is not a place to hang subviews.
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.wantsLayer = true
        contentView = container
        for view in [metalView, captionView] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
    }

    /// The line Stay awake sets into the close: "Staying awake · Cursor is working".
    /// nil clears it. It never moves and never delays a frame: two text layers
    /// whose opacity follows the lid.
    func setCaption(_ text: String?) { captionView.text = text }
    func setCaptionProgress(_ progress: Double) { captionView.progress = progress }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Opaque black for snapshot styles; clear for mask styles that composite over
    /// the live desktop. Safe to call while ordered in.
    func setTransparent(_ transparent: Bool) {
        isOpaque = !transparent
        backgroundColor = transparent ? .clear : .black
        metalView.isTransparent = transparent
    }

    /// Wanted: one window that is on every desktop and full-screen Space.
    static let everySpace: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    /// Fallback: follow whichever Space is active when the window is ordered in.
    static let activeSpaceOnly: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    /// How the window ended up on screen, for the log.
    enum Placement: String { case everySpace, movedToActiveSpace, offActiveSpace }

    /// Orders the window in and makes sure it is on the Space the user is looking
    /// at. `canJoinAllSpaces` alone is not enough in practice: on macOS 15/26 the
    /// window server sometimes keeps a reused window on the Space where it was
    /// first ordered in, and `isOnActiveSpace` then reports false while the
    /// window is "visible". When that happens the window is re-ordered with
    /// `.moveToActiveSpace`, which pins it to the current Space (desktop or
    /// full-screen app). That is exactly where the lid is closing, and the
    /// window is hidden again before the user could switch away.
    @discardableResult
    func show(on screen: NSScreen) -> Placement {
        setFrame(screen.frame, display: false)
        collectionBehavior = Self.everySpace
        orderFrontRegardless()
        if isOnActiveSpace { return .everySpace }

        orderOut(nil)
        collectionBehavior = Self.activeSpaceOnly
        setFrame(screen.frame, display: false)
        orderFrontRegardless()
        return isOnActiveSpace ? .movedToActiveSpace : .offActiveSpace
    }

    func hide() {
        orderOut(nil)
    }
}

/// Low on the panel, where a closing lid is still readable. Playfair, white, a soft
/// shadow so it holds over any desktop. Fades in as the effect begins.
final class ClosingCaptionView: NSView {
    private let first = CATextLayer()
    private let second = CATextLayer()

    var text: String? { didSet { if text != oldValue { needsLayout = true } } }
    /// 0 = open, 1 = shut.
    var progress: Double = 0 {
        didSet {
            let alpha = Float(min(max((progress - 0.04) / 0.18, 0), 1))
            guard alpha != first.opacity else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            first.opacity = alpha
            second.opacity = alpha * 0.82
            CATransaction.commit()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for line in [first, second] {
            line.foregroundColor = NSColor.white.cgColor
            line.shadowColor = NSColor.black.cgColor
            line.shadowOpacity = 0.55
            line.shadowRadius = 10
            line.shadowOffset = CGSize(width: 0, height: -2)
            line.opacity = 0
            line.alignmentMode = .left
            layer?.addSublayer(line)
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let parts = (text ?? "").components(separatedBy: " · ")
        // Sized against a 14-inch panel (982 pt tall) and scaled with the display.
        let scale = max(bounds.height / 982, 0.6)
        let margin = bounds.width * 0.07
        let sizes: [CGFloat] = [44 * scale, 30 * scale]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, line) in [first, second].enumerated() {
            let string = index < parts.count ? parts[index] : ""
            let font = TunerFonts.nsDisplay(sizes[index])
            line.string = NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: NSColor.white, .kern: -0.8 * scale])
            line.contentsScale = window?.backingScaleFactor ?? 2
            let height = ceil(font.ascender - font.descender) + 4
            let y = index == 0 ? bounds.height * 0.12 + sizes[1] * 1.4 : bounds.height * 0.12
            line.frame = CGRect(x: margin, y: y, width: bounds.width - margin * 2, height: height)
            line.isHidden = string.isEmpty
        }
        CATransaction.commit()
    }
}
