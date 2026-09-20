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
        /// Answers to "this app is asking to stay awake".
        case allow, notThisApp
        var title: String {
            switch self {
            case .turnOn: return "Turn on…"
            case .letItSleep: return "Let it sleep"
            case .keepAwake: return "Keep awake"
            case .undo: return "Undo"
            case .ok: return "OK"
            case .allow: return "Allow"
            case .notThisApp: return "Not this app"
            }
        }
    }

    /// `everTurnedOn`: the user has been through the consent sheet. Someone who switched
    /// the feature off knows what it is; the bar stops offering it and just says so.
    static func status(state: HoldState, reasons: [HoldReason], conditions: PowerConditions, limits: HoldLimits,
                       canUndo: Bool, everTurnedOn: Bool = false, now: Date) -> Status {
        if canUndo, !state.holdsLid {
            return Status(dot: .idle, sentence: "Letting it sleep", action: .undo)
        }
        switch state {
        case .off:
            if everTurnedOn { return Status(dot: .idle, sentence: "Off · lid sleeps as usual", action: nil) }
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

    /// An app is asking macOS to stay awake and Shut is not holding the lid for it,
    /// because nobody has said whether it may. Asked once, only while nothing else holds.
    static func pending(_ app: String) -> Status {
        Status(dot: .idle, sentence: "\(app) is asking to stay awake", action: .allow)
    }

    static func pendingHero(_ app: String) -> Hero {
        Hero(headline: "\(app) is asking to stay awake.",
             detail: "Shut is not holding the lid for it. Allow, and your Mac stays awake with the lid shut while \(app) needs it.",
             showsCards: false)
    }

    /// The menu bar badge: what the lid would do now, without the journal's unread receipt
    /// (that belongs to the panel, and would leave a ring up until someone read it).
    static func badge(state: HoldState, conditions: PowerConditions, limits: HoldLimits) -> Dot {
        switch state {
        case .off, .ready: return .idle
        case .holding:
            let low = !conditions.onCharger && (conditions.batteryPercent.map { $0 <= limits.batteryFloor + 5 } ?? false)
            return low ? .warning : .holding
        case .grace: return .winding
        case .stopped(let reason): return reason == .userLetItSleep ? .idle : .warning
        }
    }

    /// Who is working: the tool when it is known ("Claude Code"), else the app ("Cursor").
    static func subject(_ reason: HoldReason) -> String { reason.tool ?? reason.title }

    struct Hero: Equatable {
        let headline: String
        let detail: String
        /// A warning needs its card even when there is only one reason.
        let showsCards: Bool
    }

    /// The Awake page in two sentences: what is happening, and what the lid will do.
    static func hero(state: HoldState, reasons: [HoldReason], conditions: PowerConditions, limits: HoldLimits, now: Date) -> Hero {
        let floor = conditions.batteryPercent == nil ? "" : ", or at \(limits.batteryFloor) % battery"
        switch state {
        case .off:
            return Hero(headline: "Off.", detail: "The lid sleeps your Mac as usual.", showsCards: false)
        case .ready:
            return Hero(headline: "Nothing is working.", detail: "Close the lid and your Mac sleeps, as it always has.", showsCards: false)
        case .grace(let until):
            return Hero(headline: "Finished.",
                        detail: "Your Mac sleeps in \(duration(until.timeIntervalSince(now))) unless the work starts again.", showsCards: false)
        case .stopped(let reason):
            return Hero(headline: reason == .userLetItSleep ? "Letting it sleep." : "Not holding the lid.",
                        detail: reason == .userLetItSleep ? "Close the lid and your Mac sleeps, although something is working."
                                                          : stopped(reason, conditions: conditions) + ".", showsCards: false)
        case .holding:
            let low = !conditions.onCharger && (conditions.batteryPercent.map { $0 <= limits.batteryFloor + 5 } ?? false)
            guard let first = reasons.first else {
                return Hero(headline: "Staying awake.", detail: "Close the lid and your Mac stays awake.", showsCards: low)
            }
            let headline: String
            if reasons.count > 1 {
                headline = "\(reasons.count) things are keeping your Mac awake."
            } else {
                switch first.kind {
                case .working: headline = "\(subject(first)) is working\(first.tool == nil ? "" : " in \(first.title)")."
                case .display: headline = "\(first.title) is connected."
                case .appOpen: headline = "\(first.title) is open."
                case .command: headline = "\(first.title) is running."
                case .manual: headline = first.until.map { "Awake until \(clock($0))." } ?? "Kept awake by you."
                }
            }
            let ends = reasons.count == 1 && first.kind == .manual
                ? (first.until == nil ? "until you let it sleep" : "until then")
                : "and sleeps by itself when \(reasons.count > 1 ? "they end" : "that ends")"
            return Hero(headline: headline, detail: "Close the lid: your Mac stays awake \(ends)\(floor).", showsCards: low)
        }
    }

    /// "Cursor is working · 47 min"
    static func holding(_ reasons: [HoldReason], now: Date) -> String {
        guard let first = reasons.first else { return "Staying awake" }
        if reasons.count == 1 {
            let since = duration(now.timeIntervalSince(first.since))
            switch first.kind {
            case .working: return "\(subject(first)) is working · \(since)"
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
            case .working: return "Staying awake · \(subject(first)) is working"
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

    /// What the closing transition shows: the line, whether it is bad news (set in
    /// Saffron), and, the first few times, how to change the decision.
    struct Caption: Equatable {
        let text: String
        let warning: Bool
        let hint: String?
    }

    static func closingCaption(state: HoldState, reasons: [HoldReason], conditions: PowerConditions, teachOption: Bool) -> Caption? {
        guard let text = caption(state: state, reasons: reasons, conditions: conditions) else { return nil }
        let warning: Bool
        switch state {
        case .stopped(.batteryFloor), .stopped(.tooHot): warning = true
        default: warning = false
        }
        return Caption(text: text, warning: warning,
                       hint: teachOption && state.holdsLid ? "Hold ⌥ to let it sleep instead" : nil)
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

    /// The collapsed Options row: the reasons that are on, then the limit that matters most.
    static func optionsSummary(working: Bool, display: Bool, apps: Bool, batteryFloor: Int) -> String {
        var reasons: [String] = []
        if working { reasons.append("working") }
        if display { reasons.append("display") }
        if apps { reasons.append("apps") }
        let first = reasons.isEmpty ? "Only when you say so" : reasons.joined(separator: " · ").capitalizedFirst
        return first + " · sleeps at \(batteryFloor) %"
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

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
