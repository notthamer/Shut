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
    /// `animated`: the caption changed while on screen (Option was pressed), so crossfade.
    func setCaption(_ caption: AwakeText.Caption?, animated: Bool = false) {
        captionView.crossfadesNextChange = animated
        captionView.caption = caption
    }
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

/// Low on the panel, where a closing lid is still readable. Playfair, white, over a
/// soft dark gradient of its own so it holds on any wallpaper, a white one included.
/// Bad news is set in Saffron. Fades in as the effect begins.
final class ClosingCaptionView: NSView {
    private let scrim = CAGradientLayer()
    private let first = CATextLayer()
    private let second = CATextLayer()
    private let hint = CATextLayer()
    private var lines: [CATextLayer] { [first, second, hint] }
    /// How strongly each layer shows once fully faded in.
    private let strength: [Float] = [1, 0.86, 0.8]

    /// Top of the band to the bottom edge; shared with the preview's SwiftUI caption.
    static let scrimStops: [(location: Double, alpha: Double)] = [(0, 0), (0.45, 0.36), (0.8, 0.62), (1, 0.72)]
    static let scrimHeight = 0.42

    var caption: AwakeText.Caption? { didSet { if caption != oldValue { needsLayout = true } } }
    var crossfadesNextChange = false
    /// 0 = open, 1 = shut.
    var progress: Double = 0 {
        didSet {
            let alpha = Float(min(max((progress - 0.04) / 0.18, 0), 1))
            guard alpha != first.opacity else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (line, strength) in zip(lines, strength) { line.opacity = alpha * strength }
            scrim.opacity = caption == nil ? 0 : alpha
            CATransaction.commit()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Clear at the top of its band, about half black behind the headline and deeper
        // under the small hint: measured against a plain white desktop, where white type
        // needs at least that much to stay readable.
        scrim.colors = ClosingCaptionView.scrimStops.map { NSColor.black.withAlphaComponent($0.alpha).cgColor }
        scrim.locations = ClosingCaptionView.scrimStops.map { NSNumber(value: $0.location) }
        scrim.startPoint = CGPoint(x: 0.5, y: 1)
        scrim.endPoint = CGPoint(x: 0.5, y: 0)
        scrim.opacity = 0
        layer?.addSublayer(scrim)
        for line in lines {
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
        let parts = (caption?.text ?? "").components(separatedBy: " · ")
        let strings = [parts.first ?? "", parts.count > 1 ? parts[1] : "", caption?.hint ?? ""]
        // Sized against a 14-inch panel (982 pt tall) and scaled with the display.
        let scale = max(bounds.height / 982, 0.6)
        let margin = bounds.width * 0.07
        let fonts = [TunerFonts.nsDisplay(44 * scale), TunerFonts.nsDisplay(30 * scale), TunerFonts.nsFont(17 * scale)]
        let colors = [caption?.warning == true ? NSColor(TunerTheme.saffron) : .white, NSColor.white, .white]
        // From the bottom up: the hint, the second line, the headline.
        let base = bounds.height * 0.12
        let ys = [base + 30 * scale * 1.4, base, base - 17 * scale * 2.1]

        if crossfadesNextChange {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            lines.forEach { $0.add(fade, forKey: "caption") }
            crossfadesNextChange = false
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrim.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * Self.scrimHeight)
        scrim.isHidden = caption == nil
        for (index, line) in lines.enumerated() {
            let font = fonts[index]
            line.string = NSAttributedString(string: strings[index], attributes: [
                .font: font, .foregroundColor: colors[index], .kern: (index == 2 ? 0 : -0.8) * scale])
            line.contentsScale = window?.backingScaleFactor ?? 2
            let height = ceil(font.ascender - font.descender) + 4
            line.frame = CGRect(x: margin, y: ys[index], width: bounds.width - margin * 2, height: height)
            line.isHidden = strings[index].isEmpty
        }
        CATransaction.commit()
    }
}
