import SwiftUI

/// A full-width button row.
public struct ActionRow: View {
    let label: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    public init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(TunerTheme.label)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: TunerTheme.rowHeight)
                .background(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous)
                    .fill(hover ? theme.surfaceHover : theme.surface))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
        .focusEffectDisabled()
    }
}

/// Press feedback for every pressable surface: scales down on mouse-down (not
/// on release, which would feel dead) and settles on a critically damped spring.
/// 0.97 for rows and cards; 0.96 for small icon and text buttons, where the
/// element is small enough that 0.97 reads as nothing.
public struct PressScaleStyle: ButtonStyle {
    let scale: CGFloat
    public init(scale: CGFloat = 0.97) { self.scale = scale }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .tunerMotion(TunerTheme.press, value: configuration.isPressed)
    }
}
