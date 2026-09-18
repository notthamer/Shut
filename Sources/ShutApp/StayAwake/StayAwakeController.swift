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

    private var lidEdges: LidStateProvider?
    private var sessionActive = true
    private var cancellables = Set<AnyCancellable>()

    public init(settings: StayAwakeSettings? = nil, arbiter: HoldArbiter? = nil) {
        self.settings = settings ?? StayAwakeSettings()
        self.arbiter = arbiter ?? HoldArbiter(hold: LidHold(log: { Log.awake.error("\($0, privacy: .public)") }))
    }

    func start() {
        if arbiter.recoverFromLastRun() {
            Log.awake.notice("the last run ended while holding the lid; lid sleep restored")
        }
        arbiter.onTransition = { from, to, reasons in
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
        workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionActive = true; self?.applySettings() }
        }

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
        arbiter.limits = limits
        arbiter.setEnabled(.working, settings.whenWorking)
        arbiter.setEnabled(.display, settings.whenDisplayConnected)
        arbiter.setEnabled(.appOpen, settings.whenAppsOpen)
        arbiter.apps.bundleIDs = Set(settings.pickedApps)
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
        guard !isOpen, arbiter.state.holdsLid, settings.lockWhenShut else { return }
        ScreenLock.lock { [weak self] locked in
            if locked { self?.onLockedWhileShut?() }
        }
    }

    // MARK: For the lid

    /// From `AppController`, as the lid starts to come down.
    func lidStartedClosing() { arbiter.lidIsClosing() }

    // MARK: For the interface

    var status: AwakeText.Status {
        AwakeText.status(state: arbiter.state, reasons: arbiter.reasons, conditions: arbiter.conditions,
                         limits: arbiter.limits, canUndo: arbiter.canUndoLetItSleep, now: Date())
    }

    var caption: String? {
        AwakeText.caption(state: arbiter.state, reasons: arbiter.reasons, conditions: arbiter.conditions)
    }

    /// The first switch-on goes through the consent sheet; `consent()` finishes it.
    var needsConsent: Bool { !settings.hasConsented }

    func consent() {
        settings.hasConsented = true
        settings.isOn = true
    }

    func perform(_ action: AwakeText.Action) {
        switch action {
        case .turnOn: if settings.hasConsented { settings.isOn = true }
        case .letItSleep: arbiter.letItSleep()
        case .keepAwake: arbiter.manual.begin(for: 3600)
        case .undo: arbiter.undoLetItSleep()
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

    enum ManualChoice: Int, CaseIterable { case off, oneHour, fourHours, untilStopped }

    var manualChoice: ManualChoice {
        guard let reason = arbiter.manual.reasons.first else { return .off }
        guard let until = reason.until else { return .untilStopped }
        return until.timeIntervalSince(reason.since) > 3600 ? .fourHours : .oneHour
    }
}
