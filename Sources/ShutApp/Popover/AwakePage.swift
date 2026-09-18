import AppKit
import StayAwake
import SwiftUI
import Tuner

/// The Awake page: the stage on the left shows the close as it will look, caption
/// included; the right says what is keeping the Mac awake now, and holds the few
/// switches. Same size as the Styles page, so the panel never resizes.
struct AwakePage: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            AwakePageHead(model: model)
            Rectangle().fill(theme.hairline).frame(height: 1)
            HStack(spacing: 0) {
                AwakeStage(model: model)
                    .padding(16)
                    .frame(width: PopoverView.previewWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(theme.hairline).frame(width: 1)
                AwakeControls(model: model)
                    .frame(width: PopoverView.width - PopoverView.previewWidth - 1)
            }
        }
        .overlay {
            if model.showingAwakeConsent {
                AwakeConsent(model: model).transition(.opacity)
            }
        }
        .tunerAnimation(TunerTheme.ease, value: model.showingAwakeConsent)
    }
}

private struct AwakePageHead: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let settings = model.stayAwake.settings
        ZStack {
            Eyebrow("Stay awake")
            HStack {
                QuietButton("‹ Styles") { model.page = .styles }
                    .help("Back to the lid styles.")
                Spacer()
                SmallPill(isOn: settings.isOn && settings.hasConsented, size: .regular) { model.toggleAwake() }
                    .help(settings.isOn ? "Stop keeping the Mac awake with the lid shut." : "Keep the Mac awake with the lid shut while something is working.")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}

// MARK: - Left: the stage

private struct AwakeStage: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var preview: PreviewModel
    @Environment(\.tunerTheme) private var theme

    init(model: PopoverModel) {
        self.model = model
        preview = model.preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("How the close will look").padding(.bottom, 10)
            PreviewWindow(preview: preview, caption: model.stayAwake.caption ?? sampleCaption)
            VStack(spacing: 4) {
                FillSliderRow("Lid", value: $preview.progress, in: 0...1, step: 0.005, decimals: 2,
                              help: "Drag to move the lid by hand.", showsValue: false, height: 28, labelWidth: 36)
                HStack {
                    Text("Open")
                    Spacer()
                    Button { preview.playRound() } label: {
                        Text(preview.isPlaying ? "Playing…" : "Play").foregroundStyle(theme.inkLabel).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .help("Play the close with its caption.")
                    Spacer()
                    Text("Shut")
                }
                .font(TunerTheme.bodySmall)
                .foregroundStyle(theme.inkTertiary)
                .padding(.horizontal, 2)
            }
            .padding(.top, 16)

            Text(model.stayAwake.caption == nil
                 ? "An example. With nothing working there is no caption, and the lid sleeps your Mac as it always has."
                 : "As the lid comes down, the screen tells you what will happen.")
                .font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Spacer(minLength: 0)
        }
    }

    private var sampleCaption: String { "Staying awake · Cursor is working" }
}

// MARK: - Right: now, reasons, limits

private struct AwakeControls: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme
    @State private var showApps = false
    @State private var showPicker = false
    @State private var showLimits = false

    private var awake: StayAwakeController { model.stayAwake }
    private var settings: StayAwakeSettings { awake.settings }

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: TunerTheme.sectionGap) {
                if settings.isOn && settings.hasConsented { nowSection } else { pitch }
                reasonsSection
                limitsSection
            }
            .padding(16)
            .tunerAnimation(TunerTheme.ease, value: showApps)
            .tunerAnimation(TunerTheme.ease, value: showPicker)
            .tunerAnimation(TunerTheme.ease, value: showLimits)
        }
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep working with the lid shut.")
                .font(TunerTheme.heading).tracking(TunerTheme.headingTracking).foregroundStyle(theme.ink)
            Text("Shut holds your Mac awake only while something is working, a display is connected, or you say so. When that ends, your Mac goes to sleep by itself.")
                .font(TunerTheme.body).foregroundStyle(theme.inkLabel).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton("Turn on…") { model.toggleAwake() }
                .padding(.top, 4)
        }
    }

    private var nowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Now")
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let arbiter = awake.arbiter
                VStack(alignment: .leading, spacing: 10) {
                    AwakeCards(state: arbiter.state, reasons: arbiter.reasons, conditions: arbiter.conditions,
                               limits: arbiter.limits, now: context.date)
                    Text(AwakeText.ending(reasons: arbiter.reasons, conditions: arbiter.conditions, limits: arbiter.limits))
                        .font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
                }
            }
        }
    }

    private var reasonsSection: some View {
        VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
            Eyebrow("Stay awake when").padding(.bottom, 2)

            ReasonRow("Something is working", detail: allowedSummary, isOn: bind(\.whenWorking), expanded: $showApps,
                      help: "Hold the lid while an app you allow is asking macOS to stay awake: a coding agent in a terminal, a render, a download.")
            if showApps { AllowedApps(model: model).transition(.blurFade) }

            ReasonRow("A display is connected", detail: nil, isOn: bind(\.whenDisplayConnected), expanded: nil,
                      help: "Close the lid and keep working on an external display, even on battery and without a keyboard or mouse attached.")

            ReasonRow("These apps are open", detail: settings.pickedApps.isEmpty ? "none" : "\(settings.pickedApps.count)",
                      isOn: bind(\.whenAppsOpen), expanded: $showPicker,
                      help: "Hold the lid for as long as an app you pick is open.")
            if showPicker { AppPicker(model: model).transition(.blurFade) }

            SegmentedRow("I say so", options: ["Off", "1 h", "4 h", "∞"],
                         selection: Binding(get: { awake.manualChoice.rawValue },
                                            set: { awake.setManualHold(StayAwakeController.ManualChoice(rawValue: $0) ?? .off) }),
                         help: "Keep the Mac awake with the lid shut for an hour, four hours, or until you switch this off.")
                .disabled(!(settings.isOn && settings.hasConsented))
                .opacity(settings.isOn && settings.hasConsented ? 1 : 0.45)
        }
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
            HStack {
                Eyebrow("Limits")
                Spacer()
                QuietButton(showLimits ? "Done" : "Change…") { showLimits.toggle() }
            }
            .padding(.bottom, 2)
            if showLimits {
                AwakeLimits(model: model).transition(.blurFade)
            } else {
                Text(limitsSummary)
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var allowedSummary: String {
        let count = awake.arbiter.mirror.seenApps.filter(\.allowed).count
        return count == 1 ? "1 app" : "\(count) apps"
    }

    private var limitsSummary: String {
        var parts = ["Lets your Mac sleep at \(settings.batteryFloor) % battery, when it gets hot, and after 8 hours on battery."]
        if settings.chargerOnly { parts.append("Holds on the charger only.") }
        parts.append(settings.lockWhenShut ? "Locks when the lid shuts." : "Does not lock when the lid shuts.")
        return parts.joined(separator: " ")
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<StayAwakeSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

/// One reason: a label, an optional "3 apps ›" disclosure, and its switch.
private struct ReasonRow: View {
    let label: String
    let detail: String?
    @Binding var isOn: Bool
    let expanded: Binding<Bool>?
    let help: String
    @Environment(\.tunerTheme) private var theme

    init(_ label: String, detail: String?, isOn: Binding<Bool>, expanded: Binding<Bool>?, help: String) {
        self.label = label; self.detail = detail; _isOn = isOn; self.expanded = expanded; self.help = help
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(TunerTheme.body).foregroundStyle(theme.inkLabel).lineLimit(1)
            Spacer(minLength: 4)
            if let expanded, let detail {
                QuietButton(expanded.wrappedValue ? "Done" : "\(detail) ›") { expanded.wrappedValue.toggle() }
            }
            SmallPill(isOn: isOn, size: .regular) { isOn.toggle() }
        }
        .frame(height: TunerTheme.rowHeight)
        .help(help)
    }
}

// MARK: - Cards

/// One bordered block, a row per thing keeping the Mac awake.
struct AwakeCards: View {
    let state: HoldState
    let reasons: [HoldReason]
    let conditions: PowerConditions
    let limits: HoldLimits
    let now: Date
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                Text("Nothing is keeping your Mac awake.")
                    .font(TunerTheme.body).foregroundStyle(theme.inkLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.glyph).font(.system(size: 11)).foregroundStyle(row.warning ? theme.ink : theme.inkLabel)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title).font(TunerTheme.bodyMedium).foregroundStyle(theme.ink).lineLimit(1)
                        Text(row.subtitle).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(row.trailing).font(TunerTheme.value).foregroundStyle(theme.inkTertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(row.warning ? theme.washSaffron : .clear)
            }
        }
        .surface(.card, radius: TunerTheme.cardRadius)
        .clipShape(RoundedRectangle(cornerRadius: TunerTheme.cardRadius, style: .continuous))
        .tunerAnimation(TunerTheme.ease, value: rows)
    }

    struct Row: Equatable { let glyph, title, subtitle, trailing: String; let warning: Bool }

    var rows: [Row] {
        var result: [Row] = reasons.map { reason in
            switch reason.kind {
            case .working:
                return Row(glyph: "◆", title: reason.title, subtitle: reason.detail.map { "working · \($0)" } ?? "working",
                           trailing: AwakeText.duration(now.timeIntervalSince(reason.since)), warning: false)
            case .display:
                return Row(glyph: "▭", title: reason.title, subtitle: "while it is plugged in",
                           trailing: "since \(AwakeText.clock(reason.since))", warning: false)
            case .appOpen:
                return Row(glyph: "▣", title: reason.title, subtitle: "while it is open", trailing: "", warning: false)
            case .command:
                return Row(glyph: "›", title: reason.title, subtitle: "running from the command line",
                           trailing: AwakeText.duration(now.timeIntervalSince(reason.since)), warning: false)
            case .manual:
                return Row(glyph: "◇", title: "Kept awake by you",
                           subtitle: reason.until.map { "\(AwakeText.duration($0.timeIntervalSince(now))) left" } ?? "until you stop it",
                           trailing: reason.until.map { "until \(AwakeText.clock($0))" } ?? "", warning: false)
            }
        }
        switch state {
        case .grace(let until):
            result.append(Row(glyph: "◆", title: "Finished", subtitle: "sleeping in \(AwakeText.duration(until.timeIntervalSince(now))) unless it starts again",
                              trailing: "", warning: false))
        case .stopped(let reason) where reason != .userLetItSleep:
            result.append(Row(glyph: "▲", title: "Not holding the lid", subtitle: AwakeText.stopped(reason, conditions: conditions),
                              trailing: "", warning: true))
        case .holding:
            if !conditions.onCharger, let percent = conditions.batteryPercent, percent <= limits.batteryFloor + 5 {
                result.append(Row(glyph: "▲", title: "On battery · \(percent) %", subtitle: "will let the Mac sleep at \(limits.batteryFloor) %",
                                  trailing: "", warning: true))
            }
        default: break
        }
        return result
    }
}

// MARK: - Disclosures

/// Apps Shut has seen asking macOS to stay awake. New tools appear here by
/// themselves, so there is no list of agents to keep up to date.
private struct AllowedApps: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let mirror = model.stayAwake.arbiter.mirror
        VStack(alignment: .leading, spacing: 0) {
            Text("Apps that asked macOS to stay awake. Switch on the ones that may hold the lid.")
                .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
            if mirror.seenApps.isEmpty {
                Rectangle().fill(theme.hairline).frame(height: 1)
                Text("None yet. They appear here by themselves.")
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary).padding(12)
            }
            ForEach(mirror.seenApps) { app in
                Rectangle().fill(theme.hairline).frame(height: 1)
                HStack {
                    Text(app.name).font(TunerTheme.body).foregroundStyle(theme.ink).lineLimit(1)
                    Spacer()
                    SmallPill(isOn: app.allowed) { mirror.setAllowed(app.bundleID, !app.allowed); model.objectWillChange.send() }
                }
                .padding(.horizontal, 12).frame(height: 34)
            }
        }
        .surface(.well, radius: TunerTheme.wellRadius)
    }
}

/// Regular apps that are open now, plus any already picked.
private struct AppPicker: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    private struct Candidate: Identifiable { let id: String; let name: String }

    private var candidates: [Candidate] {
        var seen = Set<String>()
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> Candidate? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                  seen.insert(id).inserted else { return nil }
            return Candidate(id: id, name: app.localizedName ?? id)
        }
        let picked = model.stayAwake.settings.pickedApps.filter { seen.insert($0).inserted }.map { id in
            Candidate(id: id, name: NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?
                .deletingPathExtension().lastPathComponent ?? id)
        }
        return (running + picked).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let settings = model.stayAwake.settings
        VStack(alignment: .leading, spacing: 0) {
            Text("Open apps. Switch on the ones your Mac should stay awake for.")
                .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).padding(12)
            ForEach(candidates) { app in
                Rectangle().fill(theme.hairline).frame(height: 1)
                HStack {
                    Text(app.name).font(TunerTheme.body).foregroundStyle(theme.ink).lineLimit(1)
                    Spacer()
                    SmallPill(isOn: settings.pickedApps.contains(app.id)) {
                        if let index = settings.pickedApps.firstIndex(of: app.id) { settings.pickedApps.remove(at: index) }
                        else { settings.pickedApps.append(app.id) }
                    }
                }
                .padding(.horizontal, 12).frame(height: 34)
            }
        }
        .surface(.well, radius: TunerTheme.wellRadius)
    }
}

private struct AwakeLimits: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        let settings = model.stayAwake.settings
        VStack(spacing: TunerTheme.rowGap) {
            SegmentedRow("Power", options: ["Any", "Charger only"],
                         selection: Binding(get: { settings.chargerOnly ? 1 : 0 }, set: { settings.chargerOnly = $0 == 1 }),
                         help: "Charger only: on battery the lid sleeps your Mac as usual.")
            SegmentedRow("After work stops", options: ["1", "5", "15", "30 min"],
                         selection: Binding(get: { HoldLimits.graceChoices.firstIndex(of: settings.grace) ?? 1 },
                                            set: { settings.grace = HoldLimits.graceChoices[$0] }),
                         help: "How long to wait before letting the Mac sleep, in case the work starts again. An agent between two steps looks finished for a moment.")
            FillSliderRow("Battery floor",
                          value: Binding(get: { Double(settings.batteryFloor) }, set: { settings.batteryFloor = Int($0) }),
                          in: Double(HoldLimits.batteryFloorRange.lowerBound)...Double(HoldLimits.batteryFloorRange.upperBound),
                          step: 5, decimals: 0, unit: " %",
                          help: "On battery, at this charge Shut lets your Mac sleep whatever is working.")
            ToggleRow("Lock when shut", isOn: Binding(get: { settings.lockWhenShut }, set: { settings.lockWhenShut = $0 }),
                      help: "A Mac that never slept is unlocked for whoever opens it next. On: Shut locks the screen as the lid shuts.")
            ToggleRow("Pause in Low Power Mode", isOn: Binding(get: { settings.respectLowPowerMode }, set: { settings.respectLowPowerMode = $0 }),
                      help: "While macOS Low Power Mode is on, the lid sleeps your Mac as usual.")
            ToggleRow("⌥ flips the decision", isOn: Binding(get: { settings.optionFlips }, set: { settings.optionFlips = $0 }),
                      help: "Hold Option as you close the lid to do the opposite this once: sleep although something is working, or stay awake for an hour although nothing is.")
        }
    }
}

// MARK: - Consent

/// Shown once, the first time the feature is switched on. Void Black, like the welcome.
private struct AwakeConsent: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        ZStack {
            TunerTheme.voidBlack
            VStack(alignment: .leading, spacing: 18) {
                Text("Your Mac will stay awake\nwith the lid shut.")
                    .font(TunerTheme.display(30)).tracking(-0.8).foregroundStyle(.white).lineSpacing(2)
                Text("Only while something is working, a display is connected, or you say so. It goes to sleep by itself when that ends, at \(model.stayAwake.settings.batteryFloor) % battery, or if it gets hot.")
                    .font(TunerTheme.font(14)).foregroundStyle(.white.opacity(0.78)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Do not put a working Mac in a bag.")
                    .font(TunerTheme.font(14, weight: .medium)).foregroundStyle(TunerTheme.saffron)
                HStack(spacing: 10) {
                    Spacer()
                    Button("Not now") { model.showingAwakeConsent = false }
                        .buttonStyle(ConsentButtonStyle(filled: false))
                    Button("Turn on") { model.stayAwake.consent(); model.showingAwakeConsent = false }
                        .buttonStyle(ConsentButtonStyle(filled: true))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 420)
            .padding(32)
        }
    }
}

private struct ConsentButtonStyle: ButtonStyle {
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TunerTheme.bodyMedium)
            .foregroundStyle(filled ? Color.black : .white)
            .padding(.horizontal, 20).frame(height: TunerTheme.rowHeight)
            .background(Capsule().fill(filled ? Color.white : .clear))
            .overlay(Capsule().strokeBorder(.white.opacity(filled ? 0 : 0.5), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}
