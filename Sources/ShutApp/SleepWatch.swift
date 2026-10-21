import AppKit
import Combine
import Foundation

/// The one thing about sleep that macOS never says on screen: a lid close starts a sleep
/// "transaction", and until every app and driver has answered it (up to 30 s), a lid
/// lifted and closed again does nothing, and the Mac sleeps on its own when the laggard
/// times out, lid open or not. Shut sees the two notifications that bracket the transaction
/// and says so; and after a slow one it reads `pmset -g log` once to name who held it up.
///
/// Some laggards are known by name before any sleep: background agents that never answer
/// (Logitech's, so far), which Shut can see running and offer to stop, in the user's own
/// launchd domain, so the first close is not the one that teaches the lesson.
@MainActor
final class SleepWatch: ObservableObject {
    /// A sleep began and has not finished (no wake yet).
    @Published private(set) var pendingSince: Date?
    /// The last slow sleep: who did not answer, and when. Shown until dismissed, or until a
    /// sleep goes through quickly again.
    @Published private(set) var slow: SlowSleep?
    /// The known laggards running now, in the table's order. Read at start and when an app
    /// launches or quits: never a poll.
    @Published private(set) var running: [Laggard] = []

    /// A process known to hold every sleep open until macOS gives up on it (30 s): its plain
    /// name, the bundle id its agent runs under, and the launchd label that starts it. The
    /// table grows as reports come in; the labels are in /Library/LaunchAgents.
    struct Laggard: Equatable, Identifiable {
        let name: String
        /// The name on a button: "Stop G Hub".
        let short: String
        let bundleID: String
        let label: String
        var id: String { bundleID }
    }
    nonisolated static let knownLaggards: [Laggard] = [
        Laggard(name: "Logitech Options+", short: "Options+", bundleID: "com.logi.cp-dev-mgr", label: "com.logi.cp-dev-mgr"),
        Laggard(name: "Logitech G Hub", short: "G Hub", bundleID: "com.logi.ghub.agent", label: "com.logi.ghub"),
    ]

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
    /// The bundle ids running now; a test hands in its own set.
    private let runningBundleIDs: () -> Set<String>
    /// Stops a laggard; a test hands in one that only records the call.
    private let stopper: (Laggard) -> Void
    /// Laggards the user chose to leave alone (the × on the card), by bundle id. Saved.
    private var ignored: Set<String> { didSet { defaults.set(Array(ignored).sorted(), forKey: "sleep.laggardsIgnored") } }
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, powerLog: (() -> String?)? = nil,
         runningBundleIDs: (() -> Set<String>)? = nil, stopper: ((Laggard) -> Void)? = nil) {
        self.defaults = defaults
        self.powerLog = powerLog ?? Self.readPowerLog
        self.runningBundleIDs = runningBundleIDs ?? Self.readRunningBundleIDs
        self.stopper = stopper ?? Self.stopWithLaunchd
        ignored = Set(defaults.stringArray(forKey: "sleep.laggardsIgnored") ?? [])
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
        // The laggards: once now, and again whenever an app comes or goes.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshLaggards() }
            })
        }
        refreshLaggards()
    }

    // MARK: The laggards, known in advance

    /// Which known laggards are running and not waved away.
    func refreshLaggards() {
        let ids = runningBundleIDs()
        let now = Self.knownLaggards.filter { ids.contains($0.bundleID) && !ignored.contains($0.bundleID) }
        if now != running { running = now }
    }

    /// Stops a laggard, off the main thread, and looks again once it has had a moment to go.
    func stop(_ laggard: Laggard) {
        let stop = stopper
        Log.app.notice("stopping \(laggard.name, privacy: .public), which holds every sleep for 30 s")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            stop(laggard)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.refreshLaggards() }
        }
    }

    /// The × on the card: this one is the user's business. Kept across launches.
    func ignore(_ laggard: Laggard) {
        ignored.insert(laggard.bundleID)
        refreshLaggards()
    }

    /// Every laggard's bundle id that is running, read from the workspace. No process list
    /// is walked: one lookup per known name, and there are two.
    nonisolated private static func readRunningBundleIDs() -> Set<String> {
        Set(knownLaggards.map(\.bundleID).filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty })
    }

    /// Out of launchd for this session and the next login, then out of memory: `launchctl
    /// bootout` and `disable` in the user's own gui domain, which need no password, and a
    /// terminate for a process that outlives its job. Launching the app brings it back, with
    /// its agent, so nothing here is final.
    nonisolated private static func stopWithLaunchd(_ laggard: Laggard) {
        let service = "gui/\(getuid())/\(laggard.label)"
        run("/bin/launchctl", ["bootout", service])
        run("/bin/launchctl", ["disable", service])
        DispatchQueue.main.async {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: laggard.bundleID) { app.terminate() }
        }
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
        process.waitUntilExit()
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
