import AppKit
import TransitionKit

/// The borderless, click-through window that covers the built-in display while
/// a transition plays. It sits at screen-saver level so it's above full-screen
/// apps and the menu bar, joins every Space, and never takes focus.
final class OverlayWindow: NSWindow {
    let metalView: MetalTransitionView

    init(screen: NSScreen, renderer: TransitionRenderer, transition: AnyTransition, context: RenderContext) {
        metalView = MetalTransitionView(renderer: renderer, transition: transition, context: context)
        // Use the designated initializer directly. The `screen:` variant calls back
        // into it, which a Swift subclass with its own init doesn't inherit, and
        // that call traps at runtime. `screen.frame` is in global coordinates, so
        // the window lands on the right display anyway.
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        hidesOnDeactivate = false
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

    func show(on screen: NSScreen) {
        setFrame(screen.frame, display: false)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
