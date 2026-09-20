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
        HStack(spacing: 0) {
            AwakeStage(model: model)
                .padding(16)
                .frame(width: PopoverView.previewWidth)
                .frame(maxHeight: .infinity, alignment: .top)
            Rectangle().fill(theme.hairline).frame(width: 1)
            AwakeControls(model: model)
                .frame(width: PopoverView.width - PopoverView.previewWidth - 1)
        }
        .overlay {
            if model.showingAwakeConsent {
                AwakeConsent(model: model).transition(.opacity)
            }
        }
        .tunerAnimation(TunerTheme.ease, value: model.showingAwakeConsent)
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
            PreviewWindow(preview: preview, caption: model.stayAwake.closingCaption(beginning: false)
                          ?? AwakeText.Caption(text: sampleCaption, warning: false, hint: nil))
            HStack {
                Text(model.stayAwake.caption == nil ? "What closing looks like when something is working" : "What closing will look like")
                    .foregroundStyle(theme.inkTertiary)
                Spacer()
                Button { preview.playRound() } label: {
                    Text(preview.isPlaying ? "Playing…" : "Play").foregroundStyle(theme.inkLabel).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help("Play the close with its caption.")
            }
            .font(TunerTheme.bodySmall)
            .padding(.top, 14)
            .padding(.horizontal, 2)

            if let receipt = model.stayAwake.journal.last {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Last time")
                    ForEach(AwakeText.receipt(receipt), id: \.self) { line in
                        Text(line).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, TunerTheme.sectionGap)
                .onAppear { model.stayAwake.perform(.ok) }
            }
            Spacer(minLength: 0)
        }
        // Show, don't explain: the close plays once as the page opens.
        .onAppear { if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { preview.playRound() } }
    }

    /// With a question on the right, the stage shows what saying yes would look like.
    private var sampleCaption: String { "Staying awake · \(model.stayAwake.pendingApp?.name ?? "Cursor") is working" }
}

// MARK: - Right: now, reasons, limits

private struct AwakeControls: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme
    @State private var showApps = false
    @State private var showPicker = false

    private var awake: StayAwakeController { model.stayAwake }
    private var settings: StayAwakeSettings { awake.settings }

    private var isOn: Bool { settings.isOn && settings.hasConsented }

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: TunerTheme.sectionGap) {
                if isOn { hero } else { pitch }
                triggers
                options
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 16)
            .tunerAnimation(TunerTheme.ease, value: model.showingAwakeSettings)
            .tunerAnimation(TunerTheme.ease, value: showApps)
            .tunerAnimation(TunerTheme.ease, value: showPicker)
        }
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 12) {
            AwakeFace(dot: .idle, isOn: false, pixel: 2.5).padding(.bottom, 2)
            Text("Keep working\nwith the lid shut.")
                .font(TunerTheme.display(26)).tracking(-0.7).foregroundStyle(theme.ink).lineSpacing(1)
            Text("Shut keeps your Mac awake only while something is working, and lets it sleep by itself when that is done.")
                .font(TunerTheme.body).foregroundStyle(theme.inkLabel).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            // The ellipsis promises a sheet; there is one only the first time.
            PrimaryButton(settings.hasConsented ? "Turn on" : "Turn on…") { model.toggleAwake() }
                .padding(.top, 6)
        }
    }

    /// One headline, one sentence about the lid, one button. Cards only when there
    /// is more than one thing to list, or a warning to show.
    private var hero: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let arbiter = awake.arbiter
            let pending = awake.pendingApp
            let copy = pending.map { AwakeText.pendingHero($0.name) }
                ?? AwakeText.hero(state: arbiter.state, reasons: arbiter.reasons, conditions: arbiter.conditions,
                                  limits: arbiter.limits, now: context.date)
            let status = awake.status
            VStack(alignment: .leading, spacing: 12) {
                // The face first: open eyes, the Mac stays awake; shut, the lid sleeps it.
                // Beside it, who it is staying awake for, when that is one app.
                HStack(spacing: 10) {
                    AwakeFace(dot: pending == nil ? status.dot : .idle, isOn: true, pixel: 2.5)
                    if let pending {
                        AppIconView(bundleID: pending.bundleID, size: 32)
                    } else if arbiter.state.holdsLid, arbiter.reasons.count == 1, let reason = arbiter.reasons.first {
                        AppIconView(bundleID: AppIcons.bundleID(for: reason), size: 32)
                    }
                }
                .padding(.bottom, 2)
                Text(copy.headline)
                    .font(TunerTheme.display(26)).tracking(-0.7).foregroundStyle(theme.ink).lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(copy.detail)
                    .font(TunerTheme.body).foregroundStyle(theme.inkLabel).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                // Who is keeping it awake is said once, in the rows under "Stays awake when".
                // A card appears here only to warn.
                if copy.showsCards {
                    AwakeWarnings(state: arbiter.state, conditions: arbiter.conditions, limits: arbiter.limits, now: context.date)
                }
                switch status.action {
                case .allow:
                    HStack(spacing: 14) {
                        PrimaryButton("Allow") { model.performAwake(.allow) }
                        QuietButton("Not this app") { model.performAwake(.notThisApp) }
                            .help("Shut will not ask about this app again. You can change it under Options, Something is working.")
                    }
                    .padding(.top, 6)
                case .letItSleep, .undo, .keepAwake:
                    PrimaryButton(status.action!.title) { model.performAwake(status.action!) }.padding(.top, 6)
                default:
                    if arbiter.state == .ready {
                        PrimaryButton("Keep awake for an hour") { awake.setManualHold(stop: AwakeText.manualStop(remaining: 3600)) }.padding(.top, 6)
                    }
                }
            }
        }
    }

    /// What keeps the Mac awake, always in view: the page answers "when?" without a
    /// click. Four rows, one line of explanation each; the one at work right now says so
    /// in ink with a Lime dot. Lists of apps stay folded until asked for.
    private var triggers: some View {
        // The running time is part of the line, so it is kept true the same way the hero is.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            triggerRows(now: context.date)
        }
    }

    private func triggerRows(now: Date) -> some View {
        let reasons = awake.arbiter.reasons
        func live(_ kind: HoldReason.Kind) -> String? {
            guard isOn else { return nil }
            return AwakeText.live(reasons.filter { $0.kind == kind }, now: now)
        }
        return VStack(alignment: .leading, spacing: 4) {
            Eyebrow("Stays awake when").padding(.bottom, 6)
            TriggerRow("An app is busy", about: "Agents, builds, renders, downloads.",
                       live: live(.working), detail: allowedSummary, isOn: bind(\.whenWorking), expanded: $showApps,
                       help: "Hold the lid while an app you allow is asking macOS to stay awake: a coding agent in a terminal, a render, a download.")
            if showApps { AllowedApps(model: model).transition(.blurFade).padding(.bottom, 6) }

            TriggerRow("A display is connected", about: "Keep working on an external monitor.",
                       live: live(.display), detail: nil, isOn: bind(\.whenDisplayConnected), expanded: nil,
                       help: "Close the lid and keep working on an external display, even on battery and without a keyboard or mouse attached.")

            TriggerRow("An app is open", about: "While apps you pick are open.",
                       live: live(.appOpen), detail: settings.pickedApps.isEmpty ? "Pick" : (settings.pickedApps.count == 1 ? "1 app" : "\(settings.pickedApps.count) apps"),
                       isOn: bind(\.whenAppsOpen), expanded: $showPicker,
                       help: "Hold the lid for as long as an app you pick is open.")
            if showPicker { AppPicker(model: model).transition(.blurFade).padding(.bottom, 6) }

            KeepAwakeDial(awake: awake, now: now).padding(.top, 4)
        }
        // Readable before the feature is on (it is the explanation), usable once it is.
        .disabled(!isOn)
        .opacity(isOn ? 1 : 0.5)
    }

    /// The rest, folded: what protects the Mac, and the extras. Safe defaults, so they can
    /// stay out of the way; the summary says the two worth knowing without opening it.
    private var options: some View {
        VStack(alignment: .leading, spacing: TunerTheme.sectionGap) {
            Button { model.showingAwakeSettings.toggle() } label: {
                HStack(spacing: 8) {
                    Eyebrow("Settings")
                    Image(systemName: model.showingAwakeSettings ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    Spacer()
                    if !model.showingAwakeSettings {
                        Text(optionsSummary).font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .help("Battery, power and lock limits, and a few extras.")

            if model.showingAwakeSettings { AwakeLimits(model: model).transition(.blurFade) }
        }
    }

    private var optionsSummary: String {
        AwakeText.limitsSummary(batteryFloor: settings.batteryFloor, lockWhenShut: settings.lockWhenShut, chargerOnly: settings.chargerOnly)
    }

    private var allowedSummary: String {
        let count = awake.arbiter.mirror.seenApps.filter(\.allowed).count
        return count == 0 ? "Apps" : (count == 1 ? "1 app" : "\(count) apps")
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<StayAwakeSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

/// "You say so": one dial instead of four arbitrary buttons. Off on the left, any time from
/// five minutes to twelve hours, "until I stop" on the right. The line under it says
/// the choice whole ("Awake until 6:40 PM · 1 h 12 min left"), and while a hold runs the
/// thumb drifts back towards Off, so the dial is also the countdown.
private struct KeepAwakeDial: View {
    @ObservedObject var awake: StayAwakeController
    let now: Date
    /// Where the thumb is while it is being moved; the hold starts when it is let go.
    @State private var dragged: Double?
    @State private var settle: DispatchWorkItem?
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let stop = dragged.map { Int($0.rounded()) } ?? awake.manualStop(now: now)
        VStack(alignment: .leading, spacing: 0) {
            FillSliderRow("You say so",
                          value: Binding(get: { dragged ?? Double(awake.manualStop(now: now)) },
                                         set: { dragged = $0; commitSoon() }),
                          in: 0...Double(AwakeText.manualLastStop), step: 1, decimals: 0,
                          help: "Keep the Mac awake with the lid shut for as long as you choose, whatever is running. All the way right: until you drag it back.",
                          valueText: { AwakeText.manualValue(stop: Int($0.rounded())) },
                          onEditingEnded: commit)
            Text(AwakeText.manualCaption(stop: stop, running: dragged == nil && awake.manualHold != nil,
                                         until: awake.manualHold?.until, now: now))
                .font(TunerTheme.bodySmall)
                .foregroundStyle(stop > 0 ? theme.ink : theme.inkTertiary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commit() {
        settle?.cancel()
        guard let dragged else { return }
        awake.setManualHold(stop: Int(dragged.rounded()))
        self.dragged = nil
    }

    /// The arrow keys move the thumb without a drag ever ending; let go means "a moment of stillness".
    private func commitSoon() {
        settle?.cancel()
        let work = DispatchWorkItem { commit() }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}

/// One trigger: its name, one line about it (or, when it is the one at work, who and
/// "now"), an optional "3 apps ›" disclosure, and its switch.
private struct TriggerRow: View {
    let label: String
    let about: String
    let live: String?
    let detail: String?
    @Binding var isOn: Bool
    let expanded: Binding<Bool>?
    let help: String
    @Environment(\.tunerTheme) private var theme

    init(_ label: String, about: String, live: String?, detail: String?, isOn: Binding<Bool>, expanded: Binding<Bool>?, help: String) {
        self.label = label; self.about = about; self.live = live; self.detail = detail
        _isOn = isOn; self.expanded = expanded; self.help = help
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(TunerTheme.body).foregroundStyle(isOn ? theme.ink : theme.inkLabel).lineLimit(1)
                HStack(spacing: 5) {
                    if live != nil, isOn {
                        Circle().fill(TunerTheme.limeWash).overlay(Circle().strokeBorder(theme.ink, lineWidth: 1))
                            .frame(width: 7, height: 7)
                    }
                    Text(isOn ? (live ?? about) : about)
                        .font(TunerTheme.bodySmall)
                        .foregroundStyle(live != nil && isOn ? theme.ink : theme.inkTertiary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let expanded, let detail {
                QuietButton(expanded.wrappedValue ? "Done" : "\(detail) ›") { expanded.wrappedValue.toggle() }
            }
            SmallPill(isOn: isOn, size: .regular) { isOn.toggle() }
        }
        .padding(.vertical, 5)
        .help(help)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label). \(live ?? about)")
    }
}

// MARK: - Cards

/// The one card the page still has: a Saffron row when a limit is near or has spoken, or
/// a plain one while the Mac winds down. Who is keeping it awake is said in the trigger
/// rows, once.
struct AwakeWarnings: View {
    let state: HoldState
    let conditions: PowerConditions
    let limits: HoldLimits
    let now: Date
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    // A shape to scan by; VoiceOver would read it as "black up-pointing triangle".
                    Text(row.glyph).font(.system(size: 11)).foregroundStyle(row.warning ? theme.ink : theme.inkLabel)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title).font(TunerTheme.bodyMedium).foregroundStyle(theme.ink).lineLimit(1)
                        Text(row.subtitle).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(row.warning ? theme.washSaffron : .clear)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([row.warning ? "Warning." : "", row.title, row.subtitle].filter { !$0.isEmpty }.joined(separator: ", "))
            }
        }
        .surface(.card, radius: TunerTheme.cardRadius)
        .clipShape(RoundedRectangle(cornerRadius: TunerTheme.cardRadius, style: .continuous))
        .tunerAnimation(TunerTheme.ease, value: rows)
    }

    struct Row: Equatable {
        let glyph, title, subtitle: String
        let warning: Bool
    }

    var rows: [Row] {
        switch state {
        case .grace(let until):
            return [Row(glyph: "◆", title: "Finished", subtitle: "sleeping in \(AwakeText.duration(until.timeIntervalSince(now))) unless it starts again", warning: false)]
        case .stopped(let reason) where reason != .userLetItSleep:
            return [Row(glyph: "▲", title: "Not holding the lid", subtitle: AwakeText.stopped(reason, conditions: conditions), warning: true)]
        case .holding:
            if !conditions.onCharger, let percent = conditions.batteryPercent, percent <= limits.batteryFloor + 5 {
                return [Row(glyph: "▲", title: "On battery · \(percent) %", subtitle: "will let the Mac sleep at \(limits.batteryFloor) %", warning: true)]
            }
            return []
        default:
            return []
        }
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
                HStack(spacing: 8) {
                    AppIconView(bundleID: app.bundleID, size: 18)
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
                HStack(spacing: 8) {
                    AppIconView(bundleID: app.id, size: 18)
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

/// The folded part of the page, in two groups and in plain words. Every row says what it
/// does in a line under its name: a tooltip is no place for the only explanation, and
/// "Battery floor" or "⌥ flips the decision" explained nothing by themselves.
struct AwakeLimits: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let settings = model.stayAwake.settings
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow("Protects your Mac").padding(.bottom, 6)
            Explained("On battery your Mac goes to sleep at this charge, whatever is working.") {
                FillSliderRow("Sleep when battery reaches",
                              value: Binding(get: { Double(settings.batteryFloor) }, set: { settings.batteryFloor = Int($0) }),
                              in: Double(HoldLimits.batteryFloorRange.lowerBound)...Double(HoldLimits.batteryFloorRange.upperBound),
                              step: 5, decimals: 0, unit: "%",
                              help: "On battery, at this charge Shut lets your Mac sleep whatever is working.",
                              labelWidth: 170)
            }
            Explained("Charger only: on battery the lid sleeps your Mac, as it always has.") {
                SegmentedRow("Stay awake on", options: ["Any power", "Charger only"],
                             selection: Binding(get: { settings.chargerOnly ? 1 : 0 }, set: { settings.chargerOnly = $0 == 1 }),
                             help: "Charger only: on battery the lid sleeps your Mac as usual.")
            }
            Explained("How long to wait after the work ends, in case it starts again.") {
                SegmentedRow("Then sleep after", options: ["1", "5", "15", "30 min"],
                             selection: Binding(get: { HoldLimits.graceChoices.firstIndex(of: settings.grace) ?? 1 },
                                                set: { settings.grace = HoldLimits.graceChoices[$0] }),
                             help: "How long to wait before letting the Mac sleep, in case the work starts again. An agent between two steps looks finished for a moment.")
            }
            TriggerRow("Lock the screen", about: "A Mac that stays awake stays unlocked. This locks it as the lid shuts.",
                       live: nil, detail: nil, isOn: Binding(get: { settings.lockWhenShut }, set: { settings.lockWhenShut = $0 }), expanded: nil,
                       help: "A Mac that never slept is unlocked for whoever opens it next. On: Shut locks the screen as the lid shuts.")
            TriggerRow("Follow Low Power Mode", about: "While Low Power Mode is on, the lid sleeps your Mac.",
                       live: nil, detail: nil, isOn: Binding(get: { settings.respectLowPowerMode }, set: { settings.respectLowPowerMode = $0 }), expanded: nil,
                       help: "While macOS Low Power Mode is on, the lid sleeps your Mac as usual.")

            Eyebrow("Extras").padding(.top, TunerTheme.sectionGap - 4).padding(.bottom, 6)
            TriggerRow("Tell me what happened", about: "A short note under the menu bar icon when you open the lid again.",
                       live: nil, detail: nil, isOn: Binding(get: { settings.showReceipt }, set: { settings.showReceipt = $0 }), expanded: nil,
                       help: "When you open the lid after your Mac stayed awake, a small note under the menu bar icon says what happened: how long, how it ended, the battery it used. It fades by itself.")
            TriggerRow("Option key changes its mind", about: "Hold ⌥ while closing the lid to do the opposite, just that once.",
                       live: nil, detail: nil, isOn: Binding(get: { settings.optionFlips }, set: { settings.optionFlips = $0 }), expanded: nil,
                       help: "Hold Option as you close the lid to do the opposite this once: sleep although something is working, or stay awake for an hour although nothing is.")
        }
    }

}

/// A slider or a segmented row with its one line of explanation underneath.
private struct Explained<Row: View>: View {
    let caption: String
    let row: Row
    @Environment(\.tunerTheme) private var theme

    init(_ caption: String, @ViewBuilder row: () -> Row) { self.caption = caption; self.row = row() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            Text(caption).font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Consent

/// Shown once, the first time the feature is switched on. Void Black, like the welcome.
private struct AwakeConsent: View {
    @ObservedObject var model: PopoverModel
    /// "Turn on" opens the eyes, and the sheet leaves a moment later: the first thing the
    /// feature ever does is wake up.
    @State private var awake = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func turnOn() {
        guard !awake else { return }
        awake = true
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.55)) {
            model.stayAwake.consent()
            model.showingAwakeConsent = false
        }
    }

    var body: some View {
        ZStack {
            TunerTheme.voidBlack
            VStack(alignment: .leading, spacing: 18) {
                AwakeEyes(mood: awake ? .awake : .asleep, pixel: 3.5, tint: awake ? TunerTheme.limeWash : .white.opacity(0.7))
                    .padding(.bottom, 4)
                    .tunerAnimation(TunerTheme.ease, value: awake)
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
                    Button("Turn on", action: turnOn)
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
