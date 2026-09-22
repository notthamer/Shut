import Foundation

/// The limits, as one pure function so the whole safety table can be tested
/// without a battery, a lid or a clock.
public enum StayAwakePolicy {
    /// The first limit that forbids holding right now, or nil when holding is allowed.
    /// Order matters only for which sentence the user reads; any one of them is enough.
    public static func blocker(limits: HoldLimits, conditions: PowerConditions, lidClosed: Bool,
                               onBatterySince: Date?, now: Date) -> StopReason? {
        if limits.respectLowPowerMode, conditions.lowPowerMode { return .lowPowerMode }
        if limits.chargerOnly, !conditions.onCharger { return .chargerOnly }
        if !conditions.onCharger, let percent = conditions.batteryPercent, percent <= limits.batteryFloor {
            return .batteryFloor
        }
        // A shut lid is a worse radiator and nobody is watching the screen, so the
        // threshold drops one level when closed.
        if conditions.thermal >= (lidClosed ? .serious : .critical) { return .tooHot }
        if !conditions.onCharger, let start = onBatterySince, now.timeIntervalSince(start) >= limits.batteryCap {
            return .timeCap
        }
        return nil
    }
}

/// Turns reasons, limits and conditions into one `HoldState`. A value type with no
/// I/O: `HoldArbiter` feeds it and acts on the answer.
public struct HoldStateMachine {
    public private(set) var state: HoldState = .off
    /// When the current stretch of holding on battery began; the cap counts from here.
    public private(set) var onBatterySince: Date?
    private var graceUntil: Date?
    private var hadWork = false
    /// Reasons that were true when the user said "Let it sleep". They stay overruled
    /// until they end or a new reason appears.
    private var overruled: Set<String> = []

    public init() {}

    /// Reasons that have not run out.
    public static func active(_ reasons: [HoldReason], now: Date) -> [HoldReason] {
        reasons.filter { $0.until.map { $0 > now } ?? true }
    }

    @discardableResult
    public mutating func update(limits: HoldLimits, conditions: PowerConditions, reasons: [HoldReason],
                                lidClosed: Bool, now: Date) -> HoldState {
        guard limits.isOn else {
            self = HoldStateMachine()
            return state
        }
        let active = Self.active(reasons, now: now)
        let ids = Set(active.map(\.id))

        if active.isEmpty || !ids.isSubset(of: overruled) { overruled = [] }

        // Work that stops gets a grace period: an agent between two turns looks
        // finished for a moment. A display unplugged or an app quit does not.
        let hasWork = active.contains { $0.kind == .working || $0.kind == .command }
        if active.isEmpty {
            if hadWork, state == .holding { graceUntil = now.addingTimeInterval(limits.grace) }
            if let until = graceUntil, until <= now { graceUntil = nil }
        } else {
            graceUntil = nil
        }
        hadWork = hasWork || (active.isEmpty && graceUntil != nil)

        guard !active.isEmpty || graceUntil != nil else {
            onBatterySince = nil
            state = .ready
            return state
        }

        if !overruled.isEmpty {
            state = .stopped(.userLetItSleep)
            return state
        }

        if conditions.onCharger { onBatterySince = nil } else if onBatterySince == nil { onBatterySince = now }

        if let reason = StayAwakePolicy.blocker(limits: limits, conditions: conditions, lidClosed: lidClosed,
                                                onBatterySince: onBatterySince, now: now) {
            state = .stopped(reason)
            return state
        }

        state = active.isEmpty ? .grace(until: graceUntil ?? now) : .holding
        return state
    }

    /// "Let it sleep": overrules whatever is true right now and ends any grace period.
    public mutating func letItSleep(reasons: [HoldReason], now: Date) {
        overruled = Set(Self.active(reasons, now: now).map(\.id))
        graceUntil = nil
        hadWork = false
        if overruled.isEmpty, state != .off { state = .ready }
    }

    public mutating func undoLetItSleep() { overruled = [] }

    /// The next moment the answer can change by itself: a grace period or a timed
    /// reason running out, or the battery cap. One one-shot timer, no polling.
    public func nextDeadline(limits: HoldLimits, reasons: [HoldReason], now: Date) -> Date? {
        var dates = Self.active(reasons, now: now).compactMap(\.until)
        if let graceUntil { dates.append(graceUntil) }
        if state == .holding, let start = onBatterySince { dates.append(start.addingTimeInterval(limits.batteryCap)) }
        return dates.filter { $0 > now }.min()
    }
}
