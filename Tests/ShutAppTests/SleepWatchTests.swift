import StayAwake
import XCTest
@testable import ShutApp

/// A sleep still going, and who held the last one up: read from the two notifications and,
/// once, from `pmset -g log`.
@MainActor
final class SleepWatchTests: XCTestCase {
    static let powerLog = """
    2026-10-20 22:53:42 +0300 PM Client Acks      \tDelays to Sleep notifications: [com.apple.audio.ParrotAudioPlugin is slow(279 ms)] [com.apple.bluetooth.sleep is slow(1534 ms)]
    2026-10-20 22:54:14 +0300 Kernel Client Acks  \tDelays to Sleep notifications: [logioptionsplus_ timed out(30000 ms)] [lghub_agent timed out(30000 ms)] [IOMobileFramebufferShim driver is slow(msg: SetState to 0)(99 ms)]
    2026-10-20 22:54:58 +0300 Kernel Client Acks  \tDelays to Sleep notifications: [logioptionsplus_ timed out(30000 ms)] [lghub_agent timed out(30000 ms)]
    """

    func testTheLineIsReadIntoNames() {
        let delays = SleepDelays.parse(Self.powerLog)
        XCTAssertEqual(delays.map(\.name), ["Logitech Options+", "Logitech G Hub"], "the last line; the driver entry has no milliseconds in the expected place and is not an app")
        XCTAssertEqual(delays.map(\.milliseconds), [30000, 30000])
        XCTAssertTrue(delays.allSatisfy(\.timedOut))
        let slow = SleepDelays.entries(in: "x [com.apple.bluetooth.sleep is slow(1534 ms)] [someagent timed out(30000 ms)]")
        XCTAssertEqual(slow.map(\.name), ["com.apple.bluetooth.sleep", "someagent"], "an unknown name stays as printed")
        XCTAssertEqual(slow.map(\.timedOut), [false, true])
        XCTAssertTrue(SleepDelays.parse("nothing here").isEmpty)
        // Only lines from this sleep on: an old one is not pinned on a sleep that went well.
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        XCTAssertTrue(SleepDelays.parse(Self.powerLog, since: formatter.date(from: "2026-10-20 22:55:00 +0300")).isEmpty)
    }

    func testASlowSleepIsNotedAndAQuickOneClearsIt() {
        let suite = UserDefaults(suiteName: "SleepWatch-\(UUID().uuidString)")!
        let watch = SleepWatch(defaults: suite, powerLog: { Self.powerLog })
        let t0 = Date(timeIntervalSince1970: 1_760_990_040)   // 2026-10-20 22:54:00 +0300, before the lines above
        XCTAssertNil(watch.pendingSince)
        watch.sleepBegan(now: t0)
        XCTAssertNotNil(watch.pendingSince, "between the two notifications the lid does nothing")
        watch.woke(now: t0.addingTimeInterval(31))
        XCTAssertNil(watch.pendingSince)
        let done = expectation(description: "read off the main thread")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(watch.slow?.names, ["Logitech Options+", "Logitech G Hub"])
        XCTAssertEqual(watch.slow?.seconds, 31)
        XCTAssertEqual(SleepWatch(defaults: suite, powerLog: { nil }).slow?.names, watch.slow?.names, "kept for the next launch")

        // A sleep that goes through quickly takes the note down.
        watch.sleepBegan(now: t0.addingTimeInterval(100))
        watch.woke(now: t0.addingTimeInterval(102))
        XCTAssertNil(watch.slow)
        XCTAssertNil(SleepWatch(defaults: suite, powerLog: { nil }).slow)

        // Dismissed by hand, it is gone too.
        watch.sleepBegan(now: t0.addingTimeInterval(200)); watch.woke(now: t0.addingTimeInterval(231))
        let again = expectation(description: "again"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { again.fulfill() }; wait(for: [again], timeout: 2)
        XCTAssertNotNil(watch.slow)
        watch.dismissSlow()
        XCTAssertNil(watch.slow)
    }

    func testTheWords() {
        XCTAssertEqual(AwakeText.sleepPendingHero(seconds: 12).headline, "Your Mac is still going to sleep from the last close.")
        XCTAssertEqual(AwakeText.sleepPendingHero(seconds: 12).detail, "Closing the lid again does nothing until that finishes: 12 s so far.")
        XCTAssertEqual(AwakeText.slowSleepTitle(seconds: 30), "Your Mac takes 30 s to sleep.")
        XCTAssertEqual(AwakeText.slowSleepDetail(names: ["Logitech Options+", "Logitech G Hub"], seconds: 30),
                       "Logitech Options+ and Logitech G Hub did not answer the sleep. Until they do, closing the lid again inside those 30 s does nothing, and the Mac sleeps on its own when they time out. Quit or update them.")
        XCTAssertTrue(AwakeText.slowSleepDetail(names: ["X"], seconds: 30).hasSuffix("Quit or update it."))
        let plugged = PowerConditions(onCharger: true, batteryPercent: 90)
        XCTAssertEqual(AwakeText.tabLine(state: .ready, reasons: [], conditions: plugged, limits: HoldLimits(isOn: true), sleepPendingSeconds: 5, now: Date()), "Still going to sleep")
        XCTAssertEqual(AwakeText.closingCaption(state: .ready, reasons: [], conditions: plugged, teachOption: false, sleepPending: true)?.text, AwakeText.sleepPendingCaption)
        XCTAssertEqual(AwakeText.closingCaption(state: .ready, reasons: [], conditions: plugged, teachOption: false, sleepPending: true)?.warning, true)
        XCTAssertEqual(AwakeText.badge(state: .ready, conditions: plugged, limits: HoldLimits(isOn: false), sleepPending: true), .warning)
    }
}
