import StayAwake
import SwiftUI
import Tuner

/// One line under the header that is always there: what is keeping the Mac awake,
/// and the one thing to do about it. It sits outside the part of the panel that
/// dims when the lid animation is paused, because staying awake does not depend
/// on the animation. A click anywhere on it opens the Awake page.
struct AwakeBar: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    static let height: CGFloat = 40

    var body: some View {
        // The sentence carries a running time ("47 min"); a slow timeline keeps it true
        // while the panel is on screen and costs nothing when it is not.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let status = model.stayAwake.status
            HStack(spacing: 10) {
                AwakeDot(dot: status.dot)
                Text("AWAKE").font(TunerTheme.eyebrow).tracking(TunerTheme.eyebrowTracking).foregroundStyle(theme.inkTertiary)
                Text(status.sentence)
                    .font(TunerTheme.body)
                    .foregroundStyle(status.dot == .idle ? theme.inkLabel : theme.ink)
                    .lineLimit(1)
                    .id(status.sentence)
                    .transition(.opacity)
                Spacer(minLength: 8)
                if let action = status.action {
                    CapsuleButton(action.title) { model.performAwake(action) }
                }
                Image(systemName: model.page == .awake ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: Self.height)
            .background(hover ? theme.linen.opacity(0.6) : .clear)
            .contentShape(Rectangle())
            .onTapGesture { model.page = model.page == .awake ? .styles : .awake }
            .onHover { hover = $0 }
            .tunerAnimation(TunerTheme.ease, value: hover)
            .tunerAnimation(TunerTheme.ease, value: status)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Stay awake. \(status.sentence)")
            .accessibilityAddTraits(.isButton)
            .help("What is keeping your Mac awake with the lid shut. Click for details.")
        }
    }
}

/// Silver ring: nothing to hold for. Lime: holding. Saffron: a limit is near or has spoken.
struct AwakeDot: View {
    let dot: AwakeText.Dot
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(dot == .idle ? theme.inkTertiary : theme.ink, lineWidth: 1))
            .frame(width: 9, height: 9)
            .tunerAnimation(TunerTheme.ease, value: dot)
    }

    private var fill: Color {
        switch dot {
        case .idle: return .clear
        case .holding: return TunerTheme.limeWash
        case .winding: return theme.linen
        case .warning: return TunerTheme.saffron
        }
    }
}

/// A small bordered capsule: the bar's action, the cards' buttons.
struct CapsuleButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TunerTheme.bodySmall)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 24)
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
