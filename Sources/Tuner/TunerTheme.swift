import AppKit
import SwiftUI

/// The visual system for every Tuner surface: light liquid glass.
///
/// One appearance. Every panel is a sheet of frosted glass over the desktop
/// (blur, a white tint, a specular sheen, a light edge), controls sit on it as
/// raised or inset glass, and text is ink. The app forces the Aqua appearance
/// on its windows so the glass reads the same over any wallpaper and in any
/// system appearance. Hand-built, so it runs on macOS 14 and up.
///
/// The layout and motion language (fill-slider rows, folders, versions) was
/// inspired by Josh Puckett's web tuning panel; the motion rules follow Emil
/// Kowalski's design-engineering skills. Both are credited in the README.
public struct TunerTheme {
    /// System Settings → Accessibility → Display. Read when the theme is built,
    /// which happens on every environment read, so a change shows on the next
    /// view update. Reduce Transparency makes the glass solid; Increase
    /// Contrast darkens ink and edges.
    public let reduceTransparency: Bool
    public let increaseContrast: Bool

    public init(reduceTransparency: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                increaseContrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast) {
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }

    // MARK: The palette
    //
    // Nine neutrals, two washes and one gradient. Everything below is one of
    // these; nothing else gets a colour.

    public static let voidBlack = Color(red: 0.008, green: 0.008, blue: 0.016)   // #020204 dramatic dark
    public static let pureBlack = Color.black                                   // #000000 primary text, icons
    public static let carbon = Color(red: 0.388, green: 0.388, blue: 0.388)     // #636363 secondary text
    public static let slate = Color(red: 0.533, green: 0.533, blue: 0.533)      // #888888 tertiary text, disabled
    public static let silver = Color(red: 0.776, green: 0.776, blue: 0.776)     // #C6C6C6 placeholders, dividers
    public static let softGraphite = Color(red: 0.341, green: 0.341, blue: 0.341) // #575757 dark button fill
    public static let paperWhite = Color.white                                  // #FFFFFF cards
    public static let bone = Color(red: 0.973, green: 0.973, blue: 0.973)       // #F8F8F8 the canvas
    public static let linen = Color(red: 0.937, green: 0.937, blue: 0.937)      // #EFEFEF pills, wells, header wash
    public static let limeWash = Color(red: 0.949, green: 0.988, blue: 0.702)   // #F2FCB3 accent wash, selection
    public static let saffron = Color(red: 1.0, green: 0.863, blue: 0.361)      // #FFDC5C warm highlight
    /// Spectrum Marquee, the brand's signature gradient, left to right:
    /// blue → lavender → amber → red → magenta.
    public static let spectrum = Gradient(stops: [
        .init(color: Color(red: 0.012, green: 0.345, blue: 0.969), location: 0),
        .init(color: Color(red: 0.882, green: 0.882, blue: 0.996), location: 0.275),
        .init(color: Color(red: 1.0, green: 0.690, blue: 0.020), location: 0.572),
        .init(color: Color(red: 0.980, green: 0.239, blue: 0.114), location: 0.84),
        .init(color: Color(red: 0.992, green: 0.008, blue: 0.961), location: 1),
    ])
    /// The spectrum's blue, for the "live" status dot.
    public static let spectrumBlue = Color(red: 0.012, green: 0.345, blue: 0.969)

    // MARK: Ink

    /// Kept for callers that tint with alpha; Pure Black is the base.
    public static let inkBase = pureBlack
    public var ink: Color { Self.pureBlack }
    public var inkLabel: Color { increaseContrast ? Self.pureBlack : Self.carbon }
    public var inkTertiary: Color { increaseContrast ? Self.carbon : Self.slate }
    public var danger: Color { Color(red: 0.980, green: 0.239, blue: 0.114) }
    public var focusRing: Color { Self.carbon }

    // MARK: Glass (the panel itself; PanelChrome draws these in AppKit)

    /// The canvas is Bone, nearly opaque over the blur so the desktop is only a
    /// hint behind it. Fully solid when transparency is reduced.
    public var glassTint: Color { reduceTransparency ? Self.bone : Self.bone.opacity(0.95) }
    /// The specular sheen, a radial highlight in the top-left.
    public var glassSheen: Color { reduceTransparency ? .clear : Color.white.opacity(0.55) }
    public var glassEdgeLight: Color { Self.paperWhite.opacity(0.8) }
    public var glassEdgeDark: Color { increaseContrast ? Self.carbon : Self.silver.opacity(0.7) }

    // MARK: Surfaces on glass

    /// Buttons, cards, menus: Paper White standing proud of the canvas.
    public var raised: Color { Self.paperWhite.opacity(0.9) }
    public var raisedHover: Color { Self.paperWhite }
    /// Slider tracks, editors, wells: Linen cut into the canvas.
    public var inset: Color { Self.linen }
    public var insetShadow: Color { Self.pureBlack.opacity(0.10) }
    /// Soft-clay depth: a dark shadow to the bottom-right and a light one to
    /// the top-left, the way a raised pane sits under a lamp.
    public var shadowLight: Color { Self.paperWhite.opacity(0.9) }
    /// The dark fill for the one strong action and for switches that are on.
    public var buttonDark: Color { Self.softGraphite }
    /// Selection: Lime Wash.
    public var tintSky: Color { Self.limeWash }
    public var tintSkyActive: Color { Self.saffron }
    /// Warm highlight zones: the permission card.
    public var tintAmber: Color { Self.saffron.opacity(0.45) }
    public var shadowSoft: Color { Self.pureBlack.opacity(0.10) }
    public var shadowContact: Color { Self.pureBlack.opacity(0.10) }
    /// Hairline between sections of one panel: Silver.
    public var hairline: Color { increaseContrast ? Self.carbon : Self.silver.opacity(0.6) }

    // MARK: Names the rows were written against (kept so every call site reads
    // naturally; they resolve to the glass tokens above).

    public var panel: Color { .white }
    public var dropdown: Color { .white }
    public var surface: Color { inset }
    public var surfaceHover: Color { Color.white.opacity(0.5) }
    public var surfaceActive: Color { tintAmber }
    public var surfaceSubtle: Color { hairline }
    public var border: Color { glassEdgeDark }
    public var borderHover: Color { tintSkyActive }
    public var textRoot: Color { ink }
    public var textPrimary: Color { ink }
    public var textLabel: Color { inkLabel }
    public var textTertiary: Color { inkTertiary }
    public var innerHighlight: Color { glassEdgeLight }
    public var elevated: Color { .clear }
    public var panelGlass: Color { glassTint }

    // MARK: Metrics

    public static let panelWidth: CGFloat = 280
    public static let previewWidth: CGFloat = 300
    public static let rowHeight: CGFloat = 36
    public static let rowGap: CGFloat = 6
    public static let rowRadius: CGFloat = 12
    public static let cardRadius: CGFloat = 16
    public static let panelRadius: CGFloat = 22
    public static let collapsedSize: CGFloat = 44
    public static let paddingH: CGFloat = 12
    public static let paddingV: CGFloat = 10

    // MARK: Fonts
    //
    // Text is Apfel Grotezk (see TunerFonts); numbers are the system monospaced
    // face so values line up while they change.

    public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { TunerFonts.font(size, weight: weight) }
    public static var label: Font { font(13, weight: .medium) }
    public static let value = Font.system(size: 13, weight: .medium, design: .monospaced)
    public static var rootTitle: Font { font(16, weight: .semibold) }
    public static var folderTitle: Font { font(13, weight: .semibold) }
    public static var caption: Font { font(11, weight: .medium) }
    /// The smallest text on any surface: 10 pt is the macOS floor, and small
    /// text wants a touch of positive tracking to stay legible.
    public static var captionSmall: Font { font(10, weight: .medium) }
    public static let captionSmallTracking: CGFloat = 0.2
    /// Names under thumbnails and similar 11-pt labels.
    public static var cardTitle: Font { font(11, weight: .medium) }
    public static let cardTitleTracking: CGFloat = 0.1
    /// Quiet uppercase section label.
    public static var eyebrow: Font { font(10.5, weight: .semibold) }
    public static let eyebrowTracking: CGFloat = 0.6

    // MARK: Motion
    //
    // Critically damped by default: a surface that merely appears, a row that
    // hovers has no momentum to spend on a bounce. `liquid` is the one exception,
    // for knobs and pills that travel: they settle with a little give, which is
    // what makes the glass feel fluid. Curves and values follow Emil Kowalski's
    // design-engineering rules; see README credits.
    public static let spring = Animation.spring(response: 0.3, dampingFraction: 0.95)
    public static let quick = Animation.spring(response: 0.18, dampingFraction: 1.0)
    /// Press feedback: fires on mouse-down and settles within ~150 ms.
    public static let press = Animation.spring(response: 0.15, dampingFraction: 1.0)
    /// A knob or selection pill on the move.
    public static let liquid = Animation.spring(response: 0.35, dampingFraction: 0.72)
    /// The Tuner bubble ⇄ panel morph, and the popover materialising.
    public static let morphDuration: Double = 0.22
    /// Strong ease-out, cubic-bezier(0.23, 1, 0.32, 1): entrances, exits, fades.
    /// The built-in `.easeOut` is too weak to read as intentional.
    public static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }
    /// Strong ease-in-out, cubic-bezier(0.77, 0, 0.175, 1): things already on
    /// screen moving from A to B.
    public static func easeInOut(_ duration: Double) -> Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: duration)
    }
    /// What movement-free changes become under Reduce Motion: a short fade,
    /// because reduced motion means gentler, not none.
    public static let reducedFade = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
    /// Slow-motion review. `SHUT_MOTION_SCALE=4` plays every UI animation four
    /// times slower so timing and easing can be judged frame by frame.
    public static let motionScale: Double = {
        let raw = ProcessInfo.processInfo.environment["SHUT_MOTION_SCALE"] ?? ""
        return max(Double(raw) ?? 1, 0.1)
    }()

    /// The animation a modifier actually applies. Pure, so it is testable:
    /// `motion` is true for anything that moves or scales, which Reduce Motion
    /// drops; everything else (opacity, colour, fill) becomes `reducedFade`.
    public static func resolve(_ animation: Animation, motion: Bool, reduceMotion: Bool) -> Animation? {
        if reduceMotion { return motion ? nil : reducedFade }
        return motionScale == 1 ? animation : animation.speed(1 / motionScale)
    }

    /// The one appearance every Shut window uses.
    public static var appearance: NSAppearance? { NSAppearance(named: .aqua) }
}

struct TunerThemeKey: EnvironmentKey {
    static let defaultValue: TunerTheme? = nil
}

public extension EnvironmentValues {
    /// One light theme everywhere, unless a host pins one explicitly (tests use
    /// this to render the solid, high-contrast variant).
    var tunerTheme: TunerTheme {
        get { self[TunerThemeKey.self] ?? TunerTheme() }
        set { self[TunerThemeKey.self] = newValue }
    }
}

public extension View {
    /// Pins the light appearance on a SwiftUI subtree, for hosts that can't set
    /// it on the window.
    func tunerThemed() -> some View { environment(\.colorScheme, .light) }
}

public extension View {
    /// For opacity, colour and fill changes. Under Reduce Motion it becomes a
    /// short fade rather than an instant cut.
    func tunerAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(TunerAnimated(animation: animation, value: value, motion: false))
    }

    /// For anything that moves, scales or re-lays out. Under Reduce Motion it is
    /// dropped entirely.
    func tunerMotion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(TunerAnimated(animation: animation, value: value, motion: true))
    }
}

private struct TunerAnimated<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let animation: Animation
    let value: V
    let motion: Bool
    func body(content: Content) -> some View {
        content.animation(TunerTheme.resolve(animation, motion: motion, reduceMotion: reduce), value: value)
    }
}

/// Number formatting shared by rows: decimals derived from the step, like the
/// web panel does, so 0.05 steps show two places and integer steps show none.
enum TunerFormat {
    static func decimals(step: Double?, range: ClosedRange<Double>, fallback: Int) -> Int {
        guard let step, step > 0 else { return fallback }
        if step >= 1 { return 0 }
        let d = Int(ceil(-log10(step) - 1e-9))
        return min(max(d, 0), 4)
    }

    static func string(_ value: Double, decimals: Int, unit: String) -> String {
        let number = String(format: "%.\(decimals)f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}
