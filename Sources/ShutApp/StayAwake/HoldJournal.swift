import Foundation
import StayAwake

/// What happened while the lid was shut, kept so the user can be told when they
/// come back. One entry, the last one; this is a receipt, not a history.
struct HoldReceipt: Codable, Equatable {
    var closedAt: Date
    var openedAt: Date?
    /// What the Mac was staying awake for when the lid shut: "Cursor".
    var titles: [String]
    var batteryAtClose: Int?
    var batteryAtOpen: Int?
    /// When the hold ended while the lid was still shut, and why. nil: it held
    /// until the lid opened.
    var endedAt: Date?
    var end: End?
    var read = false

    enum End: String, Codable { case finished, batteryFloor, tooHot, timeCap, lowPowerMode, chargerOnly, userLetItSleep, sleptAnyway }
}

/// The Mac slept on a lid close while something an allowed kind of app was doing
/// looked like work, and the feature was off. The one honest moment to offer it.
struct MissedMoment: Codable, Equatable {
    var app: String
    var at: Date
}

/// Writes the receipt as the lid shuts, the hold ends and the lid opens. Pure
/// bookkeeping on events the controller already has; no timers.
@MainActor
final class HoldJournal {
    private let defaults: UserDefaults
    private var open: HoldReceipt?

    private(set) var last: HoldReceipt? { didSet { save(last, "stayAwake.receipt") } }
    private(set) var missed: MissedMoment? { didSet { save(missed, "stayAwake.missed") } }

    /// Set as the lid starts to close with the feature off; confirmed by a sleep.
    private var candidate: MissedMoment?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        last = Self.load("stayAwake.receipt", from: defaults)
        missed = Self.load("stayAwake.missed", from: defaults)
    }

    // MARK: Receipt

    func lidShut(holding: Bool, reasons: [HoldReason], battery: Int?, now: Date = Date()) {
        guard holding else { open = nil; return }
        open = HoldReceipt(closedAt: now, titles: reasons.map(\.title), batteryAtClose: battery)
    }

    /// The hold's state changed while the lid was shut.
    func holdChanged(to state: HoldState, now: Date = Date()) {
        guard var receipt = open, receipt.end == nil, !state.holdsLid else { return }
        receipt.endedAt = now
        switch state {
        case .stopped(let reason): receipt.end = HoldReceipt.End(rawValue: reason.rawValue)
        default: receipt.end = .finished
        }
        open = receipt
    }

    /// The Mac went to sleep while we believed we were holding: powerd won the race.
    func sleptWhileHolding(now: Date = Date()) {
        guard var receipt = open, receipt.end == nil else { return }
        receipt.endedAt = now
        receipt.end = .sleptAnyway
        open = receipt
    }

    func lidOpened(battery: Int?, now: Date = Date()) {
        guard var receipt = open else { return }
        open = nil
        receipt.openedAt = now
        receipt.batteryAtOpen = battery
        // A lid shut for a moment is not worth a receipt.
        guard now.timeIntervalSince(receipt.closedAt) >= 60 else { return }
        last = receipt
    }

    func markRead() {
        guard var receipt = last, !receipt.read else { return }
        receipt.read = true
        last = receipt
    }

    // MARK: Missed moment

    func lidClosingWhileOff(workingApp: String?, now: Date = Date()) {
        candidate = workingApp.map { MissedMoment(app: $0, at: now) }
    }

    func macSlept(now: Date = Date()) {
        if let candidate, now.timeIntervalSince(candidate.at) < 120 { missed = candidate }
        candidate = nil
    }

    func lidOpenedWhileOff() { candidate = nil }
    func dismissMissed() { missed = nil }

    // MARK: Storage

    private func save<T: Codable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    private static func load<T: Codable>(_ key: String, from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

extension AwakeText {
    /// "Cursor worked 47 min, finished 02:14. Battery 82 → 64 %."
    static func receipt(_ receipt: HoldReceipt) -> [String] {
        let who = receipt.titles.isEmpty ? "Your Mac" : list(receipt.titles)
        let works = receipt.titles.count > 1 ? "were" : "was"
        var lines: [String] = []
        if let end = receipt.end, let endedAt = receipt.endedAt {
            let length = duration(endedAt.timeIntervalSince(receipt.closedAt))
            switch end {
            case .finished: lines.append("\(who) kept your Mac awake for \(length), until \(clock(endedAt)). Then it slept.")
            case .batteryFloor: lines.append("Stopped at \(clock(endedAt)) because the battery was low. \(who) \(works) still going.")
            case .tooHot: lines.append("Stopped at \(clock(endedAt)) because your Mac was hot. \(who) \(works) still going.")
            case .timeCap: lines.append("Stopped at \(clock(endedAt)) after 8 hours on battery.")
            case .lowPowerMode: lines.append("Stopped at \(clock(endedAt)) when Low Power Mode came on.")
            case .chargerOnly: lines.append("Stopped at \(clock(endedAt)) when the charger was unplugged.")
            case .userLetItSleep: lines.append("You let it sleep at \(clock(endedAt)).")
            case .sleptAnyway: lines.append("Your Mac slept at \(clock(endedAt)) although Shut was holding it. \(who) \(works) paused.")
            }
        } else if let openedAt = receipt.openedAt {
            lines.append("\(who) kept your Mac awake for \(duration(openedAt.timeIntervalSince(receipt.closedAt))), the whole time the lid was shut.")
        }
        if let from = receipt.batteryAtClose, let to = receipt.batteryAtOpen, from != to {
            lines.append("Battery \(from) → \(to) %.")
        }
        return lines
    }

    static func missed(_ moment: MissedMoment) -> String {
        "\(moment.app) was working when you shut the lid at \(clock(moment.at)), and your Mac slept"
    }

    private static func list(_ titles: [String]) -> String {
        switch titles.count {
        case 1: return titles[0]
        case 2: return "\(titles[0]) and \(titles[1])"
        default: return "\(titles[0]) and \(titles.count - 1) others"
        }
    }
}
