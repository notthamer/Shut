import AppKit
import XCTest
@testable import ShutApp
@testable import StayAwake

/// The whole feature, end to end, the way a person meets it: nothing here is a unit. A
/// stand-in kernel, battery and list of busy apps; the real arbiter, controller, journal,
/// wording and slip. Grace is a fraction of a second so real timers can run.
@MainActor
final class AwakeJourneyTests: XCTestCase {
    final class FakeKernel: LidHolding {
        var lidCalls: [Bool] = []
        func setLidSleepDisabled(_ disabled: Bool) -> Bool { lidCalls.append(disabled); return true }
        func setIdleSleepPrevented(_ prevented: Bool) {}
    }

    final class World {
        var asking: [AssertionAttribution.Owner] = []
        var power = PowerConditions(onCharger: true, batteryPercent: 90)
        let kernel = FakeKernel()
    }

    private func owner(_ id: String, _ name: String, developerTool: Bool = false, tool: String? = nil) -> AssertionAttribution.Owner {
        AssertionAttribution.Owner(app: .init(bundleID: id, name: name, isDeveloperTool: developerTool),
                                   viaCommandLine: tool != nil, assertionName: "journey", tool: tool)
    }

    private func start(_ world: World, grace: TimeInterval = 0.25) -> StayAwakeController {
        let settings = StayAwakeSettings(defaults: UserDefaults(suiteName: "AwakeJourney-\(UUID().uuidString)")!)
        settings.hasConsented = true
        settings.isOn = true
        settings.whenDisplayConnected = false   // the real display list is not part of the story
        settings.lockWhenShut = false           // or the test would lock this Mac's screen
        settings.grace = grace
        let marker = ArmedMarker(directory: FileManager.default.temporaryDirectory.appendingPathComponent("AwakeJourney-\(UUID().uuidString)"))
        let arbiter = HoldArbiter(hold: world.kernel, marker: marker,
                                  monitor: PowerSourceMonitor(reader: { world.power }),
                                  mirror: AssertionMirror(defaults: nil, read: { world.asking }))
        let awake = StayAwakeController(settings: settings, arbiter: arbiter)
        awake.start()
        spin(0.05)   // settings reach the arbiter on the next main-queue turn
        return awake
    }

    private func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func badge(_ awake: StayAwakeController) -> AwakeText.Dot {
        AwakeText.badge(state: awake.arbiter.state, conditions: awake.arbiter.conditions, limits: awake.arbiter.limits)
    }

    // MARK: 1. From "Zoom is asking" to the slip after unlock

    func testACallKeepsTheMacAwakeAndTheSlipSaysSo() throws {
        let world = World()
        world.asking = [owner("us.zoom.xos", "Zoom")]
        let awake = start(world)

        // An app that is not a developer tool is asking: one question, nothing held yet.
        XCTAssertEqual(awake.arbiter.state, .ready)
        XCTAssertEqual(awake.status.sentence, "Zoom is asking to stay awake")
        XCTAssertEqual(awake.status.action, .allow)
        XCTAssertEqual(badge(awake), .idle)
        XCTAssertTrue(world.kernel.lidCalls.isEmpty, "the system is not touched for an app nobody allowed")

        awake.perform(.allow)
        XCTAssertEqual(awake.arbiter.state, .holding)
        XCTAssertEqual(world.kernel.lidCalls, [true])
        XCTAssertEqual(badge(awake), .holding)
        XCTAssertEqual(AwakeEyes.Mood(awake.status.dot, isOn: true), .awake)
        XCTAssertEqual(AwakeText.live(awake.arbiter.reasons, now: Date()), "Zoom · <1 min")

        // The lid comes down: a fresh look, the caption with its lesson, then shut.
        let shutAt = Date().addingTimeInterval(-130)
        awake.lidStartedClosing()
        awake.closeBeginning()
        let caption = try XCTUnwrap(awake.closingCaption(beginning: true))
        XCTAssertEqual(caption.text, "Staying awake · Zoom is working")
        XCTAssertFalse(caption.warning)
        XCTAssertEqual(caption.hint, "Hold ⌥ to let it sleep instead")
        awake.lidEdge(isOpen: false, now: shutAt)
        XCTAssertTrue(awake.arbiter.lidClosed)

        // The call ends while the lid is shut: a little longer, then the Mac may sleep.
        world.asking = []
        awake.arbiter.mirror.refresh()
        guard case .grace = awake.arbiter.state else { return XCTFail("expected grace, got \(awake.arbiter.state)") }
        XCTAssertEqual(badge(awake), .winding)
        XCTAssertEqual(AwakeEyes.Mood(awake.status.dot, isOn: true), .drowsy)
        XCTAssertEqual(awake.closingCaption(beginning: false)?.text, "Staying awake a little longer")
        spin(0.6)
        XCTAssertEqual(awake.arbiter.state, .ready)
        XCTAssertEqual(world.kernel.lidCalls.last, false, "lid sleep handed back to macOS")
        awake.macWillSleep()

        // Back again: locked first, so the slip waits; then it says what happened, once.
        var locked = true
        var slips: [HoldReceipt] = []
        let slip = ReceiptSlip(stayAwake: awake, isLocked: { locked })
        slip.settleDelay = 0
        slip.present = { slips.append($0) }
        awake.onReturn = { slip.lidOpened($0) }
        awake.lidEdge(isOpen: true)
        XCTAssertTrue(slips.isEmpty)
        locked = false
        slip.sessionUnlocked()
        let receipt = try XCTUnwrap(slips.first)
        XCTAssertEqual(receipt.end, .finished)
        XCTAssertEqual(receipt.titles, ["Zoom"])
        let lines = AwakeText.receipt(receipt)
        XCTAssertTrue(lines[0].hasPrefix("Zoom kept your Mac awake for 2 min, until "), lines[0])
        XCTAssertTrue(lines[0].hasSuffix("Then it slept."), lines[0])
        XCTAssertNotEqual(awake.status.action, .ok, "handed over: the bar does not repeat it")
        XCTAssertFalse(awake.arbiter.lidClosed)
        awake.shutDown()
    }

    // MARK: 2. The battery floor wins, and everything says so in Saffron

    func testTheBatteryFloorCutsAHoldShort() throws {
        let world = World()
        world.power = PowerConditions(onCharger: false, batteryPercent: 60)
        world.asking = [owner("com.todesktop.230313mzl4w4u92", "Cursor", developerTool: true, tool: "Claude Code")]
        let awake = start(world)
        XCTAssertEqual(awake.arbiter.state, .holding, "a developer tool is allowed from the start")
        XCTAssertEqual(awake.status.sentence, "Claude Code is working · <1 min")
        awake.lidEdge(isOpen: false, now: Date().addingTimeInterval(-3 * 3600))

        world.power = PowerConditions(onCharger: false, batteryPercent: 24)
        awake.arbiter.refreshPower()
        XCTAssertEqual(awake.arbiter.state, .holding)
        XCTAssertEqual(badge(awake), .warning, "within five points of the floor")
        XCTAssertEqual(awake.status.sentence, "On battery 24 % · sleeps at 20 %")

        world.power = PowerConditions(onCharger: false, batteryPercent: 19)
        awake.arbiter.refreshPower()
        XCTAssertEqual(awake.arbiter.state, .stopped(.batteryFloor))
        XCTAssertEqual(world.kernel.lidCalls.last, false)
        let caption = try XCTUnwrap(awake.closingCaption(beginning: false))
        XCTAssertEqual(caption.text, "Sleeping · battery is at 19 %")
        XCTAssertTrue(caption.warning)
        XCTAssertNil(caption.hint)

        var handed: HoldReceipt?
        awake.onReturn = { handed = $0 }
        awake.lidEdge(isOpen: true)
        let receipt = try XCTUnwrap(handed)
        XCTAssertEqual(receipt.end, .batteryFloor)
        XCTAssertEqual(receipt.batteryAtClose, 60)
        XCTAssertEqual(receipt.batteryAtOpen, 19, "read fresh as the lid opens")
        let lines = AwakeText.receipt(receipt)
        XCTAssertTrue(lines[0].contains("because the battery was low"), lines[0])
        XCTAssertTrue(lines[0].hasSuffix("Claude Code was still going.") || lines[0].hasSuffix("Cursor was still going."), lines[0])
        XCTAssertEqual(lines.last, "Battery 60 → 19 %.")
        awake.shutDown()
    }

    // MARK: 3. macOS sleeps the Mac anyway, and the receipt does not pretend otherwise

    func testSleptAlthoughHeld() throws {
        let world = World()
        let awake = start(world)
        awake.setManualHold(stop: AwakeText.manualStop(remaining: 3600))
        XCTAssertEqual(awake.arbiter.state, .holding)
        awake.lidEdge(isOpen: false, now: Date().addingTimeInterval(-600))
        awake.macWillSleep()
        var handed: HoldReceipt?
        awake.onReturn = { handed = $0 }
        awake.lidEdge(isOpen: true)
        XCTAssertEqual(try XCTUnwrap(handed).end, .sleptAnyway)
        XCTAssertTrue(AwakeText.receipt(try XCTUnwrap(handed))[0].contains("although Shut was holding it"))
        awake.shutDown()
    }

    // MARK: 4. The first real close: the lid shut while already winding down

    /// 20 September, 23:08: work had just ended, the lid shut during the grace period, the Mac
    /// slept three minutes later, and the receipt recorded no ending at all.
    func testALidShutWhileWindingDownStillGetsItsEnding() throws {
        let world = World()
        world.asking = [owner("com.todesktop.230313mzl4w4u92", "Cursor", developerTool: true, tool: "Claude Code")]
        let awake = start(world, grace: 0.4)
        XCTAssertEqual(awake.arbiter.state, .holding)
        world.asking = []
        awake.arbiter.mirror.refresh()
        guard case .grace = awake.arbiter.state else { return XCTFail("expected grace") }

        awake.lidEdge(isOpen: false, now: Date().addingTimeInterval(-183))
        spin(0.8)
        XCTAssertEqual(awake.arbiter.state, .ready)
        awake.macWillSleep()
        var handed: HoldReceipt?
        awake.onReturn = { handed = $0 }
        awake.lidEdge(isOpen: true)
        let receipt = try XCTUnwrap(handed)
        XCTAssertEqual(receipt.titles, [], "nobody to name: the work had already ended")
        XCTAssertEqual(receipt.end, .finished, "the ending must be recorded")
        XCTAssertTrue(AwakeText.receipt(receipt)[0].hasPrefix("Your Mac stayed awake for 3 min, until "))
        awake.shutDown()
    }

    // MARK: 6. A hold that runs out looks again before it lets the Mac sleep

    /// 20 September, 23:36: a five-minute manual hold ended while an agent was working, on a
    /// reading taken before the agent's current caffeinate existed.
    func testAHoldRunningOutLooksAgainBeforeItLetsGo() throws {
        let world = World()
        let awake = start(world)
        awake.arbiter.manual.begin(for: 0.3)
        XCTAssertEqual(awake.arbiter.reasons.map(\.kind), [.manual])
        awake.lidEdge(isOpen: false, now: Date().addingTimeInterval(-240))
        // Work starts, and nothing tells Shut: macOS sends no event for it.
        world.asking = [owner("com.todesktop.230313mzl4w4u92", "Cursor", developerTool: true, tool: "Claude Code")]
        spin(0.7)
        XCTAssertEqual(awake.arbiter.state, .holding, "the manual hold ran out, but something is working")
        XCTAssertEqual(awake.arbiter.reasons.map(\.kind), [.working])
        XCTAssertNotEqual(world.kernel.lidCalls.last, false, "the lid was never let go")
        awake.shutDown()
    }

    // MARK: 5. Switching the feature off and on with the lid shut must not lose the lid

    func testTheLidStaysShutAcrossASettingsChange() throws {
        let world = World()
        let awake = start(world)
        awake.setManualHold(stop: AwakeText.manualLastStop)
        awake.lidEdge(isOpen: false, now: Date().addingTimeInterval(-300))
        XCTAssertTrue(awake.arbiter.lidClosed)
        // Any setting at all: the controller re-applies everything.
        awake.settings.batteryFloor = 25
        spin(0.1)
        XCTAssertTrue(awake.arbiter.lidClosed, "a settings change is not a lid opening")
        XCTAssertEqual(awake.arbiter.state, .holding)
        awake.shutDown()
    }
}
