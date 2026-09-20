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
    private var flippedToSleep = false
    private var lidEdges: LidStateProvider?
    private var sessionActive = true
    private var cancellables = Set<AnyCancellable>()

    public init(settings: StayAwakeSettings? = nil, arbiter: HoldArbiter? = nil) {
        self.settings = settings ?? StayAwakeSettings()
        journal = HoldJournal(defaults: settings == nil ? .standard : UserDefaults(suiteName: "StayAwakeJournal-\(UUID().uuidString)") ?? .standard)
        self.arbiter = arbiter ?? HoldArbiter(hold: LidHold(log: { Log.awake.error("\($0, privacy: .public)") }))
    }

    func start() {
        if arbiter.recoverFromLastRun() {
            Log.awake.notice("the last run ended while holding the lid; lid sleep restored")
        }
        arbiter.onTransition = { [weak self] from, to, reasons in
            if let self, self.arbiter.lidClosed { self.journal.holdChanged(to: to) }
            Log.awake.info("hold \(String(describing: from), privacy: .public) -> \(String(describing: to), privacy: .public), reasons: \(reasons.map(\.id).joined(separator: ", "), privacy: .public)")
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
        if !sessionActive { limits.isOn = false }
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
        if on, lidEdges == nil {
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

    private func lidEdge(isOpen: Bool) {
        arbiter.lidChanged(closed: !isOpen)
        let battery = arbiter.conditions.batteryPercent
        if isOpen {
            journal.lidOpened(battery: battery)
            // Option flipped this one close to "sleep"; the next close decides afresh.
            if flippedToSleep { flippedToSleep = false; arbiter.undoLetItSleep() }
            objectWillChange.send()
        } else {
            journal.lidShut(holding: arbiter.state.holdsLid, reasons: arbiter.reasons, battery: battery)
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
        guard arbiter.limits.isOn, settings.optionFlips, NSEvent.modifierFlags.contains(.option) else { return }
        if arbiter.state.holdsLid {
            flippedToSleep = true
            arbiter.letItSleep()
        } else {
            arbiter.manual.begin(for: 3600)
        }
        Log.awake.info("Option held while closing: decision flipped")
    }

    private func macWillSleep() {
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
        return AwakeText.status(state: arbiter.state, reasons: arbiter.reasons, conditions: arbiter.conditions,
                         limits: arbiter.limits, canUndo: arbiter.canUndoLetItSleep, everTurnedOn: settings.hasConsented, now: Date())
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
        }
    }

    /// The "I say so" row: nil duration means until stopped; `off` ends it.
    func setManualHold(_ choice: ManualChoice) {
        switch choice {
        case .off: arbiter.manual.end()
        case .oneHour: arbiter.manual.begin(for: 3600)
        case .fourHours: arbiter.manual.begin(for: 4 * 3600)
        case .untilStopped: arbiter.manual.begin(for: nil)
        }
    }

    // MARK: Command line

    static var commandLineLink: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/shut")
    }

    var commandLineInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: Self.commandLineLink.path)) == Bundle.main.executablePath
    }

    /// Links `~/.local/bin/shut` to this app's executable, so `shut hold` works in a
    /// terminal. A user folder: no password, nothing outside the home directory.
    @discardableResult
    func installCommandLineTool() -> Bool {
        guard let executable = Bundle.main.executablePath else { return false }
        let link = Self.commandLineLink
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? manager.destinationOfSymbolicLink(atPath: link.path)) != nil { try manager.removeItem(at: link) }
            guard !manager.fileExists(atPath: link.path) else {
                Log.awake.error("~/.local/bin/shut exists and is not a link; leaving it alone")
                return false
            }
            try manager.createSymbolicLink(atPath: link.path, withDestinationPath: executable)
            objectWillChange.send()
            return true
        } catch {
            Log.awake.error("could not link the command line tool: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    enum ManualChoice: Int, CaseIterable { case off, oneHour, fourHours, untilStopped }

    var manualChoice: ManualChoice {
        guard let reason = arbiter.manual.reasons.first else { return .off }
        guard let until = reason.until else { return .untilStopped }
        return until.timeIntervalSince(reason.since) > 3600 ? .fourHours : .oneHour
    }
}
