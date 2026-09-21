import AppKit
import StayAwake
import SwiftUI
import Tuner

/// The Stay awake page, in two columns with one job each. Left, where the eye lands first:
/// the status. What closing the lid will do and why, the one thing to do about it, the
/// "Keep awake now" dial, what happened last time, and a small preview of the close. Right:
/// the rules. What else keeps the Mac awake, and the settings. (It used to open on a large
/// decorative preview top-left, with the answer on the right and a third of the left empty.)
struct AwakePage: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    static let statusWidth: CGFloat = 320

    var body: some View {
        HStack(spacing: 0) {
            // A battery warning, a running dial, last time and the preview together are taller
            // than the panel. A column that runs long scrolls; it must never push the page out
            // of its frame (it once slid up under the header and down over the footer).
            ScrollView(showsIndicators: false) {
                AwakeStatusColumn(model: model).padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
            }
            .fadesAtTheFold()
            .frame(width: Self.statusWidth)
            Rectangle().fill(theme.hairline).frame(width: 1)
            AwakeControls(model: model)
                .frame(width: PopoverView.width - Self.statusWidth - 1)
        }
        .clipped()
        .overlay {
            if model.showingAwakeConsent {
                AwakeConsent(model: model).transition(.opacity)
            }
        }
        .tunerAnimation(TunerTheme.ease, value: model.showingAwakeConsent)
    }
}

// MARK: - Left: the status

private struct AwakeStatusColumn: View {
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
        VStack(alignment: .leading, spacing: 0) {
            if isOn { hero } else { pitch }

            // The one thing to do here, straight under the answer: keep it awake, for how long.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                KeepAwakeDial(awake: awake, now: context.date)
            }
            .padding(.top, 32)
            .disabled(!isOn)
            .opacity(isOn ? 1 : 0.5)

            if let receipt = awake.journal.last, let slip = AwakeText.slip(receipt) {
                // The same three lines as the slip, in the same order: how long, when, why.
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("Last time").padding(.bottom, 2)
                    Text(slip.headline).font(TunerTheme.heading).tracking(TunerTheme.headingTracking).foregroundStyle(theme.ink)
                    Text(slip.span).font(TunerTheme.bodySmall).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !slip.footnote.isEmpty {
                        Text(slip.footnote).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 32)
                .onAppear { awake.perform(.ok) }
            }

            // A small illustration of the close with its caption. It teaches, so it shows while
            // there is nothing else to look at; once the column is busy with a real hold (the
            // answer, a warning, the dial counting down) it steps aside rather than crowd it.
            if !awake.arbiter.state.holdsLid {
            HStack(alignment: .center, spacing: 14) {
                PreviewWindow(preview: preview, caption: awake.closingCaption(beginning: false)
                              ?? AwakeText.Caption(text: sampleCaption, warning: false, hint: nil), compact: true)
                    .frame(width: 140)
                VStack(alignment: .leading, spacing: 4) {
                    Text(awake.caption == nil ? "What closing looks like when something is working" : "What closing will look like")
                        .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    QuietButton(preview.isPlaying ? "Playing…" : "Play") { preview.playRound() }
                        .padding(.leading, -6)
                }
            }
            .padding(.top, 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Show, don't explain: the close plays once as the page opens.
        .onAppear { if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { preview.playRound() } }
    }

    /// With a question above it, the preview shows what saying yes would look like.
    private var sampleCaption: String { "Staying awake · \(awake.pendingApp?.name ?? "Cursor") is working" }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 12) {
            AwakeEyes(mood: .asleep, pixel: 3, tint: theme.inkLabel).padding(.bottom, 2)
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
                                  limits: arbiter.limits, watchingApps: settings.whenWorking, now: context.date)
            let status = awake.status
            VStack(alignment: .leading, spacing: 14) {
                // The eyes, large and bare: no capsule, no border, no ground, just the face over
                // the answer it illustrates (open: stays awake; shut: the lid sleeps it). Then the
                // answer and why, with the icon of the app it is about beside its sentence.
                AwakeEyes(mood: .init(pending == nil ? status.dot : .idle, isOn: true), pixel: 3,
                          tint: status.dot == .idle || pending != nil ? theme.inkLabel : theme.ink)
                    .padding(.bottom, 2)
                Text(copy.headline)
                    .font(TunerTheme.display(26)).tracking(-0.7).foregroundStyle(theme.ink).lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 8) {
                    if let pending {
                        AppIconView(bundleID: pending.bundleID, size: 20)
                    } else if arbiter.state.holdsLid, arbiter.reasons.count == 1, let reason = arbiter.reasons.first,
                              AppIcons.bundleID(for: reason) != nil {
                        AppIconView(bundleID: AppIcons.bundleID(for: reason), size: 20)
                    }
                    Text(copy.detail)
                        .font(TunerTheme.body).foregroundStyle(theme.inkLabel).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Who is keeping it awake is said once, in the rows under "Stays awake when".
                // A card appears here only to warn.
                if copy.showsCards {
                    AwakeWarnings(state: arbiter.state, conditions: arbiter.conditions, limits: arbiter.limits, now: context.date)
                }
                switch status.action {
                case .allow:
                    HStack(spacing: 10) {
                        PrimaryButton("Allow") { model.performAwake(.allow) }
                        CapsuleButton("Not this app") { model.performAwake(.notThisApp) }
                            .help("Shut will not ask about this app again. You can change it under Options, Something is working.")
                    }
                    .padding(.top, 6)
                case .letItSleep, .undo, .keepAwake:
                    PrimaryButton(status.action!.title) { model.performAwake(status.action!) }.padding(.top, 6)
                default:
                    // Nothing to do about "nothing is working". Keeping the Mac awake by hand is
                    // the "You say so" dial, four rows down, for any length of time.
                    EmptyView()
                }
            }
        }
    }
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
            VStack(alignment: .leading, spacing: 32) {
                triggers
                options
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 20)
            .tunerAnimation(TunerTheme.ease, value: model.showingAwakeSettings)
            .tunerAnimation(TunerTheme.ease, value: showApps)
            .tunerAnimation(TunerTheme.ease, value: showPicker)
        }
        .fadesAtTheFold()
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
            Eyebrow("Keep it awake while").padding(.bottom, 8)
            TriggerRow("An app is busy", about: "Agents, builds, renders.",
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
                        Eyebrow("Settings")
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

/// "Keep awake now": one dial instead of four arbitrary buttons. Off on the left, any time from
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
        VStack(alignment: .leading, spacing: 2) {
            // No tooltip: everything it would say is written under the track.
            StackedSlider("Keep awake now", valueText: AwakeText.manualValue(stop: stop), emphasised: true,
                          value: Binding(get: { dragged ?? Double(awake.manualStop(now: now)) },
                                         set: { dragged = $0; commitSoon() }),
                          in: 0...Double(AwakeText.manualLastStop), step: 1, onEditingEnded: commit)
            // The scale, so nobody has to drag to learn it (as Slow and Fast do for Speed).
            HStack {
                Text("5 min"); Spacer(); Text("12 h · until I stop")
            }
            .font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
            // Its sentence appears when the dial is the thing to do or is in use; while
            // something else is keeping the Mac awake, the dial waits quietly.
            if stop > 0 || !awake.arbiter.state.holdsLid {
                Text(AwakeText.manualCaption(stop: stop, running: dragged == nil && awake.manualHold != nil,
                                             until: awake.manualHold?.until, now: now))
                    .font(TunerTheme.bodySmall)
                    .foregroundStyle(stop > 0 ? theme.ink : theme.inkLabel)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
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
            Eyebrow("Protects your Mac").padding(.bottom, 12)
            Explained("On battery your Mac goes to sleep at this charge, whatever is working.") {
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
    let row: Row
    @Environment(\.tunerTheme) private var theme

    init(_ caption: String, @ViewBuilder row: () -> Row) { self.caption = caption; self.row = row() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            Text(caption).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
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
