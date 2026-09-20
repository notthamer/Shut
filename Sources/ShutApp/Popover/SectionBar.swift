import StayAwake
import SwiftUI
import Tuner

/// The app's two sections, as two words in the header: "Lid effects" and "Stay awake". No
/// pill, no row of their own. The 2-pt spectrum line that has always run under the header
/// is the indicator: it is drawn under the chosen word, and the rest of the line is a
/// hairline. The eyes sit beside "Stay awake", so its state shows from either section.
struct SectionTabs: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let status = model.stayAwake.status
        let isOn = model.stayAwake.settings.isOn && model.stayAwake.settings.hasConsented
        HStack(spacing: 22) {
            SectionTab(isSelected: model.page == .styles, help: "Ways to close your Mac: the style and how it plays.") {
                model.page = .styles
            } label: { Text("Lid effects") }
            SectionTab(isSelected: model.page == .awake, help: "Keep working with the lid shut: when, and its limits.") {
                model.page = .awake
            } label: {
                HStack(spacing: 7) {
                    Text("Stay awake")
                    AwakeEyes(mood: .init(status.dot, isOn: isOn), pixel: 1.5,
                              tint: status.dot == .idle ? theme.inkTertiary : theme.ink)
                }
            }
        }
        .tunerAnimation(TunerTheme.ease, value: status)
    }
}

/// One word of the two. Ink when chosen, Carbon otherwise; the spectrum under it when chosen.
private struct SectionTab<Label: View>: View {
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            label()
                .font(isSelected ? TunerTheme.bodyMedium : TunerTheme.body)
                .foregroundStyle(isSelected || hover ? theme.ink : theme.inkLabel)
                .lineLimit(1).fixedSize()
                .offset(y: 4)   // onto the baseline of "Shut."
                .frame(height: PopoverHeader.height)
                // The indicator sits exactly where the header's bottom line runs.
                .overlay(alignment: .bottom) {
                    LinearGradient(gradient: TunerTheme.spectrum, startPoint: .leading, endPoint: .trailing)
                        .frame(height: 2)
                        .opacity(isSelected ? 1 : 0)
                        .offset(y: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .focusEffectDisabled()
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.ease, value: isSelected)
        .tunerAnimation(TunerTheme.ease, value: hover)
        .help(help)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A row that exists only when there is something to say. On the right, what Stay awake is
/// doing and its one action (staying awake, winding down, a limit, a question, an unread
/// receipt); on the left, on the Lid effects side, why the lid effects are not simply
/// running (paused, no sensor, lid shut on an external display). Silence otherwise: the
/// panel gives the row's height back to the page.
struct StatusLine: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    static let height: CGFloat = 40

    /// Whether the row is there at all.
    static func shows(_ model: PopoverModel) -> Bool {
        guard model.page == .styles else { return false }   // the Stay awake page says it itself
        return (model.stayAwake.hasLid && model.stayAwake.status.speaks) || model.lidEffectsNote != nil
    }

    var body: some View {
        // The sentence can carry a running time ("47 min"); a slow timeline keeps it true
        // while the panel is on screen and costs nothing when it is not.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let status = model.stayAwake.status
            HStack(spacing: 10) {
                if let note = model.lidEffectsNote {
                    Text(note).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineLimit(1)
                }
                Spacer(minLength: 8)
                if model.stayAwake.hasLid, status.speaks {
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
            }
            .padding(.horizontal, 16)
            .frame(height: Self.height)
            .tunerAnimation(TunerTheme.ease, value: status)
            .accessibilityElement(children: .contain)
        }
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
