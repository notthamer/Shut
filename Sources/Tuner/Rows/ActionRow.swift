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
                .font(TunerTheme.bodyMedium)
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: TunerTheme.rowHeight)
                .background(Capsule().fill(hover ? theme.linen : theme.card))
                .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.ease, value: hover)
        .focusEffectDisabled()
    }
}
