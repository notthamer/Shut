import AppKit
import Combine
import Foundation

/// The one thing about sleep that macOS never says on screen: a lid close starts a sleep
/// "transaction", and until every app and driver has answered it (up to 30 s), a lid
/// lifted and closed again does nothing, and the Mac sleeps on its own when the laggard
/// times out, lid open or not. Shut sees the two notifications that bracket the transaction
/// and says so; and after a slow one it reads `pmset -g log` once to name who held it up.
@MainActor
final class SleepWatch: ObservableObject {
    /// A sleep began and has not finished (no wake yet).
    @Published private(set) var pendingSince: Date?
    /// The last slow sleep: who did not answer, and when. Shown until dismissed, or until a
    /// sleep goes through quickly again.
    @Published private(set) var slow: SlowSleep?

    struct SlowSleep: Codable, Equatable {
        var names: [String]
        var seconds: Int
        var at: Date
    }

    /// Longer than this from the sleep's start to its end is a sleep held up by someone.
    static let slowAfter: TimeInterval = 10
    private let defaults: UserDefaults
    /// Runs `pmset -g log` and returns its text; a test hands in a line of its own.
    private let powerLog: () -> String?
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, powerLog: (() -> String?)? = nil) {
        self.defaults = defaults
        self.powerLog = powerLog ?? Self.readPowerLog
        if let data = defaults.data(forKey: "sleep.slow"), let saved = try? JSONDecoder().decode(SlowSleep.self, from: data) { slow = saved }
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleepBegan() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.woke() }
        })
    }

    func sleepBegan(now: Date = Date()) {
        pendingSince = now
    }

    /// The transaction is over. Took long: find out who, off the main thread, once.
    func woke(now: Date = Date()) {
        guard let since = pendingSince else { return }
        pendingSince = nil
        let took = now.timeIntervalSince(since)
        if took < Self.slowAfter {
            if slow != nil { slow = nil; defaults.removeObject(forKey: "sleep.slow"); Log.app.info("sleep went through in \(Int(took)) s; the note about a slow sleep is gone") }
            return
        }
        let read = powerLog
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let delays = read().map { SleepDelays.parse($0, since: since.addingTimeInterval(-60)) } ?? []
            DispatchQueue.main.async { self?.noteSlowSleep(delays, took: took, now: now) }
        }
    }

    private func noteSlowSleep(_ delays: [SleepDelays.Delay], took: TimeInterval, now: Date) {
        let culprits = delays.filter(\.timedOut).map(\.name)
        guard !culprits.isEmpty else { return }
        let note = SlowSleep(names: culprits, seconds: Int(took.rounded()), at: now)
        slow = note
        defaults.set(try? JSONEncoder().encode(note), forKey: "sleep.slow")
        Log.app.notice("sleep took \(Int(took)) s: held up by \(culprits.joined(separator: ", "), privacy: .public)")
    }

    func dismissSlow() {
        slow = nil
        defaults.removeObject(forKey: "sleep.slow")
    }

    /// `pmset -g log`, as any user may read it. One run per slow wake, never a poll.
    nonisolated private static func readPowerLog() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "log"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// The "Delays to Sleep notifications" line of `pmset -g log`, read into names.
enum SleepDelays {
    struct Delay: Equatable {
        /// Plain where known ("Logitech Options+"), the process name otherwise.
        let name: String
        let milliseconds: Int
        let timedOut: Bool
    }

    /// The names macOS prints are process names cut short; the ones seen so far, spelled out.
    static let knownNames: [String: String] = [
        "logioptionsplus_": "Logitech Options+",
        "logioptionsplus_agent": "Logitech Options+",
        "lghub_agent": "Logitech G Hub",
        "lghub_updater": "Logitech G Hub",
    ]

    /// The last "Delays to Sleep notifications" line at or after `since`, as delays.
    static func parse(_ log: String, since: Date? = nil) -> [Delay] {
        let lines = log.split(separator: "\n").filter { $0.contains("Delays to Sleep notifications") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let line = lines.last { line in
            guard let since, let date = formatter.date(from: String(line.prefix(25))) else { return true }
            return date >= since
        }
        guard let line else { return [] }
        return entries(in: String(line))
    }

    /// "[logioptionsplus_ timed out(30000 ms)] [com.apple.bluetooth.sleep is slow(1534 ms)]"
    static func entries(in line: String) -> [Delay] {
        var delays: [Delay] = []
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "["), let close = rest[open...].firstIndex(of: "]") {
            let entry = rest[rest.index(after: open)..<close]
            rest = rest[rest.index(after: close)...]
            let timedOut = entry.contains(" timed out(")
            guard timedOut || entry.contains(" is slow(") else { continue }
            let name = String(entry[..<(entry.range(of: timedOut ? " timed out(" : " is slow(")!.lowerBound)])
            let digits = entry.drop { !$0.isNumber }.prefix { $0.isNumber }
            delays.append(Delay(name: knownNames[name] ?? name, milliseconds: Int(digits) ?? 0, timedOut: timedOut))
        }
        return delays
    }
}
