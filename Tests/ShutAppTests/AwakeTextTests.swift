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

    /// One dial instead of Off / 1 h / 4 h / ∞.
    func testTheKeepAwakeDial() {
        func stop(_ minutes: Double) -> Int { AwakeText.manualDurations.firstIndex(of: minutes * 60)! + 1 }
        XCTAssertEqual(AwakeText.manualValue(stop: 0), "Off")
        XCTAssertEqual(AwakeText.manualValue(stop: 1), "5 min", "the shortest: a quick errand")
        XCTAssertEqual(AwakeText.manualValue(stop: stop(60)), "1 h")
        XCTAssertEqual(AwakeText.manualValue(stop: stop(90)), "90 min")
        XCTAssertEqual(AwakeText.manualValue(stop: stop(720)), "12 h")
        XCTAssertEqual(AwakeText.manualValue(stop: AwakeText.manualLastStop), "∞")
        // The thumb covers the time left, and drifts towards Off as it runs out.
        XCTAssertEqual(AwakeText.manualStop(remaining: 3600), stop(60))
        XCTAssertEqual(AwakeText.manualStop(remaining: 40 * 60), stop(45), "40 min left sits at 45 min")
        XCTAssertEqual(AwakeText.manualStop(remaining: 40), 1)
        XCTAssertEqual(AwakeText.manualStop(remaining: nil), AwakeText.manualLastStop)
        XCTAssertEqual(AwakeText.manualStop(remaining: 30 * 3600), AwakeText.manualLastStop - 1, "a long command-line hold still fits on the dial")
        // The caption says it whole.
        let until = t0.addingTimeInterval(72 * 60)
        XCTAssertEqual(AwakeText.manualCaption(stop: stop(90), running: true, until: until, now: t0),
                       "1 h 12 min left, then back to automatic.", "the answer beside it has the time it ends")
        XCTAssertEqual(AwakeText.manualCaption(stop: stop(60), running: false, until: nil, now: t0),
                       "Until \(AwakeText.clock(t0.addingTimeInterval(3600))), then back to automatic.")
        XCTAssertTrue(AwakeText.manualCaption(stop: 0, running: false, until: nil, now: t0).hasPrefix("Drag to pick"))
        XCTAssertEqual(AwakeText.manualCaption(stop: AwakeText.manualLastStop, running: true, until: nil, now: t0),
                       "Awake until you choose Automatically.")
    }

    /// "Automatically" says what it will do, out of the rules that are on.
    func testAutomaticSaysItsRules() {
        XCTAssertEqual(AwakeText.automaticSummary(working: true, display: false, pickedApps: 0),
                       "Stays awake while an app is busy, and sleeps by itself when that ends.")
        XCTAssertEqual(AwakeText.automaticSummary(working: true, display: true, pickedApps: 2),
                       "Stays awake while an app is busy, a display is connected or an app you picked is open, and sleeps by itself when that ends.")
        XCTAssertTrue(AwakeText.automaticSummary(working: false, display: false, pickedApps: 0).hasPrefix("No rule is switched on"))
    }

    /// Under Automatically, the box names who is keeping the Mac awake.
    func testTheBoxNamesWhoIsKeepingItAwake() {
        let now = t0.addingTimeInterval(47 * 60)
        let agent = HoldReason(id: "working:cursor", kind: .working, title: "Cursor", tool: "Claude Code", since: t0)
        XCTAssertEqual(AwakeText.holder(agent, now: now), .init(name: "Claude Code in Cursor", detail: "busy · 47 min"))
        XCTAssertEqual(AwakeText.holder(work("Xcode"), now: now), .init(name: "Xcode", detail: "busy · 47 min"))
        let display = HoldReason(id: "display:x", kind: .display, title: "Studio Display", since: t0)
        XCTAssertEqual(AwakeText.holder(display, now: now), .init(name: "Studio Display", detail: "connected"))
        let open = HoldReason(id: "app:x", kind: .appOpen, title: "Final Cut Pro", since: t0)
        XCTAssertEqual(AwakeText.holder(open, now: now), .init(name: "Final Cut Pro", detail: "open"))
        XCTAssertNil(AwakeText.moreHolders(3))
        XCTAssertEqual(AwakeText.moreHolders(5), "and 2 more")
    }

    /// 18 % with the level at 20 %: every surface says the battery is under it, with both numbers.
    func testABatteryUnderTheLevelIsSaidPlainly() {
        let low = PowerConditions(onCharger: false, batteryPercent: 18)
        let manual = HoldReason(id: "manual", kind: .manual, title: "You", since: t0, until: t0.addingTimeInterval(3600))
        for (state, reasons) in [(HoldState.ready, [HoldReason]()), (.stopped(.batteryFloor), [manual])] {
            let hero = AwakeText.hero(state: state, reasons: reasons, conditions: low, limits: limits, now: t0)
            XCTAssertEqual(hero.headline, "Closing the lid will sleep your Mac.")
            XCTAssertEqual(hero.detail, "Plug in and it can stay awake again.", "the card under it says too low, with the numbers")
            XCTAssertTrue(hero.showsCards, "the card carries the two numbers")
            XCTAssertEqual(AwakeText.tabLine(state: state, reasons: reasons, conditions: low, limits: limits, now: t0), "Battery 18 % · too low")
            XCTAssertEqual(status(state, reasons, low).sentence, "Battery 18 % is under your 20 % limit · lid will sleep your Mac")
            let rows = AwakeWarnings(state: state, conditions: low, limits: limits, now: t0).rows
            XCTAssertEqual(rows.map(\.title), ["Battery 18 % · too low"])
            XCTAssertEqual(rows.first?.subtitle, "It stays awake only above 20 %.")
            XCTAssertEqual(rows.first?.meter, AwakeText.BatteryTooLow(percent: 18, floor: 20))
        }
        XCTAssertEqual(AwakeText.manualBlocked(.batteryFloor), "Not right now: the battery is too low. The time keeps counting.")
        // Exactly at the level counts as under it; one above does not; nor does any level on the charger.
        XCTAssertNotNil(AwakeText.batteryTooLow(conditions: PowerConditions(onCharger: false, batteryPercent: 20), limits: limits))
        XCTAssertNil(AwakeText.batteryTooLow(conditions: PowerConditions(onCharger: false, batteryPercent: 21), limits: limits))
        XCTAssertNil(AwakeText.batteryTooLow(conditions: PowerConditions(onCharger: true, batteryPercent: 5), limits: limits))
        XCTAssertNil(AwakeText.batteryTooLow(conditions: PowerConditions(onCharger: false, batteryPercent: nil), limits: limits), "a Mac with no battery")
        XCTAssertEqual(AwakeText.hero(state: .ready, reasons: [], conditions: plugged, limits: limits, now: t0).detail, "Nothing is keeping it awake right now.")
    }

    /// The page's headline is always the answer to "what will closing the lid do?".
    func testTheHeroAlwaysAnswersWhatTheLidWillDo() {
        func hero(_ state: HoldState, _ reasons: [HoldReason] = [], watching: Bool = true) -> AwakeText.Hero {
            AwakeText.hero(state: state, reasons: reasons, conditions: plugged, limits: limits, watchingApps: watching, now: t0)
        }
        let sleeps = "Closing the lid will sleep your Mac."
        let stays = "Closing the lid keeps your Mac awake."
        XCTAssertEqual(hero(.ready).headline, sleeps)
        XCTAssertEqual(hero(.ready).detail, "Nothing is keeping it awake right now.")
        XCTAssertTrue(hero(.ready, watching: false).detail.contains("apps are not being watched"), "the main reason is off: say so")
        XCTAssertEqual(hero(.holding, [work()]).headline, stays)
        // Who is working is said once, in the box under Automatically; the answer says only when it ends.
        XCTAssertEqual(hero(.holding, [work()]).detail, "It sleeps by itself when that ends, or at 20\u{00A0}% battery.")
        XCTAssertEqual(hero(.holding, [work(), work("Terminal")]).detail, "It sleeps by itself when they end, or at 20\u{00A0}% battery.")
        // With a set time running there is no box, so the answer still counts them.
        let manual = HoldReason(id: "manual", kind: .manual, title: "You", since: t0, until: t0.addingTimeInterval(3600))
        XCTAssertTrue(hero(.holding, [manual, work()]).detail.hasPrefix("2 things are keeping it awake."))
        // A set time: when it ends is the headline, beside the eyes.
        XCTAssertEqual(hero(.holding, [manual]).headline, "Your Mac stays awake until \(AwakeText.clock(t0.addingTimeInterval(3600))).")
        XCTAssertEqual(hero(.holding, [manual]).detail, "Lid shut or open. It also sleeps at 20\u{00A0}% battery.")
        let forever = HoldReason(id: "manual", kind: .manual, title: "You", since: t0)
        XCTAssertEqual(hero(.holding, [forever]).headline, stays)
        XCTAssertEqual(AwakeText.live([work()], named: false, now: t0), "At work now")
        XCTAssertEqual(hero(.grace(until: t0.addingTimeInterval(240))).headline, "Your Mac will sleep in 4 min.")
        XCTAssertEqual(hero(.stopped(.tooHot)).headline, sleeps)
        XCTAssertTrue(hero(.stopped(.tooHot)).detail.hasSuffix("That limit always wins."))
        XCTAssertEqual(hero(.stopped(.userLetItSleep), [work()]).headline, sleeps)
        for state in [HoldState.ready, .holding, .stopped(.batteryFloor)] {
            XCTAssertFalse(hero(state, [work()]).headline.contains("Nothing is working"), "it read like an error")
        }
    }

    /// A button shows where it leads, and says what it will do.
    func testActionsSayWhereTheyLead() {
        XCTAssertEqual(AwakeText.Action.letItSleep.outcome, .sleeps)
        XCTAssertEqual(AwakeText.Action.notThisApp.outcome, .sleeps)
        for action in [AwakeText.Action.keepAwake, .undo, .allow] { XCTAssertEqual(action.outcome, .staysAwake) }
        XCTAssertEqual(AwakeText.Action.turnOn.outcome, .neutral)
        XCTAssertEqual(AwakeText.Action.letItSleep.consequence(who: "Claude Code"),
                       "Just this once, even though Claude Code is working.", "the headline above already says what the lid will do")
        XCTAssertEqual(AwakeText.Action.letItSleep.consequence(who: nil), "Just this once.")
        XCTAssertEqual(AwakeText.Action.allow.consequence(who: "Zoom"), "Zoom may keep your Mac awake, now and from now on.")
        XCTAssertEqual(AwakeText.Action.undo.title, "Keep it awake", "\"Undo\" did not say what it undid")
        XCTAssertNil(AwakeText.Action.undo.consequence(who: nil), "its title says it whole")
    }

    /// The Stay awake tab's second line: its state in a few words.
    func testTheTabSaysWhatStayAwakeIsDoing() {
        func line(_ state: HoldState, _ reasons: [HoldReason] = [], _ conditions: PowerConditions? = nil,
                  pending: String? = nil, after seconds: TimeInterval = 0) -> String {
            AwakeText.tabLine(state: state, reasons: reasons, conditions: conditions ?? plugged, limits: limits,
                              pendingApp: pending, now: t0.addingTimeInterval(seconds))
        }
        XCTAssertEqual(line(.off), "Off")
        XCTAssertEqual(line(.ready), "Lid will sleep your Mac")
        XCTAssertEqual(line(.ready, pending: "Zoom"), "Zoom is asking")
        let claude = HoldReason(id: "working:cursor", kind: .working, title: "Cursor", tool: "Claude Code", since: t0)
        XCTAssertEqual(line(.holding, [claude], after: 47 * 60), "Claude Code · 47 min")
        XCTAssertEqual(line(.holding, [claude, work("Terminal")]), "2 things keep it awake")
        XCTAssertEqual(line(.holding, [HoldReason(id: "display:x", kind: .display, title: "Studio Display", since: t0)]), "Studio Display")
        XCTAssertEqual(line(.holding, [claude], PowerConditions(onCharger: false, batteryPercent: 24)), "Battery 24 % · sleeps at 20 %")
        XCTAssertEqual(line(.grace(until: t0.addingTimeInterval(240))), "Sleeping in 4 min")
        XCTAssertEqual(line(.stopped(.tooHot)), "Too hot · will sleep")
        XCTAssertEqual(line(.stopped(.userLetItSleep), [claude]), "Letting it sleep")
        for text in [line(.ready), line(.holding, [claude, work("Terminal")]), line(.stopped(.lowPowerMode))] {
            XCTAssertLessThanOrEqual(text.count, 28, "it has to fit a tab: \(text)")
        }
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
        XCTAssertEqual(AwakeEyes.frame(.awake, at: 5.5), .blink)
        XCTAssertEqual(AwakeEyes.frame(.drowsy, at: 2), .blink, "winding down is still awake")
        XCTAssertEqual(AwakeEyes.restingFrame(.shut), .shut)
        // Brows only on an awake face: open eyes and blinks have them, sleeping eyes do not.
        func hasBrows(_ frame: AwakeEyes.Frame) -> Bool { AwakeEyes.pixels(frame).contains { $0.y <= 2 } }
        XCTAssertTrue(hasBrows(.downRight))
        XCTAssertTrue(hasBrows(.blink))
        XCTAssertFalse(hasBrows(.shut))
        XCTAssertFalse(hasBrows(.asleep))
        XCTAssertEqual(AwakeEyes.pixels(.blink).filter { $0.y <= 2 }, AwakeEyes.pixels(.downRight).filter { $0.y <= 1 },
                       "a blink keeps the open eyes' brows, so nothing jumps")
        XCTAssertEqual(AwakeEyes.pixels(.asleep).count, 12)
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

    /// The slip says the time first: how long, then from when to when.
    func testTheSlipPutsTheTimeFirst() throws {
        let shut = t0, ended = t0.addingTimeInterval(4 * 60 + 9), opened = t0.addingTimeInterval(5 * 60 + 30)
        var receipt = HoldReceipt(closedAt: shut, openedAt: opened, titles: ["You"], batteryAtClose: 99, batteryAtOpen: 98,
                                  endedAt: ended, end: .finished)
        var slip = try XCTUnwrap(AwakeText.slip(receipt))
        XCTAssertEqual(slip.headline, "Awake for 4 min")
        XCTAssertEqual(slip.span, "\(AwakeText.clock(shut)) → \(AwakeText.clock(ended)), then it slept")
        XCTAssertEqual(slip.footnote, "Because you said so · Battery 99 → 98\u{00A0}%")
        XCTAssertFalse(slip.cutShort)

        receipt = HoldReceipt(closedAt: shut, openedAt: opened, titles: ["Claude Code", "Zoom"], batteryAtClose: 60, batteryAtOpen: 60)
        slip = try XCTUnwrap(AwakeText.slip(receipt))
        XCTAssertEqual(slip.headline, "Awake for 5 min")
        XCTAssertEqual(slip.span, "\(AwakeText.clock(shut)) → \(AwakeText.clock(opened)), until you opened the lid")
        XCTAssertEqual(slip.footnote, "For Claude Code and Zoom")

        receipt = HoldReceipt(closedAt: shut, openedAt: opened, titles: ["Cursor"], batteryAtClose: 60, batteryAtOpen: 19,
                              endedAt: ended, end: .batteryFloor)
        slip = try XCTUnwrap(AwakeText.slip(receipt))
        XCTAssertEqual(slip.headline, "Stopped after 4 min")
        XCTAssertTrue(slip.span.hasSuffix(", the battery was low"))
        XCTAssertTrue(slip.cutShort)
    }

    /// A hold with no named reason (the lid shut while winding down) has no "who".
    func testAReceiptWithNobodyToName() {
        let receipt = HoldReceipt(closedAt: t0, openedAt: t0.addingTimeInterval(180), titles: [], batteryAtClose: 72, batteryAtOpen: 72)
        XCTAssertEqual(AwakeText.receipt(receipt), ["Your Mac stayed awake for 3 min, the whole time the lid was shut."])
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
