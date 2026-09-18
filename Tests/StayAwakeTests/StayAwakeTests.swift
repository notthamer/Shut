import XCTest
@testable import StayAwake

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

private func work(_ id: String = "working:cursor", since: Date = t0) -> HoldReason {
    HoldReason(id: id, kind: .working, title: "Cursor", since: since)
}
private let display = HoldReason(id: "display:Studio Display", kind: .display, title: "Studio Display", since: t0)
private let on = HoldLimits(isOn: true)
private let battery = PowerConditions(onCharger: false, batteryPercent: 80)

/// The safety table: every limit, on its own.
final class StayAwakePolicyTests: XCTestCase {
    private func blocker(_ limits: HoldLimits = on, _ conditions: PowerConditions, lidClosed: Bool = true,
                         onBatterySince: Date? = nil, now: Date = t0) -> StopReason? {
        StayAwakePolicy.blocker(limits: limits, conditions: conditions, lidClosed: lidClosed, onBatterySince: onBatterySince, now: now)
    }

    func testHealthyMachineMayHold() {
        XCTAssertNil(blocker(on, battery))
        XCTAssertNil(blocker(on, PowerConditions(onCharger: true, batteryPercent: 5)), "the floor is about battery power only")
        XCTAssertNil(blocker(on, PowerConditions(onCharger: true, batteryPercent: nil)), "a Mac with no battery")
    }

    func testBatteryFloor() {
        XCTAssertEqual(blocker(on, PowerConditions(onCharger: false, batteryPercent: 20)), .batteryFloor)
        XCTAssertNil(blocker(on, PowerConditions(onCharger: false, batteryPercent: 21)))
    }

    func testHeatIsStricterWithTheLidShut() {
        let serious = PowerConditions(onCharger: true, thermal: .serious)
        XCTAssertEqual(blocker(on, serious, lidClosed: true), .tooHot)
        XCTAssertNil(blocker(on, serious, lidClosed: false))
        XCTAssertEqual(blocker(on, PowerConditions(onCharger: true, thermal: .critical), lidClosed: false), .tooHot)
    }

    func testChargerOnlyAndLowPowerMode() {
        XCTAssertEqual(blocker(HoldLimits(isOn: true, chargerOnly: true), battery), .chargerOnly)
        XCTAssertEqual(blocker(on, PowerConditions(onCharger: true, lowPowerMode: true)), .lowPowerMode)
        XCTAssertNil(blocker(HoldLimits(isOn: true, respectLowPowerMode: false), PowerConditions(onCharger: true, lowPowerMode: true)))
    }

    func testCapCountsOnBatteryOnly() {
        XCTAssertEqual(blocker(on, battery, onBatterySince: t0, now: at(8 * 3600)), .timeCap)
        XCTAssertNil(blocker(on, battery, onBatterySince: t0, now: at(8 * 3600 - 1)))
        XCTAssertNil(blocker(on, PowerConditions(onCharger: true), onBatterySince: t0, now: at(24 * 3600)), "a desk setup runs all day")
    }
}

final class HoldStateMachineTests: XCTestCase {
    private func run(_ machine: inout HoldStateMachine, _ reasons: [HoldReason], _ seconds: TimeInterval,
                     limits: HoldLimits = on, conditions: PowerConditions = battery, lidClosed: Bool = false) -> HoldState {
        machine.update(limits: limits, conditions: conditions, reasons: reasons, lidClosed: lidClosed, now: at(seconds))
    }

    func testOffMeansOffWhateverIsTrue() {
        var machine = HoldStateMachine()
        XCTAssertEqual(run(&machine, [work(), display], 0, limits: HoldLimits(isOn: false)), .off)
    }

    func testNoReasonSleepsAsUsual() {
        var machine = HoldStateMachine()
        XCTAssertEqual(run(&machine, [], 0), .ready)
        XCTAssertFalse(machine.state.holdsLid)
    }

    func testWorkHoldsThenGetsAGracePeriodThenLetsGo() {
        var machine = HoldStateMachine()
        XCTAssertEqual(run(&machine, [work()], 0), .holding)
        XCTAssertEqual(run(&machine, [], 100), .grace(until: at(400)))
        XCTAssertTrue(machine.state.holdsLid)
        XCTAssertEqual(run(&machine, [], 399), .grace(until: at(400)), "grace must not slide")
        XCTAssertEqual(run(&machine, [], 400), .ready)
    }

    func testWorkResumingDuringGraceKeepsHolding() {
        var machine = HoldStateMachine()
        _ = run(&machine, [work()], 0)
        _ = run(&machine, [], 100)
        XCTAssertEqual(run(&machine, [work()], 200), .holding)
        XCTAssertEqual(run(&machine, [], 300), .grace(until: at(600)), "a fresh grace after the second stretch")
    }

    func testADisplayUnpluggedGetsNoGrace() {
        var machine = HoldStateMachine()
        XCTAssertEqual(run(&machine, [display], 0), .holding)
        XCTAssertEqual(run(&machine, [], 10), .ready)
    }

    func testLimitStopsAndRecovers() {
        var machine = HoldStateMachine()
        let low = PowerConditions(onCharger: false, batteryPercent: 18)
        XCTAssertEqual(run(&machine, [work()], 0, conditions: low), .stopped(.batteryFloor))
        XCTAssertEqual(run(&machine, [work()], 60, conditions: PowerConditions(onCharger: true, batteryPercent: 18)), .holding)
    }

    func testCapRestartsAfterTimeOnTheCharger() {
        var machine = HoldStateMachine()
        _ = run(&machine, [display], 0)
        XCTAssertEqual(run(&machine, [display], 8 * 3600), .stopped(.timeCap))
        _ = run(&machine, [display], 8 * 3600 + 60, conditions: PowerConditions(onCharger: true, batteryPercent: 50))
        XCTAssertEqual(run(&machine, [display], 8 * 3600 + 120), .holding, "unplugged again: a new stretch")
    }

    func testLetItSleepOverrulesUntilSomethingNewHappens() {
        var machine = HoldStateMachine()
        _ = run(&machine, [work()], 0)
        machine.letItSleep(reasons: [work()], now: at(10))
        XCTAssertEqual(run(&machine, [work()], 10), .stopped(.userLetItSleep))
        XCTAssertEqual(run(&machine, [work()], 500), .stopped(.userLetItSleep), "same work, still overruled")
        XCTAssertEqual(run(&machine, [work(), display], 510), .holding, "a new reason is a new decision")
    }

    func testLetItSleepEndsWhenTheWorkEndsAndUndoWorks() {
        var machine = HoldStateMachine()
        _ = run(&machine, [work()], 0)
        machine.letItSleep(reasons: [work()], now: at(10))
        XCTAssertEqual(run(&machine, [], 20), .ready, "no grace after the user said sleep")
        XCTAssertEqual(run(&machine, [work()], 30), .holding, "next run holds again")

        machine.letItSleep(reasons: [work()], now: at(40))
        machine.undoLetItSleep()
        XCTAssertEqual(run(&machine, [work()], 41), .holding)
    }

    func testLetItSleepDuringGrace() {
        var machine = HoldStateMachine()
        _ = run(&machine, [work()], 0)
        _ = run(&machine, [], 10)
        machine.letItSleep(reasons: [], now: at(20))
        XCTAssertEqual(run(&machine, [], 20), .ready)
    }

    func testTimedReasonsRunOut() {
        var machine = HoldStateMachine()
        let manual = HoldReason(id: "manual", kind: .manual, title: "You", since: t0, until: at(3600))
        XCTAssertEqual(run(&machine, [manual], 0), .holding)
        XCTAssertEqual(machine.nextDeadline(limits: on, reasons: [manual], now: at(0)), at(3600))
        XCTAssertEqual(run(&machine, [manual], 3600), .ready)
    }

    func testNextDeadlineIsTheEarliest() {
        var machine = HoldStateMachine()
        _ = run(&machine, [work()], 0)
        XCTAssertEqual(machine.nextDeadline(limits: on, reasons: [work()], now: at(0)), at(8 * 3600), "the battery cap")
        _ = run(&machine, [], 50)
        XCTAssertEqual(machine.nextDeadline(limits: on, reasons: [], now: at(50)), at(350), "grace end")
    }
}

/// caffeinate <- claude <- zsh <- Cursor Helper <- Cursor, and friends.
final class AssertionAttributionTests: XCTestCase {
    private let cursor = ProcessNode.App(bundleID: "com.todesktop.cursor", name: "Cursor", isDeveloperTool: true)
    private let resolve = ProcessNode.App(bundleID: "com.blackmagic.resolve", name: "DaVinci Resolve", isDeveloperTool: false)
    private let music = ProcessNode.App(bundleID: "com.apple.Music", name: "Music", isDeveloperTool: false)

    private var table: [pid_t: ProcessNode] {
        [500: ProcessNode(name: "Cursor", parent: 1, app: cursor),
         510: ProcessNode(name: "Cursor Helper", parent: 500, app: nil),
         520: ProcessNode(name: "zsh", parent: 510, app: nil),
         530: ProcessNode(name: "2.1.275", parent: 520, app: nil),   // claude names its process after its version
         540: ProcessNode(name: "caffeinate", parent: 530, app: nil),
         600: ProcessNode(name: "Resolve", parent: 1, app: resolve),
         700: ProcessNode(name: "Music", parent: 1, app: music),
         350: ProcessNode(name: "powerd", parent: 1, app: nil),
         425: ProcessNode(name: "coreaudiod", parent: 1, app: nil),
         999: ProcessNode(name: "shut", parent: 1, app: nil)]
    }

    private func owners(_ assertions: [RawAssertion]) -> [AssertionAttribution.Owner] {
        AssertionAttribution.owners(of: assertions, ownPID: 999) { self.table[$0] }
    }

    func testCommandLineToolBelongsToTheAppItRunsIn() {
        let result = owners([RawAssertion(pid: 540, type: "PreventUserIdleSystemSleep", name: "caffeinate command-line tool")])
        XCTAssertEqual(result.map(\.app.name), ["Cursor"])
        XCTAssertTrue(result[0].viaCommandLine)
    }

    func testAnAppAssertingForItselfIsNotCommandLineWork() {
        let result = owners([RawAssertion(pid: 600, type: "PreventUserIdleSystemSleep", name: "Background Activity")])
        XCTAssertEqual(result.map(\.app.name), ["DaVinci Resolve"])
        XCTAssertFalse(result[0].viaCommandLine)
    }

    func testDaemonsAssertingOnBehalfOfAnApp() {
        let result = owners([RawAssertion(pid: 425, type: "PreventUserIdleSystemSleep", name: "audio", onBehalfOf: 700)])
        XCTAssertEqual(result.map(\.app.name), ["Music"])
        XCTAssertFalse(result[0].viaCommandLine)
    }

    func testSystemDaemonsDisplayAssertionsAndOurselvesAreIgnored() {
        XCTAssertTrue(owners([
            RawAssertion(pid: 350, type: "PreventUserIdleSystemSleep", name: "Powerd - Prevent sleep while display is on"),
            RawAssertion(pid: 600, type: "PreventUserIdleDisplaySleep", name: "video"),
            RawAssertion(pid: 999, type: "PreventUserIdleSystemSleep", name: "Shut is keeping the Mac awake"),
            RawAssertion(pid: 4242, type: "PreventUserIdleSystemSleep", name: "a process that has already exited"),
        ]).isEmpty)
    }

    func testCreatedForPIDIsParsedFromDetails() {
        XCTAssertEqual(AssertionMirror.createdForPID("com.apple.audio.context. Created for PID: 92711. "), 92711)
        XCTAssertNil(AssertionMirror.createdForPID("caffeinate asserting for 300 secs"))
    }
}

/// The arbiter against a fake kernel: what it asks the system to do, and when.
@MainActor
final class HoldArbiterTests: XCTestCase {
    final class FakeHold: LidHolding {
        var lidCalls: [Bool] = []
        var idlePrevented = false
        var refuse = false
        func setLidSleepDisabled(_ disabled: Bool) -> Bool { lidCalls.append(disabled); return !refuse }
        func setIdleSleepPrevented(_ prevented: Bool) { idlePrevented = prevented }
    }

    private func make(_ hold: FakeHold) -> (HoldArbiter, ArmedMarker) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StayAwakeTests-\(UUID().uuidString)")
        let marker = ArmedMarker(directory: directory)
        let arbiter = HoldArbiter(limits: HoldLimits(isOn: true), hold: hold, marker: marker,
                                  mirror: AssertionMirror(defaults: nil))
        arbiter.setEnabled(.working, false)   // no real system reads in tests
        arbiter.setEnabled(.display, false)
        return (arbiter, marker)
    }

    func testManualHoldArmsAndLetItSleepDisarms() {
        let hold = FakeHold()
        let (arbiter, marker) = make(hold)
        arbiter.start()
        XCTAssertEqual(arbiter.state, .ready)
        XCTAssertTrue(hold.lidCalls.isEmpty, "nothing to hold: the system is never touched")

        arbiter.manual.begin(for: 3600)
        XCTAssertEqual(arbiter.state, .holding)
        XCTAssertEqual(hold.lidCalls, [true])
        XCTAssertTrue(hold.idlePrevented)
        XCTAssertTrue(marker.exists)

        arbiter.letItSleep()
        XCTAssertEqual(arbiter.state, .ready)
        XCTAssertEqual(hold.lidCalls, [true, false])
        XCTAssertFalse(hold.idlePrevented)
        XCTAssertFalse(marker.exists)
        arbiter.shutDown()
    }

    func testShutDownAlwaysRestoresTheLid() {
        let hold = FakeHold()
        let (arbiter, marker) = make(hold)
        arbiter.start()
        arbiter.manual.begin(for: nil)
        arbiter.shutDown()
        XCTAssertEqual(hold.lidCalls.last, false)
        XCTAssertFalse(marker.exists)
    }

    func testTurningTheFeatureOffRestoresTheLid() {
        let hold = FakeHold()
        let (arbiter, _) = make(hold)
        arbiter.start()
        arbiter.manual.begin(for: nil)
        arbiter.limits.isOn = false
        XCTAssertEqual(arbiter.state, .off)
        XCTAssertEqual(hold.lidCalls, [true, false])
        arbiter.shutDown()
    }

    func testARefusedCallLeavesNoMarkerBehind() {
        let hold = FakeHold()
        hold.refuse = true
        let (arbiter, marker) = make(hold)
        arbiter.start()
        arbiter.manual.begin(for: nil)
        XCTAssertFalse(marker.exists)
        XCTAssertFalse(hold.idlePrevented)
        arbiter.shutDown()
    }

    func testRecoveryUndoesAHoldLeftByACrash() {
        let hold = FakeHold()
        let (arbiter, marker) = make(hold)
        XCTAssertFalse(arbiter.recoverFromLastRun(), "no marker: leave the shared bit alone")
        XCTAssertTrue(hold.lidCalls.isEmpty)

        marker.write()
        XCTAssertTrue(arbiter.recoverFromLastRun())
        XCTAssertEqual(hold.lidCalls, [false])
        XCTAssertFalse(marker.exists)
    }
}

/// `shut hold`: the protocol, and one real round trip over a socket.
@MainActor
final class CommandHoldTests: XCTestCase {
    func testStartStopAndStatus() {
        let hold = CommandHold(path: "/unused")
        hold.statusLine = { "holding" }
        var changes = 0
        hold.onChange = { changes += 1 }

        XCTAssertEqual(hold.handle("START\trender\t0\t7200\tFinal render", now: t0), "ok holding")
        XCTAssertEqual(hold.reasons.map(\.id), ["command:render"])
        XCTAssertEqual(hold.reasons.first?.title, "Final render")
        XCTAssertEqual(hold.reasons.first?.until, at(7200))
        XCTAssertEqual(hold.handle("START\trender\t0\t0\tFinal render", now: t0), "ok holding", "the same id replaces, never doubles")
        XCTAssertEqual(hold.reasons.count, 1)
        XCTAssertEqual(hold.handle("STATUS"), "holding")
        XCTAssertEqual(hold.handle("STOP\trender"), "ok holding")
        XCTAssertTrue(hold.reasons.isEmpty)
        XCTAssertEqual(changes, 3)
        XCTAssertTrue(hold.handle("nonsense").hasPrefix("error"))
    }

    func testTimedHoldsArePrunedAndDeadProcessesNeverHold() {
        let hold = CommandHold(path: "/unused")
        _ = hold.handle("START\ta\t0\t60\ta", now: t0)
        hold.prune(now: at(59))
        XCTAssertEqual(hold.reasons.count, 1)
        hold.prune(now: at(60))
        XCTAssertTrue(hold.reasons.isEmpty)

        _ = hold.handle("START\tghost\t2147483000\t0\tghost", now: t0)
        XCTAssertTrue(hold.reasons.isEmpty, "a pid that does not exist is not a reason")
    }

    func testControlCharactersAreStrippedAndDurationsParse() {
        XCTAssertEqual(CommandHold.clean("build\u{07}\n\u{1B}[31m", limit: 40), "build[31m")
        XCTAssertEqual(CommandHold.clean(String(repeating: "x", count: 100), limit: 40).count, 40)
        XCTAssertEqual(HoldCommand.seconds("90s"), 90)
        XCTAssertEqual(HoldCommand.seconds("30m"), 1800)
        XCTAssertEqual(HoldCommand.seconds("2h"), 7200)
        XCTAssertEqual(HoldCommand.seconds("45"), 45)
        XCTAssertNil(HoldCommand.seconds("soon"))
    }

    func testARealRoundTripOverTheSocket() {
        let path = NSTemporaryDirectory() + "shut-\(UUID().uuidString.prefix(8)).sock"
        let hold = CommandHold(path: path)
        hold.statusLine = { "ready" }
        hold.start()
        defer { hold.stop() }

        var answer: String?
        let done = expectation(description: "answered")
        DispatchQueue.global().async {
            answer = HoldSocket.request("START\tbuild\t0\t0\tBuild", path: path)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(answer, "ok ready")
        XCTAssertEqual(hold.reasons.map(\.title), ["Build"])
        XCTAssertNil(HoldSocket.request("STATUS", path: path + ".nobody"), "nobody listening is nil, not a hang")
    }
}
