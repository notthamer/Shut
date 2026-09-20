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

    /// Offered once. Someone who switched it off is told so, not sold to again.
    func testTheBarStopsOfferingAfterItWasSwitchedOff() {
        let never = status(.off)
        XCTAssertEqual(never.sentence, "Keep working with the lid shut")
        XCTAssertEqual(never.action, .turnOn)
        let switchedOff = AwakeText.status(state: .off, reasons: [], conditions: plugged, limits: limits,
                                           canUndo: false, everTurnedOn: true, now: t0)
        XCTAssertEqual(switchedOff.sentence, "Off · lid sleeps as usual")
        XCTAssertNil(switchedOff.action)
        XCTAssertEqual(switchedOff.dot, .idle)
    }

    func testTheMenuBarBadgeSaysWhatTheLidWillDo() {
        func badge(_ state: HoldState, _ conditions: PowerConditions? = nil) -> AwakeText.Dot {
            AwakeText.badge(state: state, conditions: conditions ?? plugged, limits: limits)
        }
        XCTAssertEqual(badge(.off), .idle)
        XCTAssertEqual(badge(.ready), .idle)
        XCTAssertEqual(badge(.holding), .holding)
        XCTAssertEqual(badge(.holding, PowerConditions(onCharger: false, batteryPercent: 23)), .warning)
        XCTAssertEqual(badge(.grace(until: t0)), .winding)
        XCTAssertEqual(badge(.stopped(.tooHot)), .warning)
        XCTAssertEqual(badge(.stopped(.userLetItSleep)), .idle, "the user's own choice is not a warning")
    }

    /// The offer is made a few times, then the bar keeps its name and stops asking.
    func testTheBarStopsOfferingOnceTheOfferHasBeenSeen() {
        let seen = AwakeText.status(state: .off, reasons: [], conditions: plugged, limits: limits,
                                    canUndo: false, offerIt: false, now: t0)
        XCTAssertEqual(seen.sentence, "Stay awake with the lid shut")
        XCTAssertNil(seen.action)
    }

    /// The trigger row says who is at work, once, with the running time where there is one.
    func testTheLiveLineOfATrigger() {
        let claude = HoldReason(id: "working:cursor", kind: .working, title: "Cursor", tool: "Claude Code", since: t0)
        XCTAssertEqual(AwakeText.live([claude], now: t0.addingTimeInterval(47 * 60)), "Claude Code in Cursor · 47 min")
        XCTAssertEqual(AwakeText.live([work()], now: t0.addingTimeInterval(120)), "Cursor · 2 min")
        XCTAssertEqual(AwakeText.live([work(), work("Terminal")], now: t0), "Cursor and 1 more")
        let display = HoldReason(id: "display:x", kind: .display, title: "Studio Display", since: t0)
        XCTAssertEqual(AwakeText.live([display], now: t0), "Studio Display")
        XCTAssertNil(AwakeText.live([], now: t0))
    }

    func testLimitsSummarySaysTheOnesWorthKnowing() {
        XCTAssertEqual(AwakeText.limitsSummary(batteryFloor: 20, lockWhenShut: true, chargerOnly: false),
                       "Sleeps at 20 % battery · locks when shut")
        XCTAssertEqual(AwakeText.limitsSummary(batteryFloor: 20, lockWhenShut: false, chargerOnly: true), "Charger only")
    }

    /// Open eyes mean the Mac stays awake; the little performance is a pure function of time.
    func testTheEyesSayWhatTheLidWillDo() {
        XCTAssertEqual(AwakeEyes.Mood(.holding, isOn: true), .awake)
        XCTAssertEqual(AwakeEyes.Mood(.warning, isOn: true), .awake)
        XCTAssertEqual(AwakeEyes.Mood(.winding, isOn: true), .drowsy)
        XCTAssertEqual(AwakeEyes.Mood(.idle, isOn: true), .shut)
        XCTAssertEqual(AwakeEyes.Mood(.idle, isOn: false), .asleep)
        XCTAssertEqual(AwakeEyes.frame(.awake, at: 1), .downRight, "resting: looking at the words")
        XCTAssertEqual(AwakeEyes.frame(.awake, at: 603.2), .upRight)
        XCTAssertEqual(AwakeEyes.frame(.awake, at: 3.6), .upLeft)
        XCTAssertEqual(AwakeEyes.frame(.awake, at: 4.0), .downLeft)
        XCTAssertEqual(AwakeEyes.frame(.awake, at: 5.5), .shut, "a blink")
        XCTAssertEqual(AwakeEyes.frame(.drowsy, at: 2), .shut)
        XCTAssertEqual(AwakeEyes.restingFrame(.asleep), .asleep)
        XCTAssertEqual(AppAssets.eyes.map(\.count), [64, 64, 64, 64, 20, 20], "inked pixels per frame, counted from the sheet")
        XCTAssertTrue(AppAssets.eyes.allSatisfy { frame in frame.allSatisfy { (0..<16).contains(Int($0.x)) && (0..<12).contains(Int($0.y)) } })
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

    /// Bad news is marked so it can be set in Saffron; the Option hint only rides on a
    /// caption that says the Mac will stay awake, and only while it is still being taught.
    func testTheClosingCaptionKnowsBadNewsAndWhenToTeachOption() {
        let holding = AwakeText.closingCaption(state: .holding, reasons: [work()], conditions: plugged, teachOption: true)
        XCTAssertEqual(holding, AwakeText.Caption(text: "Staying awake · Cursor is working", warning: false,
                                                  hint: "Hold ⌥ to let it sleep instead"))
        XCTAssertNil(AwakeText.closingCaption(state: .holding, reasons: [work()], conditions: plugged, teachOption: false)?.hint)
        let low = AwakeText.closingCaption(state: .stopped(.batteryFloor), reasons: [work()],
                                           conditions: PowerConditions(onCharger: false, batteryPercent: 18), teachOption: true)
        XCTAssertEqual(low?.warning, true)
        XCTAssertNil(low?.hint, "nothing to flip: the limit wins")
        XCTAssertEqual(AwakeText.closingCaption(state: .stopped(.userLetItSleep), reasons: [work()], conditions: plugged,
                                                teachOption: true)?.warning, false, "the user's own choice is not bad news")
        XCTAssertNil(AwakeText.closingCaption(state: .ready, reasons: [], conditions: plugged, teachOption: true))
    }

    func testDurations() {
        XCTAssertEqual(AwakeText.duration(20), "<1 min")
        XCTAssertEqual(AwakeText.duration(47 * 60), "47 min")
        XCTAssertEqual(AwakeText.duration(2 * 3600), "2 h")
        XCTAssertEqual(AwakeText.duration(2 * 3600 + 5 * 60), "2 h 5 min")
    }
}

/// The receipt and the missed moment: bookkeeping on lid and hold events.
@MainActor
final class HoldJournalTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    private func journal() -> HoldJournal { HoldJournal(defaults: UserDefaults(suiteName: "Journal-\(UUID().uuidString)")!) }
    private let cursor = HoldReason(id: "working:cursor", kind: .working, title: "Cursor", since: Date(timeIntervalSinceReferenceDate: 800_000_000))

    func testAHoldThatFinishedWhileShut() throws {
        let journal = journal()
        journal.lidShut(holding: true, reasons: [cursor], battery: 82, now: at(0))
        journal.holdChanged(to: .grace(until: at(3000)), now: at(2700))   // still holding: not an end
        journal.holdChanged(to: .ready, now: at(3000))
        journal.lidOpened(battery: 64, now: at(9000))
        let receipt = try XCTUnwrap(journal.last)
        XCTAssertEqual(receipt.end, .finished)
        let lines = AwakeText.receipt(receipt)
        XCTAssertTrue(lines[0].hasPrefix("Cursor kept your Mac awake for 50 min, until "), lines[0])
        XCTAssertEqual(lines[1], "Battery 82 → 64 %.")
        XCTAssertFalse(receipt.read)
        journal.markRead()
        XCTAssertEqual(journal.last?.read, true)
    }

    func testStoppedByALimitAndSleptAnyway() throws {
        let low = journal()
        low.lidShut(holding: true, reasons: [cursor], battery: 30, now: at(0))
        low.holdChanged(to: .stopped(.batteryFloor), now: at(1200))
        low.lidOpened(battery: 19, now: at(5000))
        XCTAssertEqual(low.last?.end, .batteryFloor)
        XCTAssertTrue(AwakeText.receipt(try XCTUnwrap(low.last))[0].contains("because the battery was low"))

        let raced = journal()
        raced.lidShut(holding: true, reasons: [cursor], battery: 80, now: at(0))
        raced.sleptWhileHolding(now: at(600))
        raced.lidOpened(battery: 80, now: at(4000))
        XCTAssertEqual(raced.last?.end, .sleptAnyway)
        XCTAssertTrue(AwakeText.receipt(try XCTUnwrap(raced.last))[0].contains("although Shut was holding it"), "a failed hold is said, not hidden")
    }

    func testNoReceiptForAnUnheldOrMomentaryClose() {
        let journal = journal()
        journal.lidShut(holding: false, reasons: [], battery: 80, now: at(0))
        journal.lidOpened(battery: 80, now: at(5000))
        XCTAssertNil(journal.last)
        journal.lidShut(holding: true, reasons: [cursor], battery: 80, now: at(6000))
        journal.lidOpened(battery: 80, now: at(6030))
        XCTAssertNil(journal.last)
    }

    func testMissedMomentNeedsBothWorkAndASleep() {
        let journal = journal()
        journal.lidClosingWhileOff(workingApp: nil, now: at(0))
        journal.macSlept(now: at(5))
        XCTAssertNil(journal.missed, "nothing was working")

        journal.lidClosingWhileOff(workingApp: "Cursor", now: at(100))
        journal.macSlept(now: at(110))
        XCTAssertEqual(journal.missed?.app, "Cursor")
        journal.dismissMissed()

        journal.lidClosingWhileOff(workingApp: "Cursor", now: at(1000))
        journal.macSlept(now: at(5000))
        XCTAssertNil(journal.missed, "a sleep an hour later is not about that lid close")
    }
}
