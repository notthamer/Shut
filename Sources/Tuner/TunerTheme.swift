import AppKit
import SwiftUI

/// The visual system for every Tuner surface. Neutral alphas over a near-black or
/// near-white panel; no accent colour anywhere, so the one inverted element (the
/// Copy button) reads as the primary action. Inspired by Josh Puckett's web
/// tuning panel, rebuilt natively.
public struct TunerTheme {
    public let isDark: Bool
    /// System Settings → Accessibility → Display. Read when the theme is built,
    /// which happens on every environment read, so a change shows on the next
    /// view update.
    public let reduceTransparency: Bool
    public let increaseContrast: Bool

    public init(colorScheme: ColorScheme,
                reduceTransparency: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                increaseContrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast) {
        isDark = colorScheme == .dark
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }

    // Surfaces
    public var panel: Color { isDark ? Color(red: 0.129, green: 0.129, blue: 0.129) : Color(red: 0.98, green: 0.98, blue: 0.98) }
    public var dropdown: Color { isDark ? Color(red: 0.165, green: 0.165, blue: 0.165) : .white }
    public var surface: Color { mono(isDark ? 0.05 : 0.04) }
    public var surfaceHover: Color { mono(isDark ? 0.10 : 0.08) }
    public var surfaceActive: Color { mono(isDark ? 0.11 : 0.10) }
    public var surfaceSubtle: Color { mono(isDark ? 0.06 : 0.06) }
    /// Increase Contrast asks for defined edges: the hairline steps up to a line.
    public var border: Color { mono(increaseContrast ? 0.28 : 0.10) }
    public var borderHover: Color { mono(increaseContrast ? 0.36 : 0.15) }

    // Text
    public var textRoot: Color { isDark ? .white : .black }
    public var textPrimary: Color { mono(isDark ? 0.95 : 0.90) }
    public var textLabel: Color { mono(isDark ? 0.70 : 0.60) }
    public var textTertiary: Color { mono(isDark ? 0.40 : 0.35) }
    public var focusRing: Color { mono(isDark ? 0.60 : 0.55) }
    public var danger: Color { Color(red: 1.0, green: 0.23, blue: 0.19) }
    /// A hairline of light along the top edge of a surface, the "edge catch"
    /// that makes glass read as glass.
    public var innerHighlight: Color { isDark ? Color.white.opacity(0.07) : Color.white.opacity(0.9) }
    /// Header and footer bands sit a step above the body.
    public var elevated: Color { isDark ? Color.white.opacity(0.025) : Color.black.opacity(0.02) }
    /// Panel fill with a little translucency so a blur behind it shows through.
    /// Reduce Transparency makes it solid (the chrome drops its blur too).
    public var panelGlass: Color { reduceTransparency ? panel : panel.opacity(isDark ? 0.86 : 0.9) }

    /// White alpha in dark mode, black alpha in light.
    private func mono(_ alpha: Double) -> Color {
        Color(white: isDark ? 1 : 0).opacity(alpha)
    }

    // Metrics
    public static let panelWidth: CGFloat = 280
    public static let previewWidth: CGFloat = 300
    public static let rowHeight: CGFloat = 36
    public static let rowGap: CGFloat = 6
    public static let rowRadius: CGFloat = 8
    public static let panelRadius: CGFloat = 14
    public static let collapsedSize: CGFloat = 42
    public static let paddingH: CGFloat = 12
    public static let paddingV: CGFloat = 10

    // Fonts
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

    // Motion. Critically damped by default: a surface that merely appears, a
    // pill that toggles, a row that hovers has no momentum to spend on a bounce.
    // Bounce belongs to gestures that carried velocity (the slider's rubber band)
    // and to the effects themselves. Curves and values follow Emil Kowalski's
    // design-engineering rules; see README credits.
    public static let spring = Animation.spring(response: 0.3, dampingFraction: 0.95)
    public static let quick = Animation.spring(response: 0.18, dampingFraction: 1.0)
    /// Press feedback: fires on mouse-down and settles within ~150 ms.
    public static let press = Animation.spring(response: 0.15, dampingFraction: 1.0)
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
}

struct TunerThemeKey: EnvironmentKey {
    static let defaultValue: TunerTheme? = nil
}

public extension EnvironmentValues {
    /// Follows the colour scheme unless a host pins a theme explicitly, so every
    /// view that reads it, including the root of a hierarchy, agrees.
    var tunerTheme: TunerTheme {
        get { self[TunerThemeKey.self] ?? TunerTheme(colorScheme: colorScheme) }
        set { self[TunerThemeKey.self] = newValue }
    }
}

public extension View {
    /// Kept for hosts that call it; the theme already follows the colour scheme.
    func tunerThemed() -> some View { self }
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
