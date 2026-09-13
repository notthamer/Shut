import SwiftUI

/// Quiet uppercase section label ("STYLE", "ADJUST FOLD").
public struct Eyebrow: View {
    let text: String
    @Environment(\.tunerTheme) private var theme
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(TunerTheme.eyebrow)
            .tracking(TunerTheme.eyebrowTracking)
            .foregroundStyle(theme.inkTertiary)
    }
}

/// How a control sits on the glass.
public enum GlassStyle: Equatable {
    /// Stands proud: buttons, cards, menus, folders.
    case raised
    /// Cut in: slider tracks, editors, wells, text fields.
    case inset
    /// Raised, over a colour: slider fills, selection, the permission card.
    case tinted(Color)
}

/// A pane of glass: a translucent white fill, a light catch along the top edge,
/// a dark hairline around, and either a soft drop shadow (raised) or an inner
/// shadow (inset). Everything on a panel is built from this one modifier so the
/// whole app reads as one material.
public struct GlassSurface: ViewModifier {
    let style: GlassStyle
    let radius: CGFloat
    @Environment(\.tunerTheme) private var theme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    private var fill: Color {
        switch style {
        case .raised: return theme.raised
        case .inset: return theme.inset
        case .tinted(let color): return color
        }
    }

    public func body(content: Content) -> some View {
        switch style {
        case .raised, .tinted:
            content
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(theme.glassEdgeDark, lineWidth: 1))
                .overlay(alignment: .top) { lightCatch(height: 12, alpha: 0.85) }
                .shadow(color: theme.shadowSoft, radius: 6, y: 2)
        case .inset:
            content
                .background(shape.fill(fill))
                // Inner shadow: a soft dark band inside the top edge.
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [theme.insetShadow, .clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 3)
                    .allowsHitTesting(false)
                )
                // Light edge along the bottom, where the cut catches the light.
                .overlay(alignment: .bottom) {
                    shape.fill(LinearGradient(colors: [.clear, theme.glassEdgeLight], startPoint: .top, endPoint: .bottom))
                        .frame(height: 10)
                        .mask(shape.strokeBorder(lineWidth: 1))
                        .allowsHitTesting(false)
                }
                .overlay(shape.strokeBorder(theme.glassEdgeDark.opacity(0.8), lineWidth: 1))
        }
    }

    private func lightCatch(height: CGFloat, alpha: Double) -> some View {
        shape.fill(LinearGradient(colors: [Color.white.opacity(alpha), .clear], startPoint: .top, endPoint: .bottom))
            .frame(height: height)
            .mask(shape.strokeBorder(lineWidth: 1))
            .allowsHitTesting(false)
    }
}

public extension View {
    func glassSurface(_ style: GlassStyle = .raised, radius: CGFloat = TunerTheme.rowRadius) -> some View {
        modifier(GlassSurface(style: style, radius: radius))
    }

    /// The older name; a raised pane, or a tinted one when a fill is given.
    func tunerSurface(radius: CGFloat = TunerTheme.rowRadius, fill: Color? = nil) -> some View {
        modifier(GlassSurface(style: fill.map { .tinted($0) } ?? .raised, radius: radius))
    }

    /// Replaces the system focus ring with a hairline that only shows for
    /// keyboard focus.
    func tunerFocusRing(_ focused: Bool, radius: CGFloat = TunerTheme.rowRadius) -> some View {
        self
            .focusEffectDisabled()
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(TunerTheme.inkBase.opacity(focused ? 0.45 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }
}

/// A small glass bead: slider handles, toggle knobs, colour swatches.
public struct GlassBead: View {
    let size: CGFloat
    @Environment(\.tunerTheme) private var theme
    public init(size: CGFloat = 14) { self.size = size }
    public var body: some View {
        Circle()
            .fill(Color.white.opacity(0.92))
            .overlay(Circle().strokeBorder(TunerTheme.inkBase.opacity(0.15), lineWidth: 1))
            .overlay(alignment: .top) {
                Circle().fill(LinearGradient(colors: [Color.white, .clear], startPoint: .top, endPoint: .center))
                    .mask(Circle().strokeBorder(lineWidth: 1.5))
            }
            .shadow(color: theme.shadowContact, radius: 1, y: 1)
            .shadow(color: theme.shadowSoft, radius: 4, y: 2)
            .frame(width: size, height: size)
    }
}

/// A crossfade bridged by a 2-pt blur and a 4-pt rise, so the outgoing and the
/// incoming content read as one thing changing rather than two things
/// overlapping. Under Reduce Motion the rise is dropped and only the fade stays.
struct BlurFade: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 2 : 0)
            .offset(y: active && !reduce ? 4 : 0)
    }
}

public extension AnyTransition {
    static let blurFade = AnyTransition.modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
}

/// The one strong call to action on a surface: an ink pill with a light catch.
public struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false
    public init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(TunerTheme.label)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: TunerTheme.rowHeight)
                .background(Capsule().fill(TunerTheme.inkBase.opacity(hover ? 0.92 : 1)))
                .overlay(alignment: .top) {
                    Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(height: 14)
                        .mask(Capsule().strokeBorder(lineWidth: 1))
                }
                .shadow(color: TunerTheme.inkBase.opacity(0.22), radius: 8, y: 4)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
        .focusEffectDisabled()
    }
}
