import StayAwake
import SwiftUI
import Tuner

/// Under the header: the app's two sections as two equal tabs, and, only when there is
/// something to say, one line of status with its one action.
///
/// It replaces a strip that was a status readout, a navigation link and a button holder at
/// once, and that spent most of its life saying "nothing" in the most prominent place in the
/// panel. Now navigation looks like navigation (tabs, as on any Mac), the eyes in the
/// "Stay awake" tab carry the state at a glance, and words appear when they matter: staying
/// awake, winding down, a limit, a question, an unread receipt.
struct SectionBar: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    static let height: CGFloat = 40

    var body: some View {
        // The sentence can carry a running time ("47 min"); a slow timeline keeps it true
        // while the panel is on screen and costs nothing when it is not.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let status = model.stayAwake.status
            let isOn = model.stayAwake.settings.isOn && model.stayAwake.settings.hasConsented
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    SectionTab(isSelected: model.page == .styles, help: "Ways to close your Mac: the style and how it plays.") {
                        model.page = .styles
                    } label: { Text("Lid effects") }
                    SectionTab(isSelected: model.page == .awake, help: "Keep working with the lid shut: when, and its limits.") {
                        model.page = .awake
                    } label: {
                        HStack(spacing: 7) {
                            AwakeEyes(mood: .init(status.dot, isOn: isOn), pixel: 1.5, tint: eyeTint(status.dot, isOn: isOn))
                            Text("Stay awake")
                        }
                    }
                }
                .padding(2)
                .surface(.pill)

                Spacer(minLength: 8)

                // On the Stay awake tab the page itself says all of this, with the same button.
                if status.speaks, model.page != .awake {
                    HStack(spacing: 10) {
                        StatusSpot(dot: status.dot)
                        Text(status.sentence)
                            .font(TunerTheme.body).foregroundStyle(theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.85).truncationMode(.tail)
                            .id(status.sentence).transition(.opacity)
                            .help(status.sentence)
                        if let action = status.action {
                            CapsuleButton(action.title) { model.performAwake(action) }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: Self.height)
            .tunerAnimation(TunerTheme.ease, value: status)
            .tunerAnimation(TunerTheme.ease, value: model.page)
            .accessibilityElement(children: .contain)
        }
    }

    private func eyeTint(_ dot: AwakeText.Dot, isOn: Bool) -> Color {
        dot == .idle ? theme.inkTertiary : theme.ink
    }
}

/// One of the two tabs: Paper White with a border when chosen, bare Linen otherwise.
private struct SectionTab<Label: View>: View {
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        Button(action: action) {
            label()
                .font(isSelected ? TunerTheme.bodyMedium : TunerTheme.body)
                .foregroundStyle(isSelected ? theme.ink : theme.inkLabel)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background {
                    Capsule().fill(theme.card)
                        .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
                        .opacity(isSelected ? 1 : 0)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .focusEffectDisabled()
        .tunerAnimation(TunerTheme.ease, value: isSelected)
        .help(help)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The colour of the status line: Lime holding, Linen winding down, Saffron for a limit.
private struct StatusSpot: View {
    let dot: AwakeText.Dot
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        Circle().fill(fill).overlay(Circle().strokeBorder(theme.ink.opacity(0.8), lineWidth: 1))
            .frame(width: 8, height: 8)
    }

    private var fill: Color {
        switch dot {
        case .idle: return theme.card
        case .holding: return TunerTheme.limeWash
        case .winding: return theme.linen
        case .warning: return TunerTheme.saffron
        }
    }
}

/// Tier two, under the name the app already used for it. See `PrimaryButton`.
struct CapsuleButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View { SecondaryButton(title, action: action) }
}
