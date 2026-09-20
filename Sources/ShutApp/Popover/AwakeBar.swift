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
            let onPage = model.page == .awake
            HStack(spacing: 10) {
                if onPage {
                    // On the Awake page the bar is the page's header: the way back, and the switch.
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    Text("Styles").font(TunerTheme.body).foregroundStyle(theme.inkLabel)
                    Spacer(minLength: 8)
                    Text("Stay awake").font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
                    SmallPill(isOn: model.stayAwake.settings.isOn && model.stayAwake.settings.hasConsented, size: .regular) { model.toggleAwake() }
                        .help("Keep the Mac awake with the lid shut while something is working.")
                } else {
                    AwakeFace(dot: status.dot, isOn: model.stayAwake.settings.isOn && model.stayAwake.settings.hasConsented)
                    Text("AWAKE").font(TunerTheme.eyebrow).tracking(TunerTheme.eyebrowTracking).foregroundStyle(theme.inkTertiary)
                    if status.action == .allow, let pending = model.stayAwake.pendingApp {
                        AppIconView(bundleID: pending.bundleID, size: 16)
                    } else if status.dot == .holding, model.stayAwake.arbiter.reasons.count == 1, let reason = model.stayAwake.arbiter.reasons.first {
                        AppIconView(bundleID: AppIcons.bundleID(for: reason), size: 16)
                    }
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: Self.height)
            .background(hover ? theme.linen.opacity(0.6) : .clear)
            .contentShape(Rectangle())
            .onTapGesture { model.page = onPage ? .styles : .awake }
            .onHover { hover = $0 }
            .tunerAnimation(TunerTheme.ease, value: hover)
            .tunerAnimation(TunerTheme.ease, value: status)
            .tunerAnimation(TunerTheme.ease, value: onPage)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(onPage ? "Back to styles" : "Stay awake. \(status.sentence)")
            .help(onPage ? "Back to the lid styles." : "What is keeping your Mac awake with the lid shut. Click for details.")
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
