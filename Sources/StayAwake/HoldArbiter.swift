import Combine
import Foundation

/// Owns the decision. Collects reasons from every source, runs them through
/// `HoldStateMachine`, and applies the answer to the system through `LidHolding`.
///
/// Timers, and why each exists (CLAUDE.md rule 11):
/// - a one-shot at the next deadline (grace end, timed hold end, battery cap);
/// - a slow assertion read while the feature is on, because macOS sends no event
///   when one app's stay-awake request ends (30 s, wide tolerance);
/// - a re-apply tick only while holding with the lid shut, because `powerd` can
///   clear the shared kernel bit behind our back (10 s, wide tolerance).
/// With the feature off none of them run.
@MainActor
public final class HoldArbiter: ObservableObject {
    @Published public private(set) var state: HoldState = .off
    @Published public private(set) var reasons: [HoldReason] = []
    /// Apps asking to stay awake that the user has not decided about; see `AssertionMirror.pendingApps`.
    @Published public private(set) var pendingApps: [SeenApp] = []
    @Published public private(set) var conditions = PowerConditions()
    /// True for a few seconds after "Let it sleep", while Undo is offered.
    @Published public private(set) var canUndoLetItSleep = false

    public var limits: HoldLimits { didSet { if limits != oldValue { limitsChanged(from: oldValue) } } }
    public private(set) var lidClosed = false

    public let manual: ManualHold
    public let mirror: AssertionMirror
    public let displays: DisplayConnected
    public let apps: AppsOpen

    /// Reports every state change with the reasons at that moment (for the journal).
    public var onTransition: ((_ from: HoldState, _ to: HoldState, _ reasons: [HoldReason]) -> Void)?

    private let hold: LidHolding
    private let marker: ArmedMarker
    private let monitor: PowerSourceMonitor
    private let now: () -> Date
    private var machine = HoldStateMachine()
    private var extraSources: [HoldSource] = []
    private var deadlineTimer: Timer?
    private var mirrorTimer: Timer?
    private var reapplyTimer: Timer?
    private var undoTimer: Timer?
    private var applied = false
    private var reasonToggles: Set<HoldReason.Kind> = [.working, .display]

    /// The optional parts default to the real system; tests pass stand-ins.
    public init(limits: HoldLimits = HoldLimits(), hold: LidHolding = LidHold(), marker: ArmedMarker = ArmedMarker(),
                monitor: PowerSourceMonitor? = nil, mirror: AssertionMirror? = nil,
                apps: AppsOpen? = nil, now: @escaping () -> Date = Date.init) {
        self.limits = limits
        self.hold = hold
        self.marker = marker
        self.monitor = monitor ?? PowerSourceMonitor()
        self.mirror = mirror ?? AssertionMirror()
        self.apps = apps ?? AppsOpen()
        self.now = now
        manual = ManualHold()
        displays = DisplayConnected()
    }

    // MARK: Lifecycle

    /// Call once at launch, before anything else: undoes a hold a crashed run left behind.
    @discardableResult
    public func recoverFromLastRun() -> Bool { marker.recover(using: hold) }

    public func start() {
        monitor.onChange = { [weak self] in self?.powerChanged() }
        monitor.start()
        conditions = monitor.conditions
        for source in allSources { source.onChange = { [weak self] in self?.evaluate() } }
        manual.start()
        syncSources()
        evaluate()
    }

    /// Quit, update relaunch, handover to another copy: always leave the lid as we found it.
    public func shutDown() {
        [deadlineTimer, mirrorTimer, reapplyTimer, undoTimer].forEach { $0?.invalidate() }
        allSources.forEach { $0.stop() }
        monitor.stop()
        apply(false)
    }

    /// Adds a source the module does not know about (the `shut hold` command server).
    public func add(_ source: HoldSource) {
        extraSources.append(source)
        source.onChange = { [weak self] in self?.evaluate() }
        if limits.isOn { source.start() }
        evaluate()
    }

    // MARK: Inputs

    /// Which kinds of reason the user has switched on. Manual and command always count.
    public func setEnabled(_ kind: HoldReason.Kind, _ enabled: Bool) {
        if enabled { reasonToggles.insert(kind) } else { reasonToggles.remove(kind) }
        syncSources()
        evaluate()
    }

    public func isEnabled(_ kind: HoldReason.Kind) -> Bool { reasonToggles.contains(kind) }

    /// From the hinge: the lid has started to close. The one moment a fresh answer
    /// matters most, so read the assertions now rather than trust a 30 s old one.
    public func lidIsClosing() {
        guard limits.isOn, isEnabled(.working) else { return }
        mirror.refresh()
        evaluate()
    }

    public func lidChanged(closed: Bool) {
        guard closed != lidClosed else { return }
        lidClosed = closed
        evaluate()
    }

    /// Shut's window is on screen: keep the cards live. Off again when it closes.
    public func setLiveUpdates(_ live: Bool) {
        mirrorInterval = live ? 3 : 30
        scheduleMirrorTimer()
        if live { mirror.refresh(); evaluate() }
    }

    public func letItSleep() {
        manual.end()
        machine.letItSleep(reasons: reasons, now: now())
        canUndoLetItSleep = true
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.canUndoLetItSleep = false }
        }
        evaluate()
    }

    public func undoLetItSleep() {
        machine.undoLetItSleep()
        canUndoLetItSleep = false
        evaluate()
    }

    // MARK: Decision

    private var allSources: [HoldSource] { [manual, mirror, displays, apps] + extraSources }

    private func syncSources() {
        let on = limits.isOn
        toggle(mirror, on && isEnabled(.working))
        toggle(displays, on && isEnabled(.display))
        toggle(apps, on && isEnabled(.appOpen))
        extraSources.forEach { toggle($0, on) }
        if !on { manual.end() }
        scheduleMirrorTimer()
    }

    private var running: Set<ObjectIdentifier> = []
    private func toggle(_ source: HoldSource, _ on: Bool) {
        let id = ObjectIdentifier(source)
        if on, running.insert(id).inserted { source.start() }
        if !on, running.remove(id) != nil { source.stop() }
    }

    private func limitsChanged(from old: HoldLimits) {
        if limits.isOn != old.isOn { syncSources() }
        evaluate()
    }

    /// A fresh look at charger, battery and heat. Called as the lid shuts and opens.
    public func refreshPower() { monitor.readNow(); if monitor.conditions != conditions { powerChanged() } }

    private func powerChanged() {
        conditions = monitor.conditions
        // powerd recomputes the shared lid bit on power-source changes; put ours back first.
        if applied { hold.setLidSleepDisabled(true) }
        evaluate()
    }

    private func evaluate() {
        let moment = now()
        allSources.forEach { $0.prune(now: moment) }
        let collected = allSources.flatMap(\.reasons)
        if collected != reasons { reasons = collected }
        let pending = isEnabled(.working) && limits.isOn ? mirror.pendingApps : []
        if pending != pendingApps { pendingApps = pending }

        let previous = state
        let next = machine.update(limits: limits, conditions: conditions, reasons: collected, lidClosed: lidClosed, now: moment)
        apply(next.holdsLid)
        if next != previous {
            state = next
            onTransition?(previous, next, collected)
        }
        scheduleDeadline(at: machine.nextDeadline(limits: limits, reasons: collected, now: moment))
        scheduleReapply()
    }

    private func apply(_ shouldHold: Bool) {
        guard shouldHold != applied else { return }
        if shouldHold {
            // Marker first: if we die between the two lines the next launch still cleans up.
            marker.write()
            guard hold.setLidSleepDisabled(true) else { marker.remove(); return }
            hold.setIdleSleepPrevented(true)
        } else {
            hold.setIdleSleepPrevented(false)
            hold.setLidSleepDisabled(false)
            marker.remove()
        }
        applied = shouldHold
    }

    // MARK: Timers

    private var mirrorInterval: TimeInterval = 30

    private func scheduleDeadline(at date: Date?) {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        guard let date else { return }
        let timer = Timer(fire: date.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                // A deadline is the one way a hold ends with nobody asking for it, and with
                // the lid shut, ending it is sleep: not something to decide on a reading that
                // is up to thirty seconds old. Look again first. (Seen for real: a five-minute
                // manual hold ran out while an agent was mid-task, and the last reading had
                // landed between two of its caffeinate processes.)
                guard let self else { return }
                if self.limits.isOn, self.isEnabled(.working) { self.mirror.refresh() }
                self.evaluate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }

    private func scheduleMirrorTimer() {
        mirrorTimer?.invalidate()
        mirrorTimer = nil
        guard limits.isOn, isEnabled(.working) else { return }
        let timer = Timer(timeInterval: mirrorInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPower(); _ = self?.mirror.refresh() }
        }
        timer.tolerance = mirrorInterval / 3
        RunLoop.main.add(timer, forMode: .common)
        mirrorTimer = timer
    }

    private func scheduleReapply() {
        let needed = applied && lidClosed
        if needed, reapplyTimer == nil {
            let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { guard let self, self.applied else { return }; self.hold.setLidSleepDisabled(true) }
            }
            timer.tolerance = 4
            RunLoop.main.add(timer, forMode: .common)
            reapplyTimer = timer
        } else if !needed, reapplyTimer != nil {
            reapplyTimer?.invalidate()
            reapplyTimer = nil
        }
    }
}
