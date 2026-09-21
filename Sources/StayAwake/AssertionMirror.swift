import AppKit
import IOKit.pwr_mgt

/// An app Shut has seen asking macOS to stay awake. The user decides which of
/// these may hold the lid; new tools show up here by themselves, so Shut never
/// needs a list of agents.
public struct SeenApp: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public var name: String
    public var allowed: Bool
    public var lastSeen: Date
    /// The user has said yes or no to this app. Until then, an app that is not allowed
    /// but is asking macOS to stay awake is worth one question; afterwards, never again.
    public var decided: Bool

    public init(bundleID: String, name: String, allowed: Bool, lastSeen: Date, decided: Bool = false) {
        self.bundleID = bundleID; self.name = name; self.allowed = allowed; self.lastSeen = lastSeen; self.decided = decided
    }

    /// Lists saved before `decided` existed load with it false.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try values.decode(String.self, forKey: .bundleID)
        name = try values.decode(String.self, forKey: .name)
        allowed = try values.decode(Bool.self, forKey: .allowed)
        lastSeen = try values.decode(Date.self, forKey: .lastSeen)
        decided = try values.decodeIfPresent(Bool.self, forKey: .decided) ?? false
    }
}

/// One process in the chain from "whoever took the assertion" up to an app.
public struct ProcessNode: Equatable, Sendable {
    public struct App: Equatable, Sendable {
        public let bundleID: String
        public let name: String
        public let isDeveloperTool: Bool
        public init(bundleID: String, name: String, isDeveloperTool: Bool) {
            self.bundleID = bundleID; self.name = name; self.isDeveloperTool = isDeveloperTool
        }
    }
    public let name: String
    public let parent: pid_t
    /// Set when this process is a regular app (Dock icon, windows).
    public let app: App?
    /// The executable's path, for naming a command-line tool.
    public let path: String?
    /// For an interpreter (node, python…): the script it is running, which is the tool.
    public let script: String?
    public init(name: String, parent: pid_t, app: App?, path: String? = nil, script: String? = nil) {
        self.name = name; self.parent = parent; self.app = app; self.path = path; self.script = script
    }
}

/// A power assertion as macOS lists it, reduced to what attribution needs.
public struct RawAssertion: Equatable, Sendable {
    public let pid: pid_t
    public let type: String
    public let name: String
    /// Daemons such as coreaudiod assert on behalf of the app that is playing.
    public let onBehalfOf: pid_t?
    public init(pid: pid_t, type: String, name: String, onBehalfOf: pid_t? = nil) {
        self.pid = pid; self.type = type; self.name = name; self.onBehalfOf = onBehalfOf
    }
}

/// Pure attribution: which app is behind each assertion. `caffeinate` started by
/// an agent in a terminal inside an editor belongs to the editor:
/// caffeinate <- claude <- zsh <- Cursor Helper <- Cursor.
public enum AssertionAttribution {
    /// Assertion types that mean "do not let the system sleep". Display-only
    /// assertions (a video on screen) say nothing about work with the lid shut.
    public static let systemSleepTypes: Set<String> = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"]

    public struct Owner: Equatable, Sendable {
        public let app: ProcessNode.App
        /// True when the assertion came from a command-line tool running inside the
        /// app rather than from the app itself. That is work by nature (a build, an
        /// agent, a download in a terminal), so it is allowed by default.
        public let viaCommandLine: Bool
        public let assertionName: String
        /// The command-line tool that wanted the Mac awake: "Claude Code", "npm".
        public let tool: String?
    }

    /// Processes that are plumbing, not the tool the user would name.
    static let plumbing: Set<String> = ["caffeinate", "zsh", "bash", "sh", "fish", "login", "tmux", "screen", "env", "sudo"]

    /// Friendlier names for a few common tools. Purely cosmetic: anything that asks macOS to
    /// stay awake is recognised whatever it is called, shows under its own name otherwise,
    /// and nothing depends on this list being complete. A key also matches a name that goes
    /// on with "-" or "_" ("codex-aarch64-apple-darwin", "gemini-cli").
    static let friendlyNames: [String: String] = [
        "claude": "Claude Code", "codex": "Codex", "gemini": "Gemini CLI", "aider": "Aider",
        "opencode": "OpenCode", "cursor-agent": "Cursor Agent", "goose": "Goose", "amp": "Amp",
        "copilot": "Copilot CLI", "qwen": "Qwen Code",
    ]

    /// Runtimes that are not the tool: the tool is the script they run.
    static let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3", "ruby", "java"]

    static func friendly(_ name: String) -> String {
        let lower = name.lowercased()
        if let exact = friendlyNames[lower] { return exact }
        // Longest key first, so "cursor-agent" wins over a shorter one that also fits.
        for key in friendlyNames.keys.sorted(by: { $0.count > $1.count })
        where lower.hasPrefix(key + "-") || lower.hasPrefix(key + "_") {
            return friendlyNames[key] ?? name
        }
        return name
    }

    /// A tool's name from its process. Some tools name their binary after their
    /// version (`~/.local/share/claude/versions/2.1.275`), so a name that looks like
    /// a version is replaced by the nearest meaningful folder in the path. A tool that is
    /// a script ("node …/gemini-cli/dist/index.js") is named after the script, or after its
    /// package when the script is called something like index.js.
    static func toolName(processName: String, path: String?, script: String? = nil) -> String {
        var name = processName
        if interpreters.contains(name.lowercased()), let script {
            let generic: Set<String> = ["index", "main", "cli", "bin", "app", "run", "start", "dist", "lib", "build", "src", "out"]
            let parts = script.split(separator: "/").map(String.init)
            let stem = (parts.last ?? "").split(separator: ".").first.map(String.init) ?? ""
            name = ([stem] + parts.dropLast().reversed()).first { !$0.isEmpty && !generic.contains($0.lowercased()) && !$0.hasPrefix("@") } ?? name
        }
        let looksLikeVersion = name.first?.isNumber == true && name.contains(".")
        // The script's own path says more than the runtime's: Cursor's tool is
        // "node …/cursor-agent/versions/2026.08.15-abc/index.js", and node may be anyone's.
        if looksLikeVersion, let location = (interpreters.contains(processName.lowercased()) ? script : nil) ?? path {
            let skip: Set<String> = ["versions", "bin", "libexec", "current"]
            name = location.split(separator: "/").dropLast().reversed()
                .first { !skip.contains($0.lowercased()) && !($0.first?.isNumber ?? true) }.map(String.init) ?? name
        }
        return friendly(name)
    }

    public static func owners(of assertions: [RawAssertion], ownPID: pid_t,
                              lookup: (pid_t) -> ProcessNode?) -> [Owner] {
        var result: [Owner] = []
        for assertion in assertions where systemSleepTypes.contains(assertion.type) {
            let start = assertion.onBehalfOf ?? assertion.pid
            guard start != ownPID else { continue }
            var pid = start, hops = 0
            var tool: String?
            while pid > 1, hops < 16, let node = lookup(pid) {
                if let app = node.app {
                    let viaCommandLine = hops > 0 && assertion.onBehalfOf == nil
                    result.append(Owner(app: app, viaCommandLine: viaCommandLine, assertionName: assertion.name,
                                        tool: viaCommandLine ? tool : nil))
                    break
                }
                // The first process on the way up that is not plumbing is the tool:
                // caffeinate <- claude <- zsh <- Cursor names "claude".
                if tool == nil, !plumbing.contains(node.name), !node.name.hasSuffix("Helper") {
                    tool = toolName(processName: node.name, path: node.path, script: node.script)
                }
                pid = node.parent
                hops += 1
            }
        }
        return result
    }
}

/// "Something is working": mirrors the stay-awake requests of allowed apps.
///
/// macOS posts no notification when one app's assertion comes or goes (the public
/// key fires only when the system-wide total changes), so this is read when it
/// matters: as the lid starts to close, while Shut's window is open, and on the
/// arbiter's slow timer. One IOKit dictionary call each time.
@MainActor
public final class AssertionMirror: HoldSource {
    public private(set) var reasons: [HoldReason] = []
    public private(set) var seenApps: [SeenApp]
    public var onChange: (() -> Void)?

    /// Bundle IDs that were asking macOS to stay awake at the last read.
    public private(set) var askingNow: Set<String> = []

    /// The list as the interface shows it: the apps keeping the Mac awake now, then the ones
    /// asking that may not, then the ones switched on, then the rest; by name within each. Twenty apps in alphabetical order put the one that
    /// matters wherever its name happens to fall.
    public var orderedApps: [SeenApp] { Self.ordered(seenApps, askingNow: askingNow) }

    static func ordered(_ apps: [SeenApp], askingNow: Set<String>) -> [SeenApp] {
        // Keeping the Mac awake right now; asking but not allowed (a decision to make);
        // allowed but quiet; everything else.
        func rank(_ app: SeenApp) -> Int {
            switch (askingNow.contains(app.bundleID), app.allowed) {
            case (true, true): return 0
            case (true, false): return 1
            case (false, true): return 2
            case (false, false): return 3
            }
        }
        return apps.sorted {
            let (a, b) = (rank($0), rank($1))
            return a != b ? a < b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// An app that asked once, months ago, was never switched on and never decided about is
    /// noise. Anything the user touched, or that may hold the lid, is kept for good.
    static let forgetAfter: TimeInterval = 60 * 24 * 3600

    static func pruned(_ apps: [SeenApp], now: Date) -> [SeenApp] {
        apps.filter { $0.allowed || $0.decided || now.timeIntervalSince($0.lastSeen) < forgetAfter }
    }

    /// Apps asking right now that may not hold the lid and that nobody has decided about.
    /// The interface asks once, where the user is already looking; this is how an app
    /// that is not a developer tool (a call, a render, a download) gets found at all.
    public var pendingApps: [SeenApp] {
        seenApps.filter { !$0.allowed && !$0.decided && askingNow.contains($0.bundleID) }
    }

    private let defaults: UserDefaults?
    private static let key = "stayAwake.seenApps"
    private var started = false

    /// Who is asking macOS to stay awake. The real answer is one IOKit call; the tests
    /// give their own so nothing depends on what this Mac happens to be doing.
    private let read: () -> [AssertionAttribution.Owner]

    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        read = {
            AssertionAttribution.owners(of: Self.readAssertions(), ownPID: ProcessInfo.processInfo.processIdentifier,
                                        lookup: Self.lookup)
        }
        seenApps = Self.pruned(defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([SeenApp].self, from: $0) } ?? [], now: Date())
    }

    init(defaults: UserDefaults?, read: @escaping () -> [AssertionAttribution.Owner]) {
        self.defaults = defaults
        self.read = read
        seenApps = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([SeenApp].self, from: $0) } ?? []
    }

    public func start() { started = true; refresh() }

    public func stop() {
        started = false
        if !reasons.isEmpty { reasons = []; onChange?() }
    }

    public func setAllowed(_ bundleID: String, _ allowed: Bool) {
        guard let index = seenApps.firstIndex(where: { $0.bundleID == bundleID }),
              seenApps[index].allowed != allowed || !seenApps[index].decided else { return }
        seenApps[index].allowed = allowed
        seenApps[index].decided = true
        save()
        refresh(force: true)
    }

    /// Reads the system's assertions once. Also used with the feature off, to learn
    /// what was working when a lid closed (the discovery card).
    @discardableResult
    public func refresh(force: Bool = false, now: Date = Date()) -> [AssertionAttribution.Owner] {
        take(read(), force: force, now: now)
    }

    /// The part of `refresh` after the system read, apart so the tests can say who is asking.
    @discardableResult
    func take(_ owners: [AssertionAttribution.Owner], force: Bool = false, now: Date = Date()) -> [AssertionAttribution.Owner] {
        var changed = force
        let asking = Set(owners.map(\.app.bundleID))
        let pendingBefore = pendingApps
        askingNow = asking
        for owner in owners {
            if let index = seenApps.firstIndex(where: { $0.bundleID == owner.app.bundleID }) {
                // Once a minute is plenty for "recently"; avoids a defaults write per read.
                if now.timeIntervalSince(seenApps[index].lastSeen) > 60 { seenApps[index].lastSeen = now; save() }
            } else {
                seenApps.append(SeenApp(bundleID: owner.app.bundleID, name: owner.app.name,
                                        allowed: owner.viaCommandLine || owner.app.isDeveloperTool, lastSeen: now))
                seenApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                save()
                changed = true
            }
        }
        if pendingApps != pendingBefore { changed = true }
        guard started else { if changed { onChange?() }; return owners }

        let allowed = Set(seenApps.filter(\.allowed).map(\.bundleID))
        let existing = Dictionary(reasons.map { ($0.id, $0.since) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        let next: [HoldReason] = owners.compactMap { owner in
            guard allowed.contains(owner.app.bundleID), seen.insert(owner.app.bundleID).inserted else { return nil }
            let id = "working:\(owner.app.bundleID)"
            return HoldReason(id: id, kind: .working, title: owner.app.name,
                              detail: owner.viaCommandLine ? nil : owner.assertionName, tool: owner.tool,
                              bundleID: owner.app.bundleID, since: existing[id] ?? now)
        }.sorted { $0.title < $1.title }
        if next != reasons { reasons = next; changed = true }
        if changed { onChange?() }
        return owners
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(seenApps) else { return }
        defaults.set(data, forKey: Self.key)
    }

    // MARK: System reads

    nonisolated static func readAssertions() -> [RawAssertion] {
        var reference: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&reference) == kIOReturnSuccess,
              let byProcess = reference?.takeRetainedValue() as NSDictionary? else { return [] }
        var result: [RawAssertion] = []
        for (key, value) in byProcess {
            guard let pid = (key as? NSNumber)?.int32Value, let list = value as? [[String: Any]] else { continue }
            for entry in list {
                let details = entry[kIOPMAssertionDetailsKey] as? String
                let behalf = (entry["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value ?? details.flatMap(Self.createdForPID)
                result.append(RawAssertion(pid: pid, type: entry[kIOPMAssertionTypeKey] as? String ?? "",
                                           name: entry[kIOPMAssertionNameKey] as? String ?? "", onBehalfOf: behalf))
            }
        }
        return result
    }

    /// coreaudiod writes "… Created for PID: 1234." into the details.
    nonisolated static func createdForPID(_ details: String) -> pid_t? {
        guard let range = details.range(of: "Created for PID: ") else { return nil }
        return pid_t(details[range.upperBound...].prefix { $0.isNumber })
    }

    nonisolated static func lookup(_ pid: pid_t) -> ProcessNode? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafePointer(to: &info.kp_proc.p_comm) {
            String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
        }
        var app: ProcessNode.App?
        if let running = NSRunningApplication(processIdentifier: pid), running.activationPolicy == .regular,
           let bundleID = running.bundleIdentifier {
            let category = running.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["LSApplicationCategoryType"] as? String }
            app = .init(bundleID: bundleID, name: running.localizedName ?? name,
                        isDeveloperTool: category == "public.app-category.developer-tools")
        }
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let path = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 ? String(cString: pathBuffer) : nil
        let script = AssertionAttribution.interpreters.contains(name.lowercased()) ? scriptArgument(of: pid) : nil
        return ProcessNode(name: name, parent: info.kp_eproc.e_ppid, app: app, path: path, script: script)
    }

    /// The first argument of `pid` that is a path to a script: what an interpreter is running.
    /// KERN_PROCARGS2 is readable for the user's own processes; anything else returns nil.
    nonisolated static func scriptArgument(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        // Layout: argc, the executable's path, padding NULs, then argv[0], argv[1], …
        var strings: [String] = []
        var current: [UInt8] = []
        for byte in buffer[MemoryLayout<Int32>.size..<size] {
            if byte == 0 {
                if !current.isEmpty { strings.append(String(decoding: current, as: UTF8.self)); current = [] }
            } else { current.append(byte) }
            if strings.count > Int(argc) + 1 { break }
        }
        return strings.dropFirst(2).prefix(max(Int(argc) - 1, 0)).first { $0.contains("/") && !$0.hasPrefix("-") }
    }
}
