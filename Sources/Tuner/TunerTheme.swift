import SwiftUI

/// The visual system for every Tuner surface. Neutral alphas over a near-black or
/// near-white panel; no accent colour anywhere, so the one inverted element (the
/// Copy button) reads as the primary action. Inspired by Josh Puckett's web
/// tuning panel, rebuilt natively.
public struct TunerTheme {
    public let isDark: Bool

    public init(colorScheme: ColorScheme) { isDark = colorScheme == .dark }

    // Surfaces
    public var panel: Color { isDark ? Color(red: 0.129, green: 0.129, blue: 0.129) : Color(red: 0.98, green: 0.98, blue: 0.98) }
    public var dropdown: Color { isDark ? Color(red: 0.165, green: 0.165, blue: 0.165) : .white }
    public var surface: Color { mono(isDark ? 0.05 : 0.04) }
    public var surfaceHover: Color { mono(isDark ? 0.10 : 0.08) }
    public var surfaceActive: Color { mono(isDark ? 0.11 : 0.10) }
    public var surfaceSubtle: Color { mono(isDark ? 0.06 : 0.06) }
    public var border: Color { mono(isDark ? 0.10 : 0.10) }
    public var borderHover: Color { mono(isDark ? 0.15 : 0.15) }

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
    public var panelGlass: Color { panel.opacity(isDark ? 0.86 : 0.9) }

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
    /// Quiet uppercase section label.
    public static let eyebrow = Font.system(size: 10.5, weight: .semibold)
    public static let eyebrowTracking: CGFloat = 0.6

    // Motion
    public static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)
    public static let quick = Animation.spring(response: 0.2, dampingFraction: 0.9)
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

/// Reduce Motion turns every spring into an instant change.
public extension View {
    func tunerAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReducedMotionAnimation(animation: animation, value: value))
    }
}

private struct ReducedMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let animation: Animation
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduce ? nil : animation, value: value)
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
