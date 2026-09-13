import AppKit
import SwiftUI

/// The visual system for every Tuner surface: an editorial broadsheet, after the
/// way The Browser Company designs Dia.
///
/// Bone paper, black ink, one-point Silver borders instead of shadows, floating
/// pills, a light serif for headlines, a humanist grotesk for copy, a mono for
/// eyebrows. Two washes (Lime, Saffron) and one gradient (the Spectrum Marquee,
/// used once as a thin line). Motion changes colour and opacity at 0.2 s, never
/// position. One appearance; every window forces Aqua so the paper reads the
/// same over any wallpaper and in dark mode.
public struct TunerTheme {
    /// System Settings → Accessibility → Display. Read when the theme is built,
    /// which happens on every environment read. Reduce Transparency makes the
    /// paper solid; Increase Contrast darkens secondary ink and borders.
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

    public static let voidBlack = Color(red: 0.008, green: 0.008, blue: 0.016)   // #020204 the dark stage (welcome)
    public static let pureBlack = Color.black                                   // #000000 primary text, icons, fills
    public static let carbon = Color(red: 0.388, green: 0.388, blue: 0.388)     // #636363 secondary text
    public static let slate = Color(red: 0.533, green: 0.533, blue: 0.533)      // #888888 tertiary text, disabled
    public static let silver = Color(red: 0.776, green: 0.776, blue: 0.776)     // #C6C6C6 borders, dividers, ticks
    public static let softGraphite = Color(red: 0.341, green: 0.341, blue: 0.341) // #575757 dark button fill
    public static let paperWhite = Color.white                                  // #FFFFFF cards, the primary button
    public static let bone = Color(red: 0.973, green: 0.973, blue: 0.973)       // #F8F8F8 the canvas
    public static let linen = Color(red: 0.937, green: 0.937, blue: 0.937)      // #EFEFEF pills, wells, header wash
    public static let limeWash = Color(red: 0.949, green: 0.988, blue: 0.702)   // #F2FCB3 selection, highlight zones
    public static let saffron = Color(red: 1.0, green: 0.863, blue: 0.361)      // #FFDC5C warm highlight
    /// Spectrum Marquee, the brand's signature gradient, left to right:
    /// blue → lavender → amber → red → magenta. Appears once, as a thin line.
    public static let spectrum = Gradient(stops: [
        .init(color: Color(red: 0.012, green: 0.345, blue: 0.969), location: 0),
        .init(color: Color(red: 0.882, green: 0.882, blue: 0.996), location: 0.275),
        .init(color: Color(red: 1.0, green: 0.690, blue: 0.020), location: 0.572),
        .init(color: Color(red: 0.980, green: 0.239, blue: 0.114), location: 0.84),
        .init(color: Color(red: 0.992, green: 0.008, blue: 0.961), location: 1),
    ])
    /// The spectrum's blue, for the "live" status dot.
    public static let spectrumBlue = Color(red: 0.012, green: 0.345, blue: 0.969)

    /// A wash for a style: its own hue at Lime Wash's saturation and
    /// brightness (#F2FCB3 is hue 68°, saturation 0.29, brightness 0.99), so
    /// every selection is the same weight of colour, only a different note.
    public static func wash(for id: String) -> Color {
        let hues: [String: Double] = [
            "fold": 68, "sinkhole": 250, "frost": 200, "crease": 30,
            "recede": 150, "slide": 340, "shutter": 45, "fade": 0,
        ]
        if id == "fade" { return Color(hue: 0, saturation: 0, brightness: 0.94) }
        let hue = hues[id] ?? Double(abs(id.hashValue % 360))
        return Color(hue: hue / 360, saturation: 0.29, brightness: 0.99)
    }

    // MARK: Roles

    public static let inkBase = pureBlack
    public var ink: Color { Self.pureBlack }
    public var inkLabel: Color { increaseContrast ? Self.pureBlack : Self.carbon }
    public var inkTertiary: Color { increaseContrast ? Self.carbon : Self.slate }
    public var danger: Color { Color(red: 0.980, green: 0.239, blue: 0.114) }
    public var focusRing: Color { Self.pureBlack }

    /// The canvas: Bone over the behind-window blur, solid when transparency is reduced.
    public var paper: Color { reduceTransparency ? Self.bone : Self.bone.opacity(0.95) }
    /// Cards and the primary button.
    public var card: Color { Self.paperWhite }
    /// Pills, wells, hover fills.
    public var linen: Color { Self.linen }
    /// The one-point edge on everything.
    public var border: Color { increaseContrast ? Self.carbon : Self.silver }
    public var borderHover: Color { Self.carbon }
    /// The primary button's edge.
    public var borderStrong: Color { Self.pureBlack }
    /// Section dividers.
    public var hairline: Color { increaseContrast ? Self.carbon : Self.silver.opacity(0.7) }
    /// Dark secondary fill: switches that are on, the Copy button.
    public var buttonDark: Color { Self.softGraphite }
    public var washLime: Color { Self.limeWash }
    public var washSaffron: Color { Self.saffron.opacity(0.55) }

    // MARK: Names older call sites use (kept so nothing breaks mid-migration)

    public var panel: Color { Self.paperWhite }
    public var dropdown: Color { Self.paperWhite }
    public var surface: Color { Self.linen }
    public var surfaceHover: Color { Self.linen }
    public var surfaceActive: Color { Self.limeWash }
    public var surfaceSubtle: Color { hairline }
    public var textRoot: Color { ink }
    public var textPrimary: Color { ink }
    public var textLabel: Color { inkLabel }
    public var textTertiary: Color { inkTertiary }
    public var innerHighlight: Color { .clear }
    public var elevated: Color { .clear }
    public var panelGlass: Color { paper }
    public var glassTint: Color { paper }
    public var glassSheen: Color { .clear }
    public var glassEdgeLight: Color { .clear }
    public var glassEdgeDark: Color { border }
    public var raised: Color { card }
    public var raisedHover: Color { Self.linen }
    public var inset: Color { Self.linen }
    public var insetShadow: Color { .clear }
    public var shadowSoft: Color { .clear }
    public var shadowContact: Color { .clear }
    public var shadowLight: Color { .clear }
    public var tintSky: Color { Self.limeWash }
    public var tintSkyActive: Color { Self.saffron }
    public var tintAmber: Color { washSaffron }

    // MARK: Metrics (Dia's radius set: 12, 20, 24, full)

    public static let panelWidth: CGFloat = 300
    public static let previewWidth: CGFloat = 300
    public static let rowHeight: CGFloat = 36
    public static let rowGap: CGFloat = 8
    public static let sectionGap: CGFloat = 24
    public static let cardRadius: CGFloat = 12
    public static let wellRadius: CGFloat = 12
    public static let rowRadius: CGFloat = 12
    public static let pillRadius: CGFloat = 20
    public static let panelRadius: CGFloat = 24
    public static let fullRadius: CGFloat = 999
    public static let collapsedSize: CGFloat = 44
    public static let paddingH: CGFloat = 16
    public static let paddingV: CGFloat = 12

    // MARK: Type scale
    //
    // display and heading in the serif; body and captions in the grotesk;
    // eyebrows and values in mono. Tracking is negative on the serif, wide and
    // uppercase on eyebrows, neutral elsewhere.

    public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { TunerFonts.font(size, weight: weight) }
    public static func display(_ size: CGFloat) -> Font { TunerFonts.display(size) }
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { TunerFonts.mono(size, weight: weight) }

    public static var displayFont: Font { display(28) }
    public static let displayTracking: CGFloat = -0.8
    public static var heading: Font { display(20) }
    public static let headingTracking: CGFloat = -0.5
    public static var body: Font { font(13) }
    public static var bodyMedium: Font { font(13, weight: .medium) }
    public static var bodySmall: Font { font(12) }
    public static var eyebrow: Font { mono(11) }
    public static let eyebrowTracking: CGFloat = 1.1
    public static let value = Font.system(size: 12, weight: .regular, design: .monospaced)

    // Older names.
    public static var label: Font { body }
    public static var rootTitle: Font { heading }
    public static var folderTitle: Font { eyebrow }
    public static var caption: Font { bodySmall }
    public static var captionSmall: Font { font(11) }
    public static let captionSmallTracking: CGFloat = 0
    public static var cardTitle: Font { bodySmall }
    public static let cardTitleTracking: CGFloat = 0

    // MARK: Motion
    //
    // One transition: 0.2 s on cubic-bezier(0.4, 0, 0.2, 1), applied to colour,
    // border and opacity. Nothing moves, scales or bounces; things change colour,
    // not position. The older names all resolve to it.
    public static let ease = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)
    public static let spring = ease
    public static let quick = ease
    public static let press = ease
    public static let liquid = ease
    public static let morphDuration: Double = 0.2
    public static func easeOut(_ duration: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: min(duration, 0.3)) }
    public static func easeInOut(_ duration: Double) -> Animation { easeOut(duration) }
    public static let reducedFade = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.12)
    /// Slow-motion review. `SHUT_MOTION_SCALE=4` plays every transition four
    /// times slower so timing can be judged frame by frame.
    public static let motionScale: Double = {
        let raw = ProcessInfo.processInfo.environment["SHUT_MOTION_SCALE"] ?? ""
        return max(Double(raw) ?? 1, 0.1)
    }()

    /// The animation a modifier actually applies. `motion` marks anything that
    /// would move or scale: that is never animated here, so it resolves to nil
    /// and the change is immediate. Colour and opacity changes get `ease`, or
    /// the shorter `reducedFade` under Reduce Motion.
    public static func resolve(_ animation: Animation, motion: Bool, reduceMotion: Bool) -> Animation? {
        if motion { return nil }
        if reduceMotion { return reducedFade }
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
    /// For opacity, colour and fill changes: the 0.2 s ease.
    func tunerAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(TunerAnimated(animation: animation, value: value, motion: false))
    }

    /// For anything that would move, scale or re-lay out. Never animated: the
    /// change is immediate.
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
