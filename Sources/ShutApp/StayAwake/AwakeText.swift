import Foundation
import StayAwake

/// Every sentence the Stay awake feature says, in one place and pure, so the
/// wording can be read (and tested) like copy rather than hunted through views.
///
/// The rule: status is always a sentence that names the reason and how it ends.
/// Never an icon alone, never a timer the user had to set.
enum AwakeText {
    enum Dot: Equatable { case idle, holding, winding, warning }

    struct Status: Equatable {
        let dot: Dot
        let sentence: String
        /// The bar's one button, when there is something to do.
        let action: Action?
    }

    enum Action: Equatable {
        case turnOn, letItSleep, keepAwake, undo, ok
        var title: String {
            switch self {
            case .turnOn: return "Turn on…"
            case .letItSleep: return "Let it sleep"
            case .keepAwake: return "Keep awake"
            case .undo: return "Undo"
            case .ok: return "OK"
            }
        }
    }

    static func status(state: HoldState, reasons: [HoldReason], conditions: PowerConditions, limits: HoldLimits,
                       canUndo: Bool, now: Date) -> Status {
        if canUndo, !state.holdsLid {
            return Status(dot: .idle, sentence: "Letting it sleep", action: .undo)
        }
        switch state {
        case .off:
            return Status(dot: .idle, sentence: "Keep working with the lid shut", action: .turnOn)
        case .ready:
            return Status(dot: .idle, sentence: "Nothing is working · lid sleeps as usual", action: nil)
        case .holding:
            if !conditions.onCharger, let percent = conditions.batteryPercent, percent <= limits.batteryFloor + 5 {
                return Status(dot: .warning, sentence: "On battery \(percent) % · sleeps at \(limits.batteryFloor) %", action: .letItSleep)
            }
            return Status(dot: .holding, sentence: holding(reasons, now: now), action: .letItSleep)
        case .grace(let until):
            return Status(dot: .winding, sentence: "Finished · sleeping in \(duration(until.timeIntervalSince(now)))", action: .keepAwake)
        case .stopped(let reason):
            return Status(dot: reason == .userLetItSleep ? .idle : .warning, sentence: stopped(reason, conditions: conditions), action: nil)
        }
    }

    /// "Cursor is working · 47 min"
    static func holding(_ reasons: [HoldReason], now: Date) -> String {
        guard let first = reasons.first else { return "Staying awake" }
        if reasons.count == 1 {
            let since = duration(now.timeIntervalSince(first.since))
            switch first.kind {
            case .working: return "\(first.title) is working · \(since)"
            case .display: return "\(first.title) is connected"
            case .appOpen: return "\(first.title) is open"
            case .command: return "\(first.title) is running · \(since)"
            case .manual: return first.until.map { "Kept awake by you until \(clock($0))" } ?? "Kept awake by you"
            }
        }
        if reasons.allSatisfy({ $0.kind == .working }) { return "\(reasons.count) apps are working" }
        return "\(reasons.count) reasons to stay awake"
    }

    /// The line set into the closing transition. One line, no numbers to read twice.
    static func caption(state: HoldState, reasons: [HoldReason], conditions: PowerConditions) -> String? {
        switch state {
        case .holding:
            guard let first = reasons.first else { return nil }
            if reasons.count > 1 {
                return "Staying awake · " + (reasons.allSatisfy { $0.kind == .working } ? "\(reasons.count) apps are working" : "\(reasons.count) reasons")
            }
            switch first.kind {
            case .working: return "Staying awake · \(first.title) is working"
            case .display: return "Staying awake · \(first.title) is connected"
            case .appOpen: return "Staying awake · \(first.title) is open"
            case .command: return "Staying awake · \(first.title) is running"
            case .manual: return first.until.map { "Staying awake until \(clock($0))" } ?? "Staying awake"
            }
        case .grace:
            return "Staying awake a little longer"
        case .stopped(.batteryFloor):
            return conditions.batteryPercent.map { "Sleeping · battery is at \($0) %" }
        case .stopped(.tooHot):
            return "Sleeping · your Mac is hot"
        case .stopped(.userLetItSleep):
            return "Sleeping this time"
        case .off, .ready, .stopped:
            return nil
        }
    }

    static func stopped(_ reason: StopReason, conditions: PowerConditions) -> String {
        switch reason {
        case .batteryFloor: return "Battery at \(conditions.batteryPercent ?? 0) % · letting the Mac sleep"
        case .tooHot: return "Your Mac is hot · letting it sleep"
        case .timeCap: return "8 hours on battery · letting the Mac sleep"
        case .lowPowerMode: return "Low Power Mode is on · lid sleeps as usual"
        case .chargerOnly: return "On battery · holds on the charger only"
        case .userLetItSleep: return "Letting it sleep"
        }
    }

    /// The line under the cards: how this ends.
    static func ending(reasons: [HoldReason], conditions: PowerConditions, limits: HoldLimits) -> String {
        let what: String
        switch reasons.count {
        case 0: what = "Sleeps when the lid shuts"
        case 1: what = "Sleeps when it ends"
        case 2: what = "Sleeps when both end"
        default: what = "Sleeps when all of them end"
        }
        guard !reasons.isEmpty, conditions.batteryPercent != nil else { return what + "." }
        return what + ", or at \(limits.batteryFloor) % battery."
    }

    /// "<1 min", "47 min", "2 h 5 min"
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(seconds, 0) / 60)
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest) min"
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
