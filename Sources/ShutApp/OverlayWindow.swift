import AppKit
import TransitionKit

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
        contentView = metalView
        metalView.frame = contentView!.bounds
        metalView.autoresizingMask = [.width, .height]
    }

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
