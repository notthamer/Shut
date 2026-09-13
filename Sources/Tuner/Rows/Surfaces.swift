import SwiftUI

/// Chapter-marker label: mono, uppercase, wide tracking, with an optional
/// number ("01 STYLE").
public struct Eyebrow: View {
    let text: String
    let number: String?
    @Environment(\.tunerTheme) private var theme
    public init(_ text: String, number: String? = nil) { self.text = text; self.number = number }
    public var body: some View {
        HStack(spacing: 8) {
            if let number {
                Text(number).font(TunerTheme.eyebrow).tracking(TunerTheme.eyebrowTracking).foregroundStyle(theme.inkLabel)
            }
            Text(text.uppercased())
                .font(TunerTheme.eyebrow)
                .tracking(TunerTheme.eyebrowTracking)
                .foregroundStyle(theme.inkTertiary)
        }
    }
}

/// How an element sits on the paper. Borders are the depth cue; nothing inside
/// a panel casts a shadow.
public enum SurfaceStyle: Equatable {
    /// Paper White with a one-point border: cards, the primary button, menus.
    case card
    /// Linen, full radius: tags, segment tracks, switch tracks.
    case pill
    /// Linen with a one-point border: slider tracks, plots, the preview frame.
    case well
    /// A wash (Lime, Saffron) with a one-point border: selection, highlight zones.
    case wash(Color)
}

/// Older names, mapped onto the surface styles.
public enum GlassStyle: Equatable {
    case raised
    case inset
    case tinted(Color)

    var surface: SurfaceStyle {
        switch self {
        case .raised: return .card
        case .inset: return .well
        case .tinted(let color): return .wash(color)
        }
    }
}

public struct Surface: ViewModifier {
    let style: SurfaceStyle
    let radius: CGFloat
    @Environment(\.tunerTheme) private var theme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style == .pill ? TunerTheme.fullRadius : radius, style: .continuous)
    }

    private var fill: Color {
        switch style {
        case .card: return theme.card
        case .pill, .well: return theme.linen
        case .wash(let color): return color
        }
    }

    public func body(content: Content) -> some View {
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(theme.border, lineWidth: style == .pill ? 0 : 1).allowsHitTesting(false))
    }
}

public extension View {
    func surface(_ style: SurfaceStyle, radius: CGFloat = TunerTheme.cardRadius) -> some View {
        modifier(Surface(style: style, radius: radius))
    }

    /// Older name.
    func glassSurface(_ style: GlassStyle = .raised, radius: CGFloat = TunerTheme.rowRadius) -> some View {
        modifier(Surface(style: style.surface, radius: radius))
    }

    /// Older name; a card, or a wash when a fill is given.
    func tunerSurface(radius: CGFloat = TunerTheme.rowRadius, fill: Color? = nil) -> some View {
        modifier(Surface(style: fill.map { .wash($0) } ?? .card, radius: radius))
    }

    /// Replaces the system focus ring with a one-point ink line that only shows
    /// for keyboard focus.
    func tunerFocusRing(_ focused: Bool, radius: CGFloat = TunerTheme.rowRadius) -> some View {
        self
            .focusEffectDisabled()
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(TunerTheme.pureBlack.opacity(focused ? 1 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }
}

/// The knob on a slider or switch: an ink disc with a paper ring.
public struct Knob: View {
    let size: CGFloat
    var fill: Color = TunerTheme.pureBlack
    public init(size: CGFloat = 16, fill: Color = TunerTheme.pureBlack) { self.size = size; self.fill = fill }
    public var body: some View {
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(TunerTheme.paperWhite, lineWidth: 2))
            .overlay(Circle().strokeBorder(TunerTheme.silver, lineWidth: 0.5))
            .frame(width: size, height: size)
    }
}

/// Older names for the knob.
public struct GlassBead: View {
    let size: CGFloat
    public init(size: CGFloat = 14) { self.size = size }
    public var body: some View { Knob(size: size) }
}

public struct ChromeKnob: View {
    let size: CGFloat
    public init(size: CGFloat = 24) { self.size = size }
    public var body: some View { Knob(size: size) }
}

/// The spectrum marquee as a thin line: the one place the gradient appears.
/// It drifts slowly along its length; under Reduce Motion it is still.
public struct SpectrumLine: View {
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var phase: CGFloat = 0
    public init(height: CGFloat = 2) { self.height = height }
    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                LinearGradient(gradient: TunerTheme.spectrum, startPoint: .leading, endPoint: .trailing).frame(width: w)
                LinearGradient(gradient: TunerTheme.spectrum, startPoint: .trailing, endPoint: .leading).frame(width: w)
                LinearGradient(gradient: TunerTheme.spectrum, startPoint: .leading, endPoint: .trailing).frame(width: w)
            }
            .offset(x: -w * 2 * phase)
            .onAppear {
                guard !reduce else { return }
                withAnimation(.linear(duration: 24 * TunerTheme.motionScale).repeatForever(autoreverses: false)) { phase = 1 }
            }
        }
        .frame(height: height)
        .clipped()
        .allowsHitTesting(false)
    }
}

/// A crossfade bridged by a 2-pt blur, so the outgoing and the incoming content
/// read as one thing changing rather than two things overlapping. Nothing moves.
struct BlurFade: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 2 : 0)
    }
}

public extension AnyTransition {
    static let blurFade = AnyTransition.modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
}

/// Press feedback that changes colour, not size: the label dims while pressed.
public struct PressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .tunerAnimation(TunerTheme.ease, value: configuration.isPressed)
    }
}

/// Older name; the scale is ignored, nothing scales.
public struct PressScaleStyle: ButtonStyle {
    public let scale: CGFloat
    public init(scale: CGFloat = 0.97) { self.scale = scale }
    public func makeBody(configuration: Configuration) -> some View {
        PressStyle().makeBody(configuration: configuration)
    }
}

/// The primary action: Paper White, a one-point ink border, ink text, full
/// radius. Hover fills with Linen. Never a coloured button.
public struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false
    public init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(TunerTheme.bodyMedium)
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: TunerTheme.rowHeight)
                .background(Capsule().fill(hover ? theme.linen : theme.card))
                .overlay(Capsule().strokeBorder(theme.borderStrong, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.ease, value: hover)
        .focusEffectDisabled()
    }
}
