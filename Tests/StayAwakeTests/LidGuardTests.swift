import XCTest
@testable import StayAwake

/// The guard waits for a process to exit and only then restores. Watched here: `/bin/sleep`,
/// and a restore that touches nothing real.
final class LidGuardTests: XCTestCase {
    private func spawnSleep(_ seconds: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        try process.run()
        return process
    }

    func testTheGuardRestoresOnlyOnceTheWatchedProcessIsGone() throws {
        let watched = try spawnSleep("0.6")
        let restored = expectation(description: "restore ran")
        let started = Date()
        var restoredAfter: TimeInterval = 0
        DispatchQueue.global().async {
            LidGuard.watch(watched.processIdentifier) {
                restoredAfter = Date().timeIntervalSince(started)
                restored.fulfill()
            }
        }
        wait(for: [restored], timeout: 5)
        XCTAssertGreaterThan(restoredAfter, 0.4, "not before the process ended")
        XCTAssertFalse(watched.isRunning)
    }

    /// A kill is the case it exists for.
    func testAKilledProcessCounts() throws {
        let watched = try spawnSleep("30")
        let restored = expectation(description: "restore ran")
        DispatchQueue.global().async { LidGuard.watch(watched.processIdentifier) { restored.fulfill() } }
        usleep(150_000)
        kill(watched.processIdentifier, SIGKILL)
        wait(for: [restored], timeout: 5)
    }

    /// Shut died before the guard could even ask: nothing to wait for, everything to restore.
    func testAProcessAlreadyGoneRestoresAtOnce() throws {
        let watched = try spawnSleep("0")
        watched.waitUntilExit()
        let started = Date()
        var ran = false
        LidGuard.watch(watched.processIdentifier) { ran = true }
        XCTAssertTrue(ran)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    /// The script an interpreter is running, read from the real process table: what turns
    /// "node" into "Gemini CLI".
    func testTheScriptAnInterpreterIsRunningCanBeRead() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("shut-probe-\(UUID().uuidString)/gemini-cli/dist/index.sh")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "sleep 5\n".write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        try process.run()
        defer { process.terminate() }
        usleep(150_000)
        let read = try XCTUnwrap(AssertionMirror.scriptArgument(of: process.processIdentifier))
        XCTAssertEqual(read, script.path)
        XCTAssertEqual(AssertionAttribution.toolName(processName: "node", path: nil, script: read), "Gemini CLI")
        XCTAssertNil(AssertionMirror.scriptArgument(of: 1), "launchd is not ours to read")
    }
}
