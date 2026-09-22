import XCTest
@testable import StayAwake

/// Not a test of the code but a look at this Mac through it: what the real reads return
/// right now. Asserts nothing; skipped unless SHUT_PROBE=1, so the suite never depends on
/// what the machine happens to be doing.
@MainActor
final class LiveProbeTests: XCTestCase {
    func testWhatShutSeesRightNow() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SHUT_PROBE"] == "1", "set SHUT_PROBE=1 to look")
        let raw = AssertionMirror.readAssertions()
        print("PROBE raw assertions: \(raw.count)")
        for assertion in raw { print("PROBE   \(assertion)") }
        let mirror = AssertionMirror(defaults: nil)
        mirror.start()
        let owners = mirror.refresh(force: true)
        print("PROBE owners: \(owners.map { "\($0.app.name) [\($0.app.bundleID)] tool=\($0.tool ?? "-") cli=\($0.viaCommandLine) dev=\($0.app.isDeveloperTool)" })")
        print("PROBE reasons: \(mirror.reasons.map { "\($0.title) tool=\($0.tool ?? "-")" })")
        print("PROBE pending: \(mirror.pendingApps.map(\.name))")
        print("PROBE power: \(PowerSourceMonitor.read())")
    }
}
