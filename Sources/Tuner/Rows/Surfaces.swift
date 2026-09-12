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
            .foregroundStyle(theme.textTertiary)
    }
}

/// A raised surface: fill, hairline border, and a one-point light catch along
/// the top edge.
public struct SurfaceModifier: ViewModifier {
    let radius: CGFloat
    let fill: Color?
    @Environment(\.tunerTheme) private var theme
    public func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill ?? theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // Light catch: a short vertical gradient clipped to the shape's top.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [theme.innerHighlight, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 12)
                    .mask(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(lineWidth: 1))
                    .allowsHitTesting(false)
            }
    }
}

public extension View {
    func tunerSurface(radius: CGFloat = TunerTheme.rowRadius, fill: Color? = nil) -> some View {
        modifier(SurfaceModifier(radius: radius, fill: fill))
    }

    /// Replaces the system focus ring with a hairline that only shows for
    /// keyboard focus.
    func tunerFocusRing(_ focused: Bool, radius: CGFloat = TunerTheme.rowRadius) -> some View {
        self
            .focusEffectDisabled()
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(focused ? 0.45 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }
}

/// The one strong call to action on a surface: inverted, like the Copy button.
public struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false
    @State private var pressed = false
    public init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    public var body: some View {
        Text(title)
            .font(TunerTheme.label)
            .foregroundStyle(theme.panel)
            .frame(maxWidth: .infinity)
            .frame(height: TunerTheme.rowHeight)
            .background(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous)
                .fill(theme.textRoot.opacity(hover ? 0.92 : 1)))
            .scaleEffect(pressed ? 0.98 : 1)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false; action() })
            .tunerAnimation(TunerTheme.quick, value: pressed)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.return) { action(); return .handled }
    }
}
