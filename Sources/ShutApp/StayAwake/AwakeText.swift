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
        /// The one button, when there is something to do.
        let action: Action?
        /// A warning with the lid about to sleep the Mac (a limit has spoken): the eyes are
        /// shut then. A warning while still holding (battery getting near) keeps them open.
        var lidSleeps = false
    }

    enum Action: Equatable {
        case turnOn, letItSleep, keepAwake, undo, ok
        /// Answers to "this app is asking to stay awake".
        case allow, notThisApp
        /// Where the action leaves the Mac. The button shows it before it is pressed: Lime and
        /// open eyes for "stays awake", an outline and shut eyes for "sleeps". They used to be
        /// one dark button with four different meanings.
        enum Outcome { case staysAwake, sleeps, neutral }

        var outcome: Outcome {
            switch self {
            case .keepAwake, .undo, .allow: return .staysAwake
            case .letItSleep, .notThisApp: return .sleeps
            case .turnOn, .ok: return .neutral
            }
        }

        /// One plain line under the button: what pressing it will do. `who` is what is working
        /// ("Claude Code"), or the app that is asking.
        func consequence(who: String?) -> String? {
            switch self {
            case .letItSleep:
                // The headline above the button already says what the lid will do; this adds only
                // what it does not: that it is for one close.
                return "Just this once" + (who.map { ", even though \($0) is working." } ?? ".")
            case .keepAwake: return "For another hour."
            case .allow: return who.map { "\($0) may keep your Mac awake, now and from now on." }
            case .undo, .notThisApp, .turnOn, .ok: return nil
            }
        }

        var title: String {
            switch self {
            case .turnOn: return "Turn on…"
            case .letItSleep: return "Let it sleep"
            case .keepAwake: return "Keep it awake"
            case .undo: return "Keep it awake"
            case .ok: return "OK"
            case .allow: return "Allow"
            case .notThisApp: return "Not this app"
            }
        }
    }

    /// On battery, at or under the level the user set: nothing can keep the Mac awake until it
    /// charges. Said with both numbers, because "battery low" alone does not say which side of
    /// the line it is on.
    struct BatteryTooLow: Equatable {
        let percent: Int
        let floor: Int
        var title: String { "Battery \(percent) % · too low" }
        var rule: String { "It stays awake only above \(floor) %." }
        static let changeLevel = "Change the level"
        var tab: String { "Battery \(percent) % · too low" }
        /// Under the battery slider, in place of its usual explanation.
        var setting: String { "Your battery is at \(percent) % now, under this level, so the lid sleeps your Mac." }
        var sentence: String { "Battery \(percent) % is under your \(floor) % limit · lid will sleep your Mac" }
    }

    /// Under the battery slider: the charge right now, so the level is chosen against it.
    static func batteryNow(_ conditions: PowerConditions) -> String {
        conditions.batteryPercent.map { "Your battery is at \($0) % now." } ?? ""
    }

    static func batteryTooLow(conditions: PowerConditions, limits: HoldLimits) -> BatteryTooLow? {
        guard !conditions.onCharger, let percent = conditions.batteryPercent, percent <= limits.batteryFloor else { return nil }
        return BatteryTooLow(percent: percent, floor: limits.batteryFloor)
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
            if let low = batteryTooLow(conditions: conditions, limits: limits) {
                return Status(dot: .idle, sentence: low.sentence, action: nil)
            }
            return Status(dot: .idle, sentence: "Closing the lid will sleep your Mac", action: nil)
        case .holding:
            if !conditions.onCharger, let percent = conditions.batteryPercent, percent <= limits.batteryFloor + 5 {
                return Status(dot: .warning, sentence: "On battery \(percent) % · sleeps at \(limits.batteryFloor) %", action: .letItSleep)
            }
            return Status(dot: .holding, sentence: holding(reasons, now: now), action: .letItSleep)
        case .grace(let until):
            return Status(dot: .winding, sentence: "Finished · sleeping in \(duration(until.timeIntervalSince(now)))", action: .keepAwake)
        case .stopped(let reason):
            if reason == .batteryFloor, let low = batteryTooLow(conditions: conditions, limits: limits) {
                return Status(dot: .warning, sentence: low.sentence, action: nil, lidSleeps: true)
            }
            return Status(dot: reason == .userLetItSleep ? .idle : .warning, sentence: stopped(reason, conditions: conditions), action: nil, lidSleeps: true)
        }
    }

    /// The "Stay awake" tab's second line: its state in three or four words, so the tab is
    /// plainly a section with a life of its own, and the state shows from the other section.
    static func tabLine(state: HoldState, reasons: [HoldReason], conditions: PowerConditions, limits: HoldLimits,
                        pendingApp: String? = nil, now: Date) -> String {
        if let pendingApp, state == .ready { return "\(pendingApp) is asking" }
        switch state {
        case .off: return "Off"
        case .ready: return batteryTooLow(conditions: conditions, limits: limits)?.tab ?? "Lid will sleep your Mac"
        case .grace(let until): return "Sleeping in \(duration(until.timeIntervalSince(now)))"
        case .stopped(let reason):
            switch reason {
            case .batteryFloor: return batteryTooLow(conditions: conditions, limits: limits)?.tab ?? "Battery low · will sleep"
            case .tooHot: return "Too hot · will sleep"
            case .timeCap: return "8 h on battery · will sleep"
            case .lowPowerMode: return "Low Power Mode · will sleep"
            case .chargerOnly: return "On battery · will sleep"
            case .userLetItSleep: return "Letting it sleep"
            }
        case .holding:
            if !conditions.onCharger, let percent = conditions.batteryPercent, percent <= limits.batteryFloor + 5 {
                return "Battery \(percent) % · sleeps at \(limits.batteryFloor) %"
            }
            guard let first = reasons.first else { return "Staying awake" }
            if reasons.count > 1 { return "\(reasons.count) things keep it awake" }
            switch first.kind {
            case .working, .command: return "\(subject(first)) · \(duration(now.timeIntervalSince(first.since)))"
            case .display, .appOpen: return first.title
            case .manual: return first.until.map { "Until \(clock($0))" } ?? "Until you stop it"
            }
        }
    }

    /// An app is asking macOS to stay awake and Shut is not holding the lid for it,
    /// because nobody has said whether it may. Asked once, only while nothing else holds.
    static func pending(_ app: String) -> Status {
        Status(dot: .idle, sentence: "\(app) is asking to stay awake", action: .allow)
    }

    static func pendingHero(_ app: String) -> Hero {
        Hero(headline: "\(app) is asking to stay awake.",
             detail: "Shut is not keeping your Mac awake for it yet: nobody has said whether it may.",
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

    /// The Awake page always answers the one question anyone has about this feature, in the
    /// same words every time: what will closing the lid do? The headline is the answer, the
    /// detail is why. ("Nothing is working." was the old headline, and read like an error.)
    /// `watchingApps`: "An app is busy" is on. When it is not, the page says so, because then
    /// an agent or a build will not keep the Mac awake and nothing else would mention it.
    static func hero(state: HoldState, reasons: [HoldReason], conditions: PowerConditions, limits: HoldLimits,
                     watchingApps: Bool = true, now: Date) -> Hero {
        let willSleep = "Closing the lid will sleep your Mac."
        let staysAwake = "Closing the lid keeps your Mac awake."
        // A no-break space: "20" at the end of one line and "% battery" on the next reads badly.
        let floor = conditions.batteryPercent == nil ? "" : ", or at \(limits.batteryFloor)\u{00A0}% battery"
        switch state {
        case .off:
            return Hero(headline: willSleep, detail: "Stay awake is off.", showsCards: false)
        case .ready, .stopped(.batteryFloor):
            // Under the battery level nothing can keep it awake, whatever is running or set:
            // say that first, with the card that shows both numbers.
            if batteryTooLow(conditions: conditions, limits: limits) != nil {
                return Hero(headline: willSleep,
                            detail: "Plug in and it can stay awake again.",
                            showsCards: true)
            }
            if case .stopped(let reason) = state {
                return Hero(headline: willSleep, detail: stopped(reason, conditions: conditions) + ". That limit always wins.", showsCards: false)
            }
            return Hero(headline: willSleep,
                        detail: watchingApps ? "Nothing is keeping it awake right now."
                                             : "Nothing is keeping it awake, and apps are not being watched: an agent or a build will not keep it awake until “An app is busy” is on.",
                        showsCards: false)
        case .grace(let until):
            return Hero(headline: "Your Mac will sleep in \(duration(until.timeIntervalSince(now))).",
                        detail: "The work has ended. It stays awake a little longer in case it starts again.", showsCards: false)
        case .stopped(let reason):
            return Hero(headline: willSleep,
                        detail: reason == .userLetItSleep ? "You chose that for this once, although something is working."
                                                          : stopped(reason, conditions: conditions) + ". That limit always wins.",
                        showsCards: false)
        case .holding:
            let low = !conditions.onCharger && (conditions.batteryPercent.map { $0 <= limits.batteryFloor + 5 } ?? false)
            guard let first = reasons.first else { return Hero(headline: staysAwake, detail: "", showsCards: low) }
            // A set time: the time it ends is the answer, so it goes in the headline, beside the eyes.
            if reasons.count == 1, first.kind == .manual {
                guard let until = first.until else {
                    return Hero(headline: staysAwake, detail: "Until you choose Automatically\(floor).", showsCards: low)
                }
                return Hero(headline: "Your Mac stays awake until \(clock(until)).",
                            detail: "Lid shut or open."
                                + (conditions.batteryPercent == nil ? "" : " It also sleeps at \(limits.batteryFloor)\u{00A0}% battery."),
                            showsCards: low)
            }
            // Under Automatically the box beside this names who, with icon and time; said once.
            if !reasons.contains(where: { $0.kind == .manual }) {
                return Hero(headline: staysAwake,
                            detail: "It sleeps by itself when \(reasons.count > 1 ? "they end" : "that ends")\(floor).", showsCards: low)
            }
            let why: String
            if reasons.count > 1 {
                why = "\(reasons.count) things are keeping it awake"
            } else {
                switch first.kind {
                case .working: why = "\(subject(first)) is working\(first.tool == nil ? "" : " in \(first.title)")"
                case .display: why = "\(first.title) is connected"
                case .appOpen: why = "\(first.title) is open"
                case .command: why = "\(first.title) is running"
                case .manual: why = "You said so"
                }
            }
            return Hero(headline: staysAwake,
                        detail: "\(why). It sleeps by itself when \(reasons.count > 1 ? "they end" : "that ends")\(floor).", showsCards: low)
        }
    }

    /// One trigger's line while it is the one at work: "Claude Code in Cursor · 47 min",
    /// "Studio Display", "Xcode and 1 more". nil when nothing of that kind is holding.
    /// `named: false` while the "Keeping it awake now" box is on the page: it names them, the
    /// row only marks which rule is at work.
    static func live(_ reasons: [HoldReason], named: Bool = true, now: Date) -> String? {
        guard let first = reasons.first else { return nil }
        guard named else { return "At work now" }
        let who: String
        switch first.kind {
        case .working: who = first.tool.map { "\($0) in \(first.title)" } ?? first.title
        default: who = first.title
        }
        if reasons.count > 1 { return "\(who) and \(reasons.count - 1) more" }
        switch first.kind {
        case .working, .command: return "\(who) · \(duration(now.timeIntervalSince(first.since)))"
        default: return who
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

    // MARK: The two ways to stay awake

    /// Automatic, in one sentence made of the rules that are on, so the mode says what it
    /// will actually do. With none on, it says that too: then only a set time keeps it awake.
    static func automaticSummary(working: Bool, display: Bool, pickedApps: Int) -> String {
        var rules: [String] = []
        if working { rules.append("an app is busy") }
        if display { rules.append("a display is connected") }
        if pickedApps > 0 { rules.append(pickedApps == 1 ? "the app you picked is open" : "an app you picked is open") }
        guard !rules.isEmpty else { return "No rule is switched on below, so nothing keeps it awake by itself." }
        let list = rules.count == 1 ? rules[0] : rules.dropLast().joined(separator: ", ") + " or " + rules[rules.count - 1]
        return "Stays awake while \(list), and sleeps by itself when that ends."
    }

    /// One line of "Keeping it awake now", under Automatically: who, and how long or what.
    struct Holder: Equatable {
        let name: String
        let detail: String
    }

    static func holder(_ reason: HoldReason, now: Date) -> Holder {
        switch reason.kind {
        case .working:
            return Holder(name: reason.tool.map { "\($0) in \(reason.title)" } ?? reason.title,
                          detail: "busy · " + duration(now.timeIntervalSince(reason.since)))
        case .command: return Holder(name: reason.title, detail: "running · " + duration(now.timeIntervalSince(reason.since)))
        case .display: return Holder(name: reason.title, detail: "connected")
        case .appOpen: return Holder(name: reason.title, detail: "open")
        case .manual: return Holder(name: "You said so", detail: reason.until.map { "until " + clock($0) } ?? "until you stop it")
        }
    }

    /// At most three lines fit the box; the rest are counted.
    static let holdersShown = 3
    static func moreHolders(_ count: Int) -> String? {
        count > holdersShown ? "and \(count - holdersShown) more" : nil
    }

    // MARK: The "You say so" dial

    /// The dial's stops between Off (0) and "until I stop" (the last): close together where
    /// people actually choose (a meeting, a build), far apart beyond that.
    static let manualDurations: [TimeInterval] = [5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720].map { $0 * 60 }
    static var manualLastStop: Int { manualDurations.count + 1 }

    /// The value column is narrow, so the dial says it short; the caption under it says it whole.
    static func manualValue(stop: Int) -> String {
        if stop <= 0 { return "Off" }
        if stop >= manualLastStop { return "∞" }
        let minutes = Int(manualDurations[stop - 1] / 60)
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min"
    }

    /// Where the thumb sits for a hold that is running: the smallest stop that still covers
    /// the time left, so the dial drifts towards Off as the time runs out.
    static func manualStop(remaining: TimeInterval?) -> Int {
        guard let remaining else { return manualLastStop }
        return (manualDurations.firstIndex { $0 >= remaining - 30 } ?? manualDurations.count - 1) + 1
    }

    /// The line under the dial. `stop` is where the thumb is (while dragging, where it would
    /// land); `until` is the running hold's end, nil for none or for "until I stop".
    static func manualCaption(stop: Int, running: Bool, until: Date?, now: Date) -> String {
        if stop <= 0 { return "Drag to pick how long, whatever is running." }
        if stop >= manualLastStop { return running ? "Awake until you choose Automatically." : "Until you choose Automatically." }
        if running, let until {
            return "\(duration(until.timeIntervalSince(now))) left, then back to automatic."
        }
        return "Until \(clock(now.addingTimeInterval(manualDurations[stop - 1]))), then back to automatic."
    }

    /// A set time that a limit overrules: say which, and that the time is still running.
    static func manualBlocked(_ reason: StopReason) -> String {
        let why: String
        switch reason {
        case .batteryFloor: why = "the battery is too low"
        case .tooHot: why = "your Mac is hot"
        case .timeCap: why = "it has been 8 hours on battery"
        case .lowPowerMode: why = "Low Power Mode is on"
        case .chargerOnly: why = "it is set to stay awake on the charger only"
        case .userLetItSleep: why = "you chose to let it sleep"
        }
        return "Not right now: \(why). The time keeps counting."
    }

    /// The folded Limits row: the ones most worth knowing without opening it.
    static func limitsSummary(batteryFloor: Int, lockWhenShut: Bool, chargerOnly: Bool) -> String {
        var parts = [chargerOnly ? "Charger only" : "Sleeps at \(batteryFloor) % battery"]
        if lockWhenShut { parts.append("locks when shut") }
        return parts.joined(separator: " · ")
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
        // macOS puts a narrow no-break space before AM/PM; Playfair Display has no glyph
        // for it and sets "3:23PM". An ordinary no-break space keeps the two together.
        return formatter.string(from: date).replacingOccurrences(of: "\u{202F}", with: "\u{00A0}")
    }
}
