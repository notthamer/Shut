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
                .background(Capsule().fill(hover ? theme.raisedHover : .clear))
                .glassSurface(.raised, radius: TunerTheme.rowHeight / 2)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
        .focusEffectDisabled()
    }
}
