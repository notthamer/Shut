import AppKit
import StayAwake
import SwiftUI
import Tuner

/// The Stay awake page reads in one order, top to bottom:
///
///     ◉◉  Closing the lid will sleep your Mac.        Keep awake now        Off
///         Nothing is keeping it awake right now.      ●━━━━━━━━━━━━━━━━━━━━━━━
///     ─────────────────────────────────────────────────────────────────────────
///     01 KEEP IT AWAKE WHILE                 02 SETTINGS
///     An app is busy          1 app ›  ◉     Sleeps at 30 % battery · locks …
///     ─────────────────────────────────────────────────────────────────────────
///     03 LAST TIME   Slept after <1 min · 2:15 → 2:16 AM …
///
/// The answer spans the panel, because it is the one thing the page is for, with the eyes
/// beside it and the one thing to do about it (the dial) on its right. Under it, the rules in
/// two numbered sections like the Lid effects page. History is a strip at the bottom, in
/// small type: it used to be a second large headline competing with the first. (Before this
/// the page was split 50/50 by a full-height rule, with nothing dominant and the lower third
/// of a too-tall panel empty.)
struct AwakePage: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    /// The left column under the band. (The right one holds Settings, whose segmented rows
    /// cannot shrink; a test measures them against what is left.)
    static let statusWidth: CGFloat = 320
    var body: some View {
        VStack(spacing: 0) {
            AwakeBand(model: model)
            Rectangle().fill(theme.hairline).frame(height: 1)
            AwakeControls(model: model)
            AwakeLastTime(model: model)
        }
        .clipped()
        // The page opening (from the menu bar or the Dock window) is the one moment the
        // battery level is started from the charge.
        .onAppear { model.stayAwake.startTheBatteryLevelFromTheChargeOnce() }
        .overlay {
            if model.showingAwakeConsent {
                AwakeConsent(model: model).transition(.opacity)
            }
        }
        .tunerAnimation(TunerTheme.ease, value: model.showingAwakeConsent)
    }
}

/// History, quietly: one strip at the foot of the page, in the slip's order (how long, when,
/// why) and in small type.
private struct AwakeLastTime: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        if let receipt = model.stayAwake.journal.last, let slip = AwakeText.slip(receipt) {
            VStack(spacing: 0) {
                Rectangle().fill(theme.hairline).frame(height: 1)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Eyebrow("Last time", number: "03").fixedSize()
                    (Text(slip.headline).foregroundStyle(theme.ink).font(TunerTheme.bodyMedium)
                     + Text("  ·  \(slip.span)" + (slip.footnote.isEmpty ? "" : "  ·  \(slip.footnote)")).foregroundStyle(theme.inkLabel))
                        .font(TunerTheme.bodySmall).lineSpacing(2)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(slip.cutShort ? theme.washSaffron.opacity(0.5) : .clear)
            }
            .onAppear { model.stayAwake.perform(.ok) }
        }
    }
}

// MARK: - Left: the status

private struct AwakeBand: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var preview: PreviewModel
    @Environment(\.tunerTheme) private var theme

    init(model: PopoverModel) {
        self.model = model
        preview = model.preview
    }

    private var awake: StayAwakeController { model.stayAwake }
    private var settings: StayAwakeSettings { awake.settings }
    private var isOn: Bool { settings.isOn && settings.hasConsented }

    var body: some View {
        // Two cells with the page's vertical rule between them, as tall as the taller one, so
        // the rule runs unbroken from the header down to "Last time".
        HStack(alignment: .top, spacing: 0) {
            // Top left, where the eye lands: the face, and under it what it is saying.
            VStack(alignment: .leading, spacing: 14) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    let dot = awake.pendingApp == nil ? awake.status.dot : .idle
                    AwakeEyes(mood: isOn ? .init(dot, isOn: true, lidSleeps: awake.status.lidSleeps) : .asleep, pixel: 3,
                              tint: !isOn || dot == .idle ? theme.inkLabel : theme.ink, dreams: true)
                }
                if isOn { hero } else { pitch }
            }
            .padding(.horizontal, 20).padding(.vertical, 22)
            .frame(width: AwakePage.statusWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Rectangle().fill(theme.hairline).frame(width: 1)

            // Top right: the one thing to do about it, and, only while closing the lid will keep
            // the Mac awake, what that will look like.
            VStack(alignment: .leading, spacing: 18) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    KeepAwakeMode(awake: awake, now: context.date)
                }
                .disabled(!isOn)
                .opacity(isOn ? 1 : 0.5)
                if isOn, awake.arbiter.state.holdsLid, let caption = awake.closingCaption(beginning: false) {
                    HStack(alignment: .center, spacing: 12) {
                        PreviewWindow(preview: preview, caption: caption, compact: true).frame(width: 120)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("What closing will look like").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                                .fixedSize(horizontal: false, vertical: true)
                            QuietButton(preview.isPlaying ? "Playing…" : "Play") { preview.playRound() }.padding(.leading, -6)
                        }
                    }
                    // Show, don't explain: it plays once as it appears.
                    .onAppear { if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { preview.playRound() } }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 22)
            .frame(width: PopoverView.width - AwakePage.statusWidth - 1, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The action under the answer shows where it leads before it is pressed. Keeping the Mac
    /// awake is Lime with open eyes; letting it sleep is an outline with shut eyes, because a
    /// working Mac going to sleep is the user's call and never the thing Shut pushes. Under
    /// the button, one line says what pressing it will do.
    @ViewBuilder
    private func actions(_ action: AwakeText.Action?, who: String?) -> some View {
        if let action, action != .turnOn, action != .ok {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    outcomeButton(action)
                    if action == .allow {
                        outcomeButton(.notThisApp)
                            .help("Shut will not ask about this app again. You can change it under “An app is busy”.")
                    }
                }
                if let consequence = action.consequence(who: who) {
                    Text(consequence).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func outcomeButton(_ action: AwakeText.Action) -> some View {
        switch action.outcome {
        case .staysAwake:
            PrimaryButton(action.title, tone: .lime) { model.performAwake(action) } icon: {
                AwakeEyes(mood: .awake, pixel: 1, tint: theme.ink, animated: false)
            }
        case .sleeps:
            SecondaryButton(action.title, prominent: action == .letItSleep) { model.performAwake(action) } icon: {
                AwakeEyes(mood: .shut, pixel: 1, tint: theme.ink, animated: false)
            }
        case .neutral:
            PrimaryButton(action.title) { model.performAwake(action) }
        }
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep working with the lid shut.")
                .font(TunerTheme.display(24)).tracking(-0.6).foregroundStyle(theme.ink).lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
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
                                  limits: arbiter.limits, watchingApps: settings.whenWorking, now: context.date)
            let status = awake.status
            VStack(alignment: .leading, spacing: 14) {
                // The eyes are beside this block, in the band. Here: the answer and why, with the icon
                // of the app it is about beside its sentence.
                Text(copy.headline)
                    .font(TunerTheme.display(24)).tracking(-0.6).foregroundStyle(theme.ink).lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 8) {
                    if let pending {
                        AppIconView(bundleID: pending.bundleID, size: 20)
                    }
                    Text(copy.detail)
                        .font(TunerTheme.body).foregroundStyle(theme.inkLabel).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Who is keeping it awake is said once, in the rows under "Stays awake when".
                // A card appears here only to warn.
                if copy.showsCards {
                    AwakeWarnings(state: arbiter.state, conditions: arbiter.conditions, limits: arbiter.limits, now: context.date,
                                  changeLevel: model.showingAwakeSettings ? nil : { model.showingAwakeSettings = true })
                }
                actions(status.action, who: pending?.name
                        ?? arbiter.reasons.first { $0.kind == .working || $0.kind == .command }.map(AwakeText.subject))
            }
        }
    }
}

// MARK: - Right: now, reasons, limits

private struct AwakeControls: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme
    @State private var showPicker = false

    private var awake: StayAwakeController { model.stayAwake }
    private var settings: StayAwakeSettings { awake.settings }

    private var isOn: Bool { settings.isOn && settings.hasConsented }

    var body: some View {
        // "01" on the left, "02" on the right, the page's vertical rule between them (as on the
        // Lid effects page). Each cell scrolls by itself and fills what the panel has left.
        HStack(alignment: .top, spacing: 0) {
            ScrollView(showsIndicators: true) {
                triggers.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fadesAtTheFold()
            .frame(width: AwakePage.statusWidth)
            Rectangle().fill(theme.hairline).frame(width: 1)
            ScrollView(showsIndicators: true) {
                options.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fadesAtTheFold()
            .frame(width: PopoverView.width - AwakePage.statusWidth - 1)
        }
        .frame(maxHeight: .infinity)
        .tunerAnimation(TunerTheme.ease, value: model.showingAwakeSettings)
        .tunerAnimation(TunerTheme.ease, value: model.showingAllowedApps)
        .tunerAnimation(TunerTheme.ease, value: showPicker)
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
            // Without a set time running, the box at the top names who; the row marks the rule.
            let boxed = model.stayAwake.arbiter.state.holdsLid && !reasons.contains { $0.kind == .manual }
            return AwakeText.live(reasons.filter { $0.kind == kind }, named: !boxed, now: now)
        }
        return VStack(alignment: .leading, spacing: 4) {
            Eyebrow("Keep it awake while", number: "01").padding(.bottom, 8)
            TriggerRow("An app is busy", about: "Only while it is working: agents, builds, renders.",
                       live: live(.working), detail: allowedSummary, isOn: bind(\.whenWorking), expanded: $model.showingAllowedApps,
                       help: "Hold the lid while an app you allow is asking macOS to stay awake: a coding agent in a terminal, a render, a download.")
            if model.showingAllowedApps { AllowedApps(model: model).transition(.blurFade).padding(.bottom, 6) }

            TriggerRow("A display is connected", about: "Keep working on an external monitor.",
                       live: live(.display), detail: nil, isOn: bind(\.whenDisplayConnected), expanded: nil,
                       help: "Close the lid and keep working on an external display, even on battery and without a keyboard or mouse attached.")

            TriggerRow("An app is open", about: "The whole time apps you pick are open, busy or not.",
                       live: live(.appOpen), detail: settings.pickedApps.isEmpty ? "Pick" : (settings.pickedApps.count == 1 ? "1 app" : "\(settings.pickedApps.count) apps"),
                       isOn: bind(\.whenAppsOpen), expanded: $showPicker,
                       help: "Hold the lid for as long as an app you pick is open.")
            if showPicker { AppPicker(model: model).transition(.blurFade).padding(.bottom, 6) }

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
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Eyebrow("Settings", number: "02")
                        Image(systemName: model.showingAwakeSettings ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                        Spacer()
                    }
                    if !model.showingAwakeSettings {
                        Text(optionsSummary).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                            .fixedSize(horizontal: false, vertical: true)
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

/// A slider for a narrow column: its name and value share a line, and the track gets the
/// whole width under them. (A row with the label beside the track left "Sleep when battery
/// reaches" a track 30 pt long.)
struct StackedSlider: View {
    let title: String
    let valueText: String
    var emphasised = false
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var onEditingEnded: (() -> Void)? = nil
    @Environment(\.tunerTheme) private var theme

    init(_ title: String, valueText: String, emphasised: Bool = false, value: Binding<Double>,
         in range: ClosedRange<Double>, step: Double, onEditingEnded: (() -> Void)? = nil) {
        self.title = title; self.valueText = valueText; self.emphasised = emphasised
        _value = value; self.range = range; self.step = step; self.onEditingEnded = onEditingEnded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(emphasised ? TunerTheme.bodyMedium : TunerTheme.body)
                    .foregroundStyle(emphasised ? theme.ink : theme.inkLabel)
                Spacer()
                Text(valueText).font(TunerTheme.value).foregroundStyle(theme.ink)
            }
            FillSliderRow(title, value: $value, in: range, step: step, decimals: 0,
                          showsValue: false, height: 28, labelWidth: 0, onEditingEnded: onEditingEnded)
                .padding(.leading, -12)   // the row keeps a gap for a label it does not show here
        }
    }
}

/// The two ways to stay awake, side by side, so going from one to the other is one click
/// either way. "Automatically": the rules under "Keep it awake while" decide. "For a set
/// time": awake whatever is running, for the time on the dial, then automatic again by
/// itself. Choosing "For a set time" starts the last time used at once; the dial changes it.
private struct KeepAwakeMode: View {
    @ObservedObject var awake: StayAwakeController
    let now: Date
    /// Where the thumb is while it is being moved; the hold starts when it is let go.
    @State private var dragged: Double?
    @State private var settle: DispatchWorkItem?
    @Environment(\.tunerTheme) private var theme

    private var settings: StayAwakeSettings { awake.settings }
    private var timed: Bool { awake.manualHold != nil || dragged != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep it awake").font(TunerTheme.bodyMedium).foregroundStyle(theme.ink)
            ModeSwitch(options: ["Automatically", "For a set time"], selection: timed ? 1 : 0) { index in
                settle?.cancel(); dragged = nil
                if index == 1 { awake.startTimedHold() } else { awake.returnToAutomatic() }
            }
            if timed { dial } else if !holders.isEmpty { holding } else {
                Text(AwakeText.automaticSummary(working: settings.whenWorking, display: settings.whenDisplayConnected,
                                                pickedApps: settings.whenAppsOpen ? settings.pickedApps.count : 0))
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tunerAnimation(TunerTheme.ease, value: timed)
    }

    /// What the rules have found, while they are the ones keeping the Mac awake.
    private var holders: [HoldReason] {
        awake.arbiter.state.holdsLid ? awake.arbiter.reasons.filter { $0.kind != .manual } : []
    }

    /// Automatic, and at work: who is keeping it awake right now, in the same box as the choice.
    private var holding: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keeping it awake now").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            ForEach(Array(holders.prefix(AwakeText.holdersShown).enumerated()), id: \.element.id) { _, reason in
                let line = AwakeText.holder(reason, now: now)
                HStack(spacing: 8) {
                    if let bundleID = AppIcons.bundleID(for: reason) {
                        AppIconView(bundleID: bundleID, size: 18)
                    } else {
                        Circle().fill(theme.ink).frame(width: 6, height: 6).frame(width: 18, height: 18)
                    }
                    Text(line.name).font(TunerTheme.bodyMedium).foregroundStyle(theme.ink).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(line.detail).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineLimit(1).fixedSize()
                }
                .padding(.horizontal, 12).frame(height: 30)
                .accessibilityElement(children: .combine)
            }
            if let more = AwakeText.moreHolders(holders.count) {
                Text(more).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                    .padding(.horizontal, 12).padding(.bottom, 4)
            }
            Spacer(minLength: 0).frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(.card, radius: TunerTheme.cardRadius)
    }

    private var dial: some View {
        let stop = max(dragged.map { Int($0.rounded()) } ?? awake.manualStop(now: now), 1)
        return VStack(alignment: .leading, spacing: 2) {
            StackedSlider("How long", valueText: AwakeText.manualValue(stop: stop),
                          value: Binding(get: { dragged ?? Double(max(awake.manualStop(now: now), 1)) },
                                         set: { dragged = $0; commitSoon() }),
                          in: 1...Double(AwakeText.manualLastStop), step: 1, onEditingEnded: commit)
            // The scale, so nobody has to drag to learn it (as Slow and Fast do for Speed).
            HStack {
                Text("5 min"); Spacer(); Text("12 h · until I stop")
            }
            .font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
            // A limit that forbids staying awake wins over the timer, and the line says so
            // instead of promising a time.
            if case .stopped(let reason) = awake.arbiter.state, reason != .userLetItSleep {
                Text(AwakeText.manualBlocked(reason))
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            } else {
                Text(AwakeText.manualCaption(stop: stop, running: dragged == nil && awake.manualHold != nil,
                                             until: awake.manualHold?.until, now: now))
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }

    private func commit() {
        settle?.cancel()
        guard let dragged else { return }
        awake.setManualHold(stop: max(Int(dragged.rounded()), 1))
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

/// Two equal halves filling the width: a choice between two ways, not a setting with a label.
/// Same pill and capsule as `SegmentedRow`.
struct ModeSwitch: View {
    let options: [String]
    let selection: Int
    let choose: (Int) -> Void
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, name in
                Button { if index != selection { choose(index) } } label: {
                    Text(name)
                        .font(index == selection ? TunerTheme.bodyMedium : TunerTheme.body)
                        .foregroundStyle(index == selection ? theme.ink : theme.inkLabel)
                        .lineLimit(1).minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background {
                            Capsule().fill(theme.card)
                                .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
                                .opacity(index == selection ? 1 : 0)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .surface(.pill)
        .tunerAnimation(TunerTheme.ease, value: selection)
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
                    // Carbon, not Slate: this line carries meaning, and Slate on the paper is 3:1.
                    Text(isOn ? (live ?? about) : about)
                        .font(TunerTheme.bodySmall)
                        .foregroundStyle(live != nil && isOn ? theme.ink : theme.inkLabel)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // The whole row opens its list, not only the small word at its end.
            .onTapGesture { expanded?.wrappedValue.toggle() }
            if let expanded, let detail {
                QuietButton(expanded.wrappedValue ? "Done" : detail, disclosure: !expanded.wrappedValue) { expanded.wrappedValue.toggle() }
            }
            SmallPill(isOn: isOn, size: .regular) { isOn.toggle() }
        }
        .padding(.vertical, 9)
        // No tooltip: the line under the name says it. (`help` stays for VoiceOver.)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label). \(live ?? about)")
        .accessibilityHint(help)
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
    /// Opens Settings at the battery level; nil while Settings is already open.
    var changeLevel: (() -> Void)? = nil
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
                        // With a meter, its two labels carry the numbers; the sentence stays for VoiceOver.
                        if row.meter == nil {
                            Text(row.subtitle).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let meter = row.meter {
                            BatteryMeter(percent: meter.percent, floor: meter.floor).padding(.top, 6)
                            // The level is the user's own: a way straight to it, unless it is already showing.
                            if let changeLevel {
                                SecondaryButton(AwakeText.BatteryTooLow.changeLevel, action: changeLevel).padding(.top, 8)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(row.warning ? theme.washSaffron : .clear)
                .accessibilityElement(children: row.meter == nil ? .ignore : .contain)
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
        var meter: AwakeText.BatteryTooLow? = nil
    }

    var rows: [Row] {
        // Under the battery level: the one fact, with both numbers and where they sit.
        if state == .ready || state == .stopped(.batteryFloor),
           let low = AwakeText.batteryTooLow(conditions: conditions, limits: limits) {
            return [Row(glyph: "▲", title: low.title, subtitle: low.rule, warning: true, meter: low)]
        }
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

/// Where the battery is against the level it must be above: a bar filled to now, a tick at
/// the level. Two numbers are easier to compare as two places on one line.
struct BatteryMeter: View {
    let percent: Int
    let floor: Int
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.ink.opacity(0.12))
                    Capsule().fill(theme.ink).frame(width: max(4, width * CGFloat(percent) / 100))
                    Rectangle().fill(theme.ink).frame(width: 1.5, height: 10)
                        .offset(x: width * CGFloat(floor) / 100)
                }
            }
            .frame(height: 4).padding(.vertical, 3)
            HStack {
                Text("now \(percent) %"); Spacer(); Text("needs more than \(floor) %")
            }
            .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Disclosures

/// A list of apps with a switch each, in a well that never outgrows the page. It shows six
/// and a half rows (the half says "there is more") and scrolls inside itself beyond that;
/// past eight apps it grows a filter. Unbounded, seven apps already pushed the rows below
/// it off the page, and a list of thirty would have been the page.
private struct AppList: View {
    struct Item: Identifiable { let id: String; let name: String; let isOn: Bool; var note: String? = nil }

    let intro: String
    let empty: String
    let items: [Item]
    let toggle: (Item) -> Void
    @State private var filter = ""
    @Environment(\.tunerTheme) private var theme

    static let rowHeight: CGFloat = 34
    static let visibleRows: CGFloat = 6.5
    static let filterFrom = 9

    private var shown: [Item] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(intro)
                .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
            if items.count >= Self.filterFrom {
                Rectangle().fill(theme.hairline).frame(height: 1)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .medium)).foregroundStyle(theme.inkTertiary)
                    TextField("Filter \(items.count) apps", text: $filter)
                        .textFieldStyle(.plain).font(TunerTheme.bodySmall)
                }
                .padding(.horizontal, 12).frame(height: 30)
            }
            if items.isEmpty {
                Rectangle().fill(theme.hairline).frame(height: 1)
                Text(empty).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).padding(12)
            } else if shown.isEmpty {
                Rectangle().fill(theme.hairline).frame(height: 1)
                Text("No app called “\(filter)”.").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).padding(12)
            }
            let rows = VStack(spacing: 0) {
                ForEach(shown) { item in
                    Rectangle().fill(theme.hairline).frame(height: 1)
                    HStack(spacing: 8) {
                        AppIconView(bundleID: item.id, size: 18)
                        Text(item.name).font(TunerTheme.body).foregroundStyle(theme.ink).lineLimit(1)
                        if let note = item.note {
                            Text(note).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineLimit(1)
                        }
                        Spacer()
                        SmallPill(isOn: item.isOn) { toggle(item) }
                    }
                    .padding(.horizontal, 12).frame(height: Self.rowHeight - 1)
                }
            }
            if CGFloat(shown.count) > Self.visibleRows {
                ScrollView(showsIndicators: true) { rows }
                    .frame(height: Self.rowHeight * Self.visibleRows)
            } else {
                rows
            }
        }
        .surface(.well, radius: TunerTheme.wellRadius)
        .clipShape(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous))
    }
}

/// Apps Shut has seen asking macOS to stay awake. New tools appear here by themselves, so
/// there is no list of agents to keep up to date. Asking now first, then the ones switched on.
private struct AllowedApps: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        let mirror = model.stayAwake.arbiter.mirror
        AppList(intro: "Apps that asked macOS to stay awake. Switch on the ones that may keep your Mac awake.",
                empty: "None yet. They appear here by themselves.",
                items: mirror.orderedApps.map {
                    .init(id: $0.bundleID, name: $0.name, isOn: $0.allowed,
                          note: mirror.askingNow.contains($0.bundleID) ? "asking now" : nil)
                }) { item in
            mirror.setAllowed(item.id, !item.isOn)
            model.objectWillChange.send()
        }
    }
}

/// Regular apps that are open now, plus any already picked. Picked first.
private struct AppPicker: View {
    @ObservedObject var model: PopoverModel

    private var items: [AppList.Item] {
        let picked = model.stayAwake.settings.pickedApps
        var seen = Set<String>()
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> AppList.Item? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                  seen.insert(id).inserted else { return nil }
            return .init(id: id, name: app.localizedName ?? id, isOn: picked.contains(id))
        }
        let closed = picked.filter { seen.insert($0).inserted }.map { id in
            AppList.Item(id: id, name: NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?
                .deletingPathExtension().lastPathComponent ?? id, isOn: true, note: "not open")
        }
        return (running + closed).sorted {
            $0.isOn != $1.isOn ? $0.isOn : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        let settings = model.stayAwake.settings
        AppList(intro: "Open apps. Switch on the ones your Mac should stay awake for.",
                empty: "No apps are open.", items: items) { item in
            if let index = settings.pickedApps.firstIndex(of: item.id) { settings.pickedApps.remove(at: index) }
            else { settings.pickedApps.append(item.id) }
        }
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
            Eyebrow("Protects your Mac").padding(.bottom, 12)
            Explained(AwakeText.batteryTooLow(conditions: model.stayAwake.arbiter.conditions, limits: model.stayAwake.arbiter.limits)?.setting
                      ?? AwakeText.batteryNow(model.stayAwake.arbiter.conditions),   // where the charge is against the level
                      link: model.stayAwake.levelFromTheCharge.map { level in
                          (AwakeText.useLevel(level), { model.stayAwake.setTheBatteryLevelFromTheCharge() })
                      }) {
                StackedSlider("Sleep when battery reaches", valueText: "\(settings.batteryFloor) %",
                              value: Binding(get: { Double(settings.batteryFloor) }, set: { settings.batteryFloor = Int($0) }),
                              in: Double(HoldLimits.batteryFloorRange.lowerBound)...Double(HoldLimits.batteryFloorRange.upperBound),
                              step: 5)
            }
            Explained("Stay awake on any power, or only on the charger.") { Self.powerRow(settings) }
            Explained("Minutes to wait after the work ends, in case it starts again.") { Self.graceRow(settings) }
            TriggerRow("Lock the screen", about: "A Mac that stays awake stays unlocked. This locks it as the lid shuts.",
                       live: nil, detail: nil, isOn: Binding(get: { settings.lockWhenShut }, set: { settings.lockWhenShut = $0 }), expanded: nil,
                       help: "A Mac that never slept is unlocked for whoever opens it next. On: Shut locks the screen as the lid shuts.")
            TriggerRow("Follow Low Power Mode", about: "While Low Power Mode is on, the lid sleeps your Mac.",
                       live: nil, detail: nil, isOn: Binding(get: { settings.respectLowPowerMode }, set: { settings.respectLowPowerMode = $0 }), expanded: nil,
                       help: "While macOS Low Power Mode is on, the lid sleeps your Mac as usual.")

            Eyebrow("Extras").padding(.top, 28).padding(.bottom, 12)
            // No switch for the Option key: a gesture nobody makes by accident needs no way to
            // be turned off, only a way to be found. The caption teaches it, and so does this.
            Text("Hold ⌥ while closing the lid to do the opposite, just that once.")
                .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
            TriggerRow("Tell me what happened", about: "A short note under the menu bar icon when you open the lid again.",
                       live: nil, detail: nil, isOn: Binding(get: { settings.showReceipt }, set: { settings.showReceipt = $0 }), expanded: nil,
                       help: "When you open the lid after your Mac stayed awake, a small note under the menu bar icon says what happened: how long, how it ended, the battery it used. It fades by itself.")
        }
    }


    // The two segmented rows cannot shrink (their words never become "…"), so they are built
    // here where a test can measure them against the column they have to fit.
    static func powerRow(_ settings: StayAwakeSettings) -> SegmentedRow {
        SegmentedRow("Power", options: ["Any", "Charger only"],
                     selection: Binding(get: { settings.chargerOnly ? 1 : 0 }, set: { settings.chargerOnly = $0 == 1 }))
    }

    static func graceRow(_ settings: StayAwakeSettings) -> SegmentedRow {
        SegmentedRow("Sleep after", options: ["1", "5", "15", "30 min"],
                     selection: Binding(get: { HoldLimits.graceChoices.firstIndex(of: settings.grace) ?? 1 },
                                        set: { settings.grace = HoldLimits.graceChoices[$0] }))
    }
}

/// A slider or a segmented row with its one line of explanation underneath.
private struct Explained<Row: View>: View {
    let caption: String
    /// One quiet thing to do about the caption, at its end ("Use 60 %").
    let link: (title: String, action: () -> Void)?
    let row: Row
    @Environment(\.tunerTheme) private var theme

    init(_ caption: String, link: (title: String, action: () -> Void)? = nil, @ViewBuilder row: () -> Row) {
        self.caption = caption; self.link = link; self.row = row()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if !caption.isEmpty {
                Text(caption).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if let link {
                // Right under a caption in the same small type, a plain quiet link would read as
                // more caption: ink and an underline say it can be pressed.
                Button(action: link.action) {
                    Text(link.title).font(TunerTheme.bodySmall).underline().foregroundStyle(theme.ink)
                        .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.bottom, 20)
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
                AwakeEyes(mood: awake ? .awake : .asleep, pixel: 3.5, tint: awake ? TunerTheme.limeWash : .white.opacity(0.7), dreams: true)
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
