import SwiftUI

/// Tier two at full width, for a row of equals (Copy · Export · Import). See `PrimaryButton`.
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
                .font(TunerTheme.bodySmall)
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Capsule().fill(hover ? theme.linen : theme.card))
                .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
                .contentShape(Capsule())
                .contentShape(.focusEffect, Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.ease, value: hover)
    }
}
