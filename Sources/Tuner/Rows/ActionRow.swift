import SwiftUI

/// A full-width button row.
public struct ActionRow: View {
    let label: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false
    @State private var pressed = false

    public init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        Text(label)
            .font(TunerTheme.label)
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: TunerTheme.rowHeight)
            .background(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous)
                .fill(hover ? theme.surfaceHover : theme.surface))
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
            .onKeyPress(.space) { action(); return .handled }
    }
}
