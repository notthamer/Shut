import AppKit
import Combine
import LidSensor
import StayAwake

/// The app's side of Stay awake: joins the settings, the arbiter and the lid, and
/// is what the popover, the menu and the closing caption read.
///
/// What the lid does while the Mac is held (measured, macOS 26.5): no sleep and no
/// screen-sleep notification arrive, the overlay simply rests on its last frame,
/// and reopening plays the style backwards. So the lid logic in `AppController`
/// needs only two things from here: to be told when the lid starts to close (a
/// fresh reading of who is working) and when it shut on a locked session (so the
/// opening animation waits for the unlock, as it does after a real sleep).
@MainActor
public final class StayAwakeController: ObservableObject {
    public let settings: StayAwakeSettings
    public let arbiter: HoldArbiter

    /// The lid shut while held and the screen was locked: `AppController` holds a
    /// black overlay until the unlock, then plays the opening.
    var onLockedWhileShut: (() -> Void)?

    let journal: HoldJournal
    private let commands = CommandHold()
    private var lastLidWasOpen: Bool?
    /// The lid opened on a receipt nobody has read yet: the moment for the slip.
    var onReturn: ((HoldReceipt) -> Void)?
    /// What Option did to this one close, so a second press can take it back.
    private enum Flip { case toSleep, toAwake }
    private var flip: Flip?
    private var lidEdges: LidStateProvider?
    private var sessionActive = true
    private var cancellables = Set<AnyCancellable>()

    /// A Mac mini, an iMac, a Studio: no lid to hold. The feature is not offered and never
    /// arms there (their monitor would otherwise count as "a display is connected").
    let hasLid: Bool

    /// False in tests: they shut and open the lid themselves, and the real one (which may be
    /// shut, on a docked Mac) must not get a word in. It once did, and the journey tests passed
    /// or failed by whether the laptop running them was open.
    private let listensToTheRealLid: Bool

    public init(settings: StayAwakeSettings? = nil, arbiter: HoldArbiter? = nil, hasLid: Bool = LidStateProvider.isAvailable(),
                listensToTheRealLid: Bool = true) {
        self.hasLid = hasLid
        self.listensToTheRealLid = listensToTheRealLid
        self.settings = settings ?? StayAwakeSettings()
        journal = HoldJournal(defaults: settings == nil ? .standard : UserDefaults(suiteName: "StayAwakeJournal-\(UUID().uuidString)") ?? .standard)
        self.arbiter = arbiter ?? HoldArbiter(hold: LidHold(guardExecutable: Bundle.main.executableURL,
                                                            log: { Log.awake.error("\($0, privacy: .public)") }))
    }

    func start() {
        if arbiter.recoverFromLastRun() {
            Log.awake.notice("the last run ended while holding the lid; lid sleep restored")
        }
        arbiter.onTransition = { [weak self] from, to, reasons in
            if let self, self.arbiter.lidClosed { self.journal.holdChanged(to: to) }
            // notice, not info: info lines are gone from the log within minutes, and "why did
            // it sleep last night" is asked the next morning.
            Log.awake.notice("hold \(String(describing: from), privacy: .public) -> \(String(describing: to), privacy: .public), reasons: \(reasons.map(\.id).joined(separator: ", "), privacy: .public)")
        }
        arbiter.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        settings.objectWillChange
            .receive(on: DispatchQueue.main)   // after the new values are in place
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)

        // Another user taking over the screen is not someone to hold the lid for.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionActive = false; self?.applySettings() }
        }
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.macWillSleep() }
        }
        workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionActive = true; self?.applySettings() }
        }

        // `shut hold` on the command line. The socket exists only while the feature is on.
        commands.statusLine = { [weak self] in self?.status.sentence ?? "" }
        arbiter.add(commands)

        applySettings()
        arbiter.start()
    }

    /// Quit, relaunch for an update, handover to a newer copy: leave the lid as we found it.
    func shutDown() {
        lidEdges?.stop()
        arbiter.shutDown()
    }

    private func applySettings() {
        var limits = settings.limits
        if !sessionActive || !hasLid { limits.isOn = false }
        // Which reasons count comes first: switching the feature on starts every
        // enabled source, and a source the user switched off must never get a look.
        arbiter.setEnabled(.working, settings.whenWorking)
        arbiter.setEnabled(.display, settings.whenDisplayConnected)
        arbiter.setEnabled(.appOpen, settings.whenAppsOpen)
        arbiter.apps.bundleIDs = Set(settings.pickedApps)
        arbiter.limits = limits
        watchLidEdges(limits.isOn)
        objectWillChange.send()
    }

    /// The lid switch, as an event. Only listened to while the feature is on.
    private func watchLidEdges(_ on: Bool) {
        if on, lidEdges == nil, listensToTheRealLid {
            let provider = LidStateProvider()
            let started = provider.start { [weak self] isOpen in
                DispatchQueue.main.async { self?.lidEdge(isOpen: isOpen) }
            }
            lidEdges = started ? provider : nil
        } else if !on, let provider = lidEdges {
            provider.stop()
            lidEdges = nil
            arbiter.lidChanged(closed: false)
        }
    }

    /// Internal, with the time as a parameter, so the journey tests can shut and open the lid.
    func lidEdge(isOpen: Bool, now: Date = Date()) {
        // macOS has been seen to deliver the same edge twice, 8 ms apart.
        guard isOpen != lastLidWasOpen else { return }
        lastLidWasOpen = isOpen
        arbiter.refreshPower()
        arbiter.lidChanged(closed: !isOpen)
        let battery = arbiter.conditions.batteryPercent
        Log.awake.notice("lid \(isOpen ? "opened" : "shut", privacy: .public): \(String(describing: self.arbiter.state), privacy: .public), battery \(battery ?? -1) %")
        if isOpen {
            journal.lidOpened(battery: battery, now: now)
            // Option flipped this one close to "sleep"; the next close decides afresh.
            if flip == .toSleep { arbiter.undoLetItSleep() }
            flip = nil
            // Handed to the slip as it is now: the Awake page, if it happens to be open, marks
            // a receipt read the moment it draws it, and that must not swallow the slip.
            if let receipt = journal.last, !receipt.read, receipt.openedAt.map({ now.timeIntervalSince($0) < 5 }) == true {
                onReturn?(receipt)
            }
            objectWillChange.send()
        } else {
            journal.lidShut(holding: arbiter.state.holdsLid, reasons: arbiter.reasons, battery: battery, now: now)
        }
        guard !isOpen, arbiter.state.holdsLid, settings.lockWhenShut else { return }
        ScreenLock.lock { [weak self] locked in
            if locked { self?.onLockedWhileShut?() }
        }
    }

    // MARK: For the lid

    /// From `AppController`, as the lid starts to come down.
    func lidStartedClosing() {
        if arbiter.limits.isOn {
            arbiter.lidIsClosing()
        } else {
            // Off: one look at what is working, so that if the Mac now sleeps on it
            // the feature can be offered from a real moment rather than a settings hunt.
            let work = arbiter.mirror.refresh().first { $0.viaCommandLine || $0.app.isDeveloperTool }
            journal.lidClosingWhileOff(workingApp: work?.app.name)
        }
    }

    /// From `AppController`, as the overlay is about to appear. Holding Option flips
    /// the decision for this one close; the caption then says which way it went.
    func closeBeginning() {
        flip = nil
        if NSEvent.modifierFlags.contains(.option) { flipDecision() }
    }

    /// Option went down, at the start of a close or during it. The first press flips the
    /// decision for this one close, a second takes it back. True when something changed,
    /// so the caption on screen can be set again.
    @discardableResult
    func flipDecision() -> Bool {
        guard arbiter.limits.isOn else { return false }
        switch flip {
        case nil:
            if arbiter.state.holdsLid { flip = .toSleep; arbiter.letItSleep() }
            else { flip = .toAwake; arbiter.manual.begin(for: 3600) }
        case .toSleep:
            flip = nil
            arbiter.undoLetItSleep()
        case .toAwake:
            flip = nil
            arbiter.manual.end()
        }
        // Whoever has used it has learned it.
        settings.optionHintsShown = StayAwakeSettings.optionHintLimit
        Log.awake.info("Option while closing: decision \(self.flip == nil ? "restored" : "flipped", privacy: .public)")
        return true
    }

    func macWillSleep() {
        if arbiter.state.holdsLid, arbiter.lidClosed {
            Log.awake.error("the Mac is going to sleep although the lid is held")
            journal.sleptWhileHolding()
        } else {
            journal.macSlept()
        }
    }

    // MARK: For the interface

    var status: AwakeText.Status {
        if !arbiter.limits.isOn, let missed = journal.missed {
            return AwakeText.Status(dot: .warning, sentence: AwakeText.missed(missed), action: .turnOn)
        }
        if !arbiter.state.holdsLid, let receipt = journal.last, !receipt.read, let line = AwakeText.receipt(receipt).first {
            return AwakeText.Status(dot: .winding, sentence: line, action: .ok)
        }
        if let pendingApp { return AwakeText.pending(pendingApp.name) }
        return AwakeText.status(state: arbiter.state, reasons: arbiter.reasons, conditions: arbiter.conditions,
                         limits: arbiter.limits, canUndo: arbiter.canUndoLetItSleep, everTurnedOn: settings.hasConsented, now: Date())
    }

    /// An app to ask about, only while nothing is holding the lid: a question must never
    /// push a working status off the bar.
    var pendingApp: SeenApp? {
        arbiter.state == .ready ? arbiter.pendingApps.first : nil
    }

    /// The caption for the real close. `beginning` is the one call per close that may
    /// spend one of the five "Hold ⌥" hints.
    func closingCaption(beginning: Bool) -> AwakeText.Caption? {
        let teach = settings.optionHintsShown < StayAwakeSettings.optionHintLimit
        let caption = AwakeText.closingCaption(state: arbiter.state, reasons: arbiter.reasons,
                                               conditions: arbiter.conditions, teachOption: teach)
        if beginning, caption?.hint != nil { settings.optionHintsShown += 1 }
        return caption
    }

    var caption: String? {
        AwakeText.caption(state: arbiter.state, reasons: arbiter.reasons, conditions: arbiter.conditions)
    }

    /// The first switch-on goes through the consent sheet; `consent()` finishes it.
    var needsConsent: Bool { !settings.hasConsented }

    func consent() {
        settings.hasConsented = true
        settings.isOn = true
        journal.dismissMissed()
    }

    func perform(_ action: AwakeText.Action) {
        switch action {
        case .turnOn: if settings.hasConsented { settings.isOn = true }
        case .letItSleep: arbiter.letItSleep()
        case .keepAwake: arbiter.manual.begin(for: 3600)
        case .undo: arbiter.undoLetItSleep()
        case .ok: journal.markRead(); objectWillChange.send()
        case .allow: if let pendingApp { arbiter.mirror.setAllowed(pendingApp.bundleID, true) }
        case .notThisApp: if let pendingApp { arbiter.mirror.setAllowed(pendingApp.bundleID, false) }
        }
    }

    /// The "You say so" dial: stop 0 ends the hold, the last stop holds until stopped, the
    /// ones between hold for `AwakeText.manualDurations`.
    func setManualHold(stop: Int) {
        if stop > 0 { settings.lastManualStop = min(stop, AwakeText.manualLastStop) }
        if stop <= 0 { arbiter.manual.end() }
        else if stop >= AwakeText.manualLastStop { arbiter.manual.begin(for: nil) }
        else { arbiter.manual.begin(for: AwakeText.manualDurations[stop - 1]) }
    }

    /// The first time Settings opens, the battery level starts from the charge right now, so
    /// nobody has to work out a number: the step just under it (65 % → 60 %). Just under, not
    /// at, because at the charge itself the Mac would refuse to stay awake on battery at once.
    /// Once only: after that the level is the user's.
    func startTheBatteryLevelFromTheChargeOnce() {
        guard !settings.batteryLevelSeeded, let percent = arbiter.conditions.batteryPercent else { return }
        settings.batteryLevelSeeded = true
        settings.batteryFloor = Self.levelJustUnder(percent)
    }

    /// The level the charge right now suggests, when it is not the one already set: what the
    /// "Use 60 %" link under the slider offers. Saved like any other change to the level.
    var levelFromTheCharge: Int? {
        guard let percent = arbiter.conditions.batteryPercent else { return nil }
        let level = Self.levelJustUnder(percent)
        return level == settings.batteryFloor ? nil : level
    }

    func setTheBatteryLevelFromTheCharge() {
        guard let level = levelFromTheCharge else { return }
        settings.batteryLevelSeeded = true
        settings.batteryFloor = level
    }

    static func levelJustUnder(_ percent: Int) -> Int {
        let range = HoldLimits.batteryFloorRange
        return min(max((percent - 1) / 5 * 5, range.lowerBound), range.upperBound)
    }

    /// "For a set time", one click: the last duration chosen, starting now.
    func startTimedHold() { setManualHold(stop: max(settings.lastManualStop, 1)) }

    /// "Automatically", one click: the timer ends and the rules decide again.
    func returnToAutomatic() { setManualHold(stop: 0) }

    /// The running manual hold, if any.
    var manualHold: HoldReason? { arbiter.manual.reasons.first }

    func manualStop(now: Date = Date()) -> Int {
        guard let hold = manualHold else { return 0 }
        return AwakeText.manualStop(remaining: hold.until.map { $0.timeIntervalSince(now) })
    }
}
