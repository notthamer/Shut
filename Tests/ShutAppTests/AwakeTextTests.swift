import XCTest
import StayAwake
@testable import ShutApp

/// The wording is the interface, so it is tested like one.
final class AwakeTextTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let limits = HoldLimits(isOn: true)
    private let plugged = PowerConditions(onCharger: true, batteryPercent: 90)

    private func status(_ state: HoldState, _ reasons: [HoldReason] = [], _ conditions: PowerConditions? = nil,
                        canUndo: Bool = false, after seconds: TimeInterval = 0) -> AwakeText.Status {
        AwakeText.status(state: state, reasons: reasons, conditions: conditions ?? plugged, limits: limits,
                         canUndo: canUndo, now: t0.addingTimeInterval(seconds))
    }

    private func work(_ title: String = "Cursor") -> HoldReason {
        HoldReason(id: "working:\(title)", kind: .working, title: title, since: t0)
    }

    func testTheSentenceNamesTheReason() {
        XCTAssertEqual(status(.holding, [work()], after: 47 * 60).sentence, "Cursor is working · 47 min")
        XCTAssertEqual(status(.holding, [work(), work("Terminal")]).sentence, "2 apps are working")
        let display = HoldReason(id: "display:x", kind: .display, title: "Studio Display", since: t0)
        XCTAssertEqual(status(.holding, [display]).sentence, "Studio Display is connected")
        XCTAssertEqual(status(.holding, [work(), display]).sentence, "2 reasons to stay awake")
    }

    func testEveryStateOffersTheRightAction() {
        XCTAssertEqual(status(.off).action, .turnOn)
        XCTAssertNil(status(.ready).action)
        XCTAssertEqual(status(.holding, [work()]).action, .letItSleep)
        XCTAssertEqual(status(.grace(until: t0.addingTimeInterval(240))).action, .keepAwake)
        XCTAssertEqual(status(.grace(until: t0.addingTimeInterval(240))).sentence, "Finished · sleeping in 4 min")
        XCTAssertEqual(status(.stopped(.userLetItSleep), [work()], canUndo: true).action, .undo)
    }

    func testBatteryWarningBeforeTheFloor() {
        let low = PowerConditions(onCharger: false, batteryPercent: 24)
        let result = status(.holding, [work()], low)
        XCTAssertEqual(result.dot, .warning)
        XCTAssertEqual(result.sentence, "On battery 24 % · sleeps at 20 %")
        XCTAssertEqual(status(.holding, [work()], PowerConditions(onCharger: false, batteryPercent: 60)).dot, .holding)
    }

    func testCaptionOnlyWhenThereIsSomethingToSay() {
        XCTAssertNil(AwakeText.caption(state: .ready, reasons: [], conditions: plugged))
        XCTAssertNil(AwakeText.caption(state: .off, reasons: [work()], conditions: plugged))
        XCTAssertEqual(AwakeText.caption(state: .holding, reasons: [work()], conditions: plugged), "Staying awake · Cursor is working")
        XCTAssertEqual(AwakeText.caption(state: .stopped(.batteryFloor), reasons: [work()],
                                         conditions: PowerConditions(onCharger: false, batteryPercent: 18)),
                       "Sleeping · battery is at 18 %")
    }

    func testDurations() {
        XCTAssertEqual(AwakeText.duration(20), "<1 min")
        XCTAssertEqual(AwakeText.duration(47 * 60), "47 min")
        XCTAssertEqual(AwakeText.duration(2 * 3600), "2 h")
        XCTAssertEqual(AwakeText.duration(2 * 3600 + 5 * 60), "2 h 5 min")
    }
}
