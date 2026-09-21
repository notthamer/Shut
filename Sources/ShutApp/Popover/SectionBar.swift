import StayAwake
import SwiftUI
import Tuner

/// The app's two sections, in the header, as two tabs that each carry their own state:
///
///     ▭ Lid effects        ◉◉ Stay awake
///     Fold · On            Claude Code · 47 min
///
/// A name alone read as a subtitle of "Shut.", not as somewhere to go. An icon, a second
/// line that changes, a filled ground under the chosen one and the spectrum line beneath it
/// say "tab" the way tabs do everywhere; and because each says what it is doing, the state of
/// Stay awake shows from the Lid effects side with no status row of its own.
struct SectionTabs: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        // The second line can carry a running time ("47 min"); a slow timeline keeps it true
        // while the panel is on screen and costs nothing when it is not.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let awake = model.stayAwake
            let status = awake.status
            let isOn = awake.settings.isOn && awake.settings.hasConsented
            HStack(spacing: 6) {
                SectionTab(title: "Lid effects", line: model.lidEffectsLine, isSelected: model.page == .styles,
                           help: "Ways to close your Mac: the style and how it plays.") {
                    model.page = .styles
                } icon: {
                    Image(systemName: "laptopcomputer").font(.system(size: 12, weight: .medium))
                }
                SectionTab(title: "Stay awake",
                           line: AwakeText.tabLine(state: awake.arbiter.state, reasons: awake.arbiter.reasons,
                                                   conditions: awake.arbiter.conditions, limits: awake.arbiter.limits,
                                                   pendingApp: awake.pendingApp?.name, now: context.date),
                           isSelected: model.page == .awake, emphasised: status.dot != .idle || awake.pendingApp != nil,
                           help: "Keep working with the lid shut: when, and its limits.") {
                    model.page = .awake
                } icon: {
                    AwakeEyes(mood: .init(status.dot, isOn: isOn, lidSleeps: status.lidSleeps), pixel: 1.25,
                              tint: status.dot == .idle ? theme.inkLabel : theme.ink)
                }
            }
            .tunerAnimation(TunerTheme.ease, value: status)
        }
    }
}

/// One tab: icon and name, its state under them. Chosen: a Linen ground and the spectrum.
private struct SectionTab<Icon: View>: View {
    let title: String
    let line: String
    let isSelected: Bool
    var emphasised = false
    let help: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    icon().frame(width: 20, height: 15)
                    Text(title).font(isSelected ? TunerTheme.bodyMedium : TunerTheme.body)
                }
                .foregroundStyle(isSelected || hover ? theme.ink : theme.inkLabel)
                // In ink when it has news (keeping the Mac awake, a limit), Carbon otherwise.
                Text(line).font(TunerTheme.bodySmall)
                    .foregroundStyle(emphasised ? theme.ink : theme.inkLabel)
                    .lineLimit(1).truncationMode(.tail)
                    .id(line).transition(.opacity)
            }
            .frame(maxWidth: 168, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.linen).opacity(isSelected ? 1 : (hover ? 0.6 : 0)))
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
        .tunerAnimation(TunerTheme.ease, value: line)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(line)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}

/// Tier two, under the name the app already used for it. See `PrimaryButton`.
struct CapsuleButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View { SecondaryButton(title, action: action) }
}
