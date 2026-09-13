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

    // MARK: Ink

    /// #1B1D22: a warm near-black that stays soft on white glass.
    public static let inkBase = Color(red: 0.106, green: 0.114, blue: 0.133)
    public var ink: Color { Self.inkBase.opacity(increaseContrast ? 1.0 : 0.88) }
    public var inkLabel: Color { Self.inkBase.opacity(increaseContrast ? 0.80 : 0.60) }
    public var inkTertiary: Color { Self.inkBase.opacity(increaseContrast ? 0.62 : 0.40) }
    public var danger: Color { Color(red: 0.93, green: 0.27, blue: 0.22) }
    public var focusRing: Color { Self.inkBase.opacity(0.5) }

    // MARK: Glass (the panel itself; PanelChrome draws these in AppKit)

    /// White tint over the behind-window blur. Solid when transparency is reduced.
    public var glassTint: Color { Color.white.opacity(reduceTransparency ? 0.96 : 0.58) }
    /// The specular sheen, a radial highlight in the top-left.
    public var glassSheen: Color { reduceTransparency ? .clear : Color.white.opacity(0.55) }
    public var glassEdgeLight: Color { Color.white.opacity(0.7) }
    public var glassEdgeDark: Color { Self.inkBase.opacity(increaseContrast ? 0.25 : 0.08) }

    // MARK: Surfaces on glass

    /// Buttons, cards, menus: a lighter pane that stands proud of the panel.
    public var raised: Color { Color.white.opacity(0.55) }
    public var raisedHover: Color { Color.white.opacity(0.72) }
    /// Slider tracks, editors, wells: a pane cut into the panel.
    public var inset: Color { Color.white.opacity(0.35) }
    public var insetShadow: Color { Self.inkBase.opacity(0.10) }
    /// Slider fills and selection: sky over glass (#DCEBFF).
    public var tintSky: Color { Color(red: 0.863, green: 0.922, blue: 1.0).opacity(0.7) }
    /// A deeper sky for the fill while it is being dragged.
    public var tintSkyActive: Color { Color(red: 0.776, green: 0.867, blue: 1.0).opacity(0.85) }
    /// The permission card (#FFE9C7).
    public var tintAmber: Color { Color(red: 1.0, green: 0.914, blue: 0.78).opacity(0.8) }
    public var shadowSoft: Color { Self.inkBase.opacity(0.08) }
    public var shadowContact: Color { Self.inkBase.opacity(0.10) }
    /// Hairline between sections of one panel.
    public var hairline: Color { Self.inkBase.opacity(increaseContrast ? 0.2 : 0.06) }

    // MARK: Names the rows were written against (kept so every call site reads
    // naturally; they resolve to the glass tokens above).

    public var panel: Color { .white }
    public var dropdown: Color { .white }
    public var surface: Color { inset }
    public var surfaceHover: Color { Color.white.opacity(0.5) }
    public var surfaceActive: Color { tintSky }
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

    public static let label = Font.system(size: 13, weight: .medium)
    public static let value = Font.system(size: 13, weight: .medium, design: .monospaced)
    public static let rootTitle = Font.system(size: 15, weight: .semibold)
    public static let folderTitle = Font.system(size: 13, weight: .semibold)
    public static let caption = Font.system(size: 11, weight: .medium)
    /// The smallest text on any surface: 10 pt is the macOS floor, and small
    /// text wants a touch of positive tracking to stay legible.
    public static let captionSmall = Font.system(size: 10, weight: .medium)
    public static let captionSmallTracking: CGFloat = 0.2
    /// Names under thumbnails and similar 11-pt labels.
    public static let cardTitle = Font.system(size: 11, weight: .medium)
    public static let cardTitleTracking: CGFloat = 0.1
    /// Quiet uppercase section label.
    public static let eyebrow = Font.system(size: 10.5, weight: .semibold)
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
