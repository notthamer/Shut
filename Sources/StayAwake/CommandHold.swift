import Foundation

/// `shut hold`: a lid-proof `caffeinate`, for anything Shut cannot see by itself.
///
///     shut hold -- npm run build        hold while this command runs
///     shut hold --pid 4242              hold while that process lives
///     shut hold start --id render --ttl 2h
///     shut hold stop --id render
///     shut hold status
///
/// Every agent's hook system runs shell commands, so wiring a new tool to Shut is
/// one line in that tool's config, not a release of this app.
///
/// The app listens on a unix socket in its Application Support folder (mode 0600:
/// this user only). One request per connection, one line each way.
public enum HoldSocket {
    public static var path: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shut/hold.sock").path
    }

    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        return address
    }

    /// Sends one line, returns the one-line answer. nil when nobody is listening.
    public static func request(_ line: String, path: String = HoldSocket.path) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = address(path) else { return nil }
        defer { close(fd) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return nil }
        let out = Array((line + "\n").utf8)
        guard write(fd, out, out.count) == out.count else { return nil }
        var buffer = [UInt8](repeating: 0, count: 1024)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { return "" }
        return String(decoding: buffer[0..<count], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The app's end: holds the reasons that commands asked for.
@MainActor
public final class CommandHold: HoldSource {
    public private(set) var reasons: [HoldReason] = []
    public var onChange: (() -> Void)?
    /// Supplies the answer to `status`: "holding · Cursor is working".
    public var statusLine: () -> String = { "" }

    private let path: String
    private var listener: DispatchSourceRead?
    private var listenFD: Int32 = -1
    private var exitWatchers: [String: DispatchSourceProcess] = [:]

    public init(path: String = HoldSocket.path) { self.path = path }

    public func start() {
        guard listener == nil else { return }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = HoldSocket.address(path) else { return }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { close(fd); return }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.accept() } }
        source.resume()
        listener = source
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(path)
        exitWatchers.values.forEach { $0.cancel() }
        exitWatchers = [:]
        if !reasons.isEmpty { reasons = []; onChange?() }
    }

    private func accept() {
        let client = Darwin.accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var buffer = [UInt8](repeating: 0, count: 1024)
        let count = read(client, &buffer, buffer.count)
        guard count > 0 else { return }
        let line = String(decoding: buffer[0..<count], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = Array((handle(line) + "\n").utf8)
        _ = write(client, answer, answer.count)
    }

    /// START \t id \t pid \t ttl seconds \t title   |   STOP \t id   |   STATUS
    func handle(_ line: String, now: Date = Date()) -> String {
        let fields = line.components(separatedBy: "\t")
        switch fields.first {
        case "START" where fields.count >= 5:
            let id = "command:" + Self.clean(fields[1], limit: 60)
            let pid = pid_t(fields[2]) ?? 0
            let ttl = TimeInterval(fields[3]) ?? 0
            let title = Self.clean(fields[4], limit: 40)
            reasons.removeAll { $0.id == id }
            reasons.append(HoldReason(id: id, kind: .command, title: title.isEmpty ? "A command" : title, since: now,
                                      until: ttl > 0 ? now.addingTimeInterval(ttl) : nil))
            watchExit(of: pid, for: id)
            onChange?()
            return "ok " + statusLine()
        case "STOP" where fields.count >= 2:
            remove("command:" + Self.clean(fields[1], limit: 60))
            return "ok " + statusLine()
        case "STATUS":
            return statusLine()
        default:
            return "error unknown request"
        }
    }

    /// A command that was killed never says stop; its exit does.
    private func watchExit(of pid: pid_t, for id: String) {
        exitWatchers.removeValue(forKey: id)?.cancel()
        guard pid > 1 else { return }
        guard kill(pid, 0) == 0 else { remove(id); return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.remove(id) } }
        source.resume()
        exitWatchers[id] = source
    }

    private func remove(_ id: String) {
        exitWatchers.removeValue(forKey: id)?.cancel()
        let before = reasons.count
        reasons.removeAll { $0.id == id }
        if reasons.count != before { onChange?() }
    }

    /// Drops holds whose time is up. The arbiter's deadline timer brings us here.
    public func prune(now: Date = Date()) {
        let expired = reasons.filter { $0.until.map { $0 <= now } ?? false }.map(\.id)
        expired.forEach(remove)
    }

    static func clean(_ text: String, limit: Int) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(limit).map(Character.init))
    }
}

/// The command line's end. Lives here so the client and the server share one protocol.
public enum HoldCommand {
    public static let usage = """
    usage: shut hold -- <command> [arguments]     hold while the command runs
           shut hold --pid <pid>                  hold while that process lives
           shut hold start --id <name> [--ttl 30m|2h|90s]
           shut hold stop --id <name>
           shut hold status
    """

    /// Returns the process exit code.
    public static func run(_ arguments: [String]) -> Int32 {
        guard let first = arguments.first else { print(usage); return 64 }
        switch first {
        case "--":
            return wrap(Array(arguments.dropFirst()))
        case "--pid":
            guard arguments.count >= 2, let pid = pid_t(arguments[1]), kill(pid, 0) == 0 else {
                print("shut hold: no such process"); return 64
            }
            return send("START\tpid:\(pid)\t\(pid)\t0\tProcess \(pid)")
        case "start":
            guard let id = value("--id", in: arguments) else { print(usage); return 64 }
            let ttl = value("--ttl", in: arguments).flatMap(seconds) ?? 0
            return send("START\t\(id)\t0\t\(Int(ttl))\t\(id)")
        case "stop":
            guard let id = value("--id", in: arguments) else { print(usage); return 64 }
            return send("STOP\t\(id)")
        case "status":
            return send("STATUS")
        default:
            print(usage)
            return 64
        }
    }

    private static func send(_ line: String) -> Int32 {
        guard let answer = HoldSocket.request(line) else {
            FileHandle.standardError.write(Data("shut hold: Shut is not running, or Stay awake is off. Open Shut and turn it on.\n".utf8))
            return 69
        }
        print(answer.hasPrefix("ok ") ? String(answer.dropFirst(3)) : answer)
        return answer.hasPrefix("error") ? 1 : 0
    }

    /// Runs the command as a child and holds for as long as it lives. The command
    /// always runs, with or without Shut: an alias must never break a workflow.
    private static func wrap(_ command: [String]) -> Int32 {
        guard let name = command.first else { print(usage); return 64 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        do { try process.run() } catch {
            FileHandle.standardError.write(Data("shut hold: \(error.localizedDescription)\n".utf8))
            return 127
        }
        // The terminal's Ctrl-C goes to the whole foreground group; let the child
        // decide what it means and report its exit.
        signal(SIGINT, SIG_IGN)
        let id = "run:\(process.processIdentifier)"
        let title = (name as NSString).lastPathComponent
        if HoldSocket.request("START\t\(id)\t\(process.processIdentifier)\t0\t\(title)") == nil {
            FileHandle.standardError.write(Data("shut hold: Shut is not running; \(title) runs without a hold.\n".utf8))
        }
        process.waitUntilExit()
        _ = HoldSocket.request("STOP\t\(id)")
        return process.terminationStatus
    }

    private static func value(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// "90s", "30m", "2h", or plain seconds.
    static func seconds(_ text: String) -> TimeInterval? {
        guard let last = text.last else { return nil }
        let multiplier: Double? = last == "s" ? 1 : last == "m" ? 60 : last == "h" ? 3600 : nil
        if let multiplier { return Double(text.dropLast()).map { $0 * multiplier } }
        return Double(text)
    }
}
