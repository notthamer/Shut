import SwiftUI
import Tuner

/// A numbered section's heading that folds: the eyebrow, a chevron, and, while folded, one
/// line that says what is inside. The Stay awake page's Settings and the Lid sound page's
/// Settings are the same shape, so the shape lives once.
struct FoldedSection: View {
    let title: String
    let number: String?
    let summary: String
    @Binding var isOpen: Bool
    let help: String
    @Environment(\.tunerTheme) private var theme

    init(_ title: String, number: String? = nil, summary: String, isOpen: Binding<Bool>, help: String) {
        self.title = title; self.number = number; self.summary = summary; _isOpen = isOpen; self.help = help
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Eyebrow(title, number: number)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    Spacer()
                }
                if !isOpen {
                    Text(summary).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(help)
        .accessibilityLabel("\(title). \(summary)")
        .accessibilityAddTraits(.isButton)
    }
}
