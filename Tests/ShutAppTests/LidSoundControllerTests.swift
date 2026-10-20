import Combine
import LidSensor
import XCTest
@testable import ShutApp

/// The whole feature against a fake player and a fake output: when the sound starts, fades
/// and stops, and what mute does to it. No audio hardware, no lid, no Metal.
@MainActor
final class LidSoundControllerTests: XCTestCase {
    final class FakePlayer: SoundPlaying {
        var volume: Float = 1
        var duration: TimeInterval = 2
        var onFinish: (() -> Void)?
        var log: [String] = []
        func prepare() { log.append("prepare") }
        func seek(to seconds: TimeInterval) { log.append("seek \(Int(seconds))") }
        func play() { log.append("play") }
        func setVolume(_ volume: Float, fade: TimeInterval) { log.append("fade \(fade)") }
        func stop() { log.append("stop") }
    }

    final class FakeOutput: OutputMuting {
        var deviceName: String? = "Speakers"
        var deviceUID: String? = "built-in"
        var muted = false
        var canSetMute = true
        var sets: [Bool] = []
        var isMuted: Bool { muted }
        func setMuted(_ muted: Bool) -> Bool { sets.append(muted); self.muted = muted; return true }
        func listen(_ onChange: @escaping () -> Void) -> AnyCancellable { AnyCancellable {} }
    }

    private var players: [FakePlayer] = []
    private var pending: [(TimeInterval, () -> Void)] = []
    private var output = FakeOutput()
    private var suite: UserDefaults!

    private func make(lidEffects: Bool = true, items: [LidSoundItem]? = nil,
                      capability: HingeCapability = .continuousAngle) -> (LidSoundController, LidSoundSettings) {
        suite = UserDefaults(suiteName: "LidSoundController-\(UUID().uuidString)")!
        let settings = LidSoundSettings(defaults: suite)
        settings.isOn = true
        if let items { settings.items = items }
        let app = AppSettings(defaults: suite)
        app.isEnabled = lidEffects
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LidSoundController-\(UUID().uuidString)")
        let library = LidSoundLibrary(directory: folder, bundle: AppAssets.resourceBundle())
        let controller = LidSoundController(settings: settings, appSettings: app, sensor: LidSensorMonitor(defaults: nil), hasLid: true,
                                            library: library, output: output,
                                            makePlayer: { [unowned self] _ in let p = FakePlayer(); self.players.append(p); return p },
                                            after: { [unowned self] seconds, work in
                                                self.pending.append((seconds, work)); return DispatchWorkItem(block: work) },
                                            capability: { capability })
        controller.start()
        return (controller, settings)
    }

    private func hinge(_ controller: LidSoundController, _ p: Double, _ direction: HingeDirection) {
        controller.hinge(HingeState(angle: nil, progress: p, velocity: 0, direction: direction, isClosed: p >= 0.98, timestamp: 0))
    }

    private func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    func testACloseWithLidEffectsOn() {
        let (controller, settings) = make()
        XCTAssertEqual(settings.items.count, 3, "the starters")
        hinge(controller, 0.005, .closing)
        XCTAssertEqual(players.count, 1)
        XCTAssertEqual(players[0].log, ["prepare"], "woken at arm, long before the overlay")
        hinge(controller, 0.02, .closing)
        XCTAssertEqual(players[0].log, ["prepare"], "with Lid effects on, the overlay says when")
        controller.closeBeginning()
        XCTAssertEqual(players[0].log, ["prepare", "play"])
        XCTAssertNotNil(controller.playing)
        hinge(controller, 0.5, .closing)
        hinge(controller, 0.91, .closing)
        XCTAssertEqual(players[0].log, ["prepare", "play", "fade 0.3"], "near shut: the sound lands with the lid")
        XCTAssertEqual(pending.count, 1)
        hinge(controller, 0.99, .closing)
        XCTAssertEqual(players[0].log.count, 3, "a second fade never restarts the clock")
        pending.removeFirst().1()
        spin()
        XCTAssertNil(controller.playing)
        XCTAssertTrue(players[0].log.contains("stop"))
        XCTAssertNotNil(settings.lastPickID, "the sound that played is the one random will not repeat")
    }

    func testLidEffectsOffStillPlaysFromTheHinge() {
        let (controller, _) = make(lidEffects: false)
        hinge(controller, 0.005, .closing)
        hinge(controller, 0.02, .closing)
        XCTAssertEqual(players[0].log, ["prepare", "play"], "no overlay: the hinge says when")
    }

    func testLiftingTheLidFadesItOut() {
        let (controller, _) = make()
        hinge(controller, 0.005, .closing)
        controller.closeBeginning()
        hinge(controller, 0.4, .closing)
        hinge(controller, 0.38, .opening)
        XCTAssertEqual(players[0].log, ["prepare", "play"], "a wobble is not a change of mind")
        hinge(controller, 0.3, .opening)
        XCTAssertEqual(players[0].log, ["prepare", "play", "fade 0.15"])
    }

    func testACloseThatNeverShowedDropsThePreparedSound() {
        let (controller, settings) = make()
        let before = settings.lastPickID
        hinge(controller, 0.005, .closing)
        controller.closeEnded(reason: "disarmed")
        spin()
        XCTAssertEqual(players[0].log, ["prepare", "stop"], "nothing played")
        XCTAssertEqual(settings.lastPickID, before, "a pick that never played is not the last pick")
        XCTAssertNil(controller.playing)
    }

    func testTheOpeningSound() {
        let (controller, settings) = make()
        controller.openingBeginning()
        XCTAssertTrue(players.isEmpty, "off by default")
        settings.onOpen = true
        settings.onOpenPick = .item(settings.items[1].id)
        controller.openingBeginning()
        XCTAssertEqual(players.count, 1)
        XCTAssertEqual(players[0].log, ["prepare", "play"])
        XCTAssertEqual(controller.playing, "Breath")
    }

    func testMutedStaysQuiet() {
        output.muted = true
        let (controller, _) = make()
        hinge(controller, 0.005, .closing)
        controller.closeBeginning()
        spin()
        XCTAssertFalse(players[0].log.contains("play"))
        XCTAssertTrue(output.sets.isEmpty, "the Mac's mute is not touched")
        XCTAssertNil(controller.playing)
    }

    func testUnmuteForItAndPutItBack() {
        output.muted = true
        let (controller, settings) = make()
        settings.whenMuted = .unmute
        hinge(controller, 0.005, .closing)
        controller.closeBeginning()
        XCTAssertEqual(output.sets, [false])
        XCTAssertTrue(players[0].log.contains("play"))
        XCTAssertTrue(LidSoundSettings(defaults: suite).muteToRestore, "the debt is written down before the mute is touched")
        players[0].onFinish?()
        spin()
        XCTAssertEqual(output.sets, [false, true], "mute comes back when the sound ends")
        XCTAssertFalse(LidSoundSettings(defaults: suite).muteToRestore)
    }

    func testAMuteOwedFromLastTimeIsPaidAtLaunch() {
        suite = UserDefaults(suiteName: "LidSoundController-\(UUID().uuidString)")!
        let settings = LidSoundSettings(defaults: suite)
        settings.muteToRestore = true
        settings.muteToRestoreDeviceUID = "built-in"
        output.muted = false
        let controller = LidSoundController(settings: settings, appSettings: AppSettings(defaults: suite), sensor: LidSensorMonitor(defaults: nil),
                                            hasLid: true, library: LidSoundLibrary(directory: FileManager.default.temporaryDirectory, bundle: nil),
                                            output: output, makePlayer: { _ in FakePlayer() })
        controller.start()
        XCTAssertEqual(output.sets, [true])
        XCTAssertFalse(settings.muteToRestore)

        // On another output the debt is forgiven, not paid on the wrong device.
        settings.muteToRestore = true
        settings.muteToRestoreDeviceUID = "airpods"
        output.sets = []
        controller.start()
        XCTAssertTrue(output.sets.isEmpty)
        XCTAssertFalse(settings.muteToRestore)
    }

    func testAMacWithoutAnAngleSensorNeverFadesOnLanding() {
        let (controller, _) = make(capability: .lidStateOnly)
        hinge(controller, 0.005, .closing)
        controller.closeBeginning()
        hinge(controller, 1, .closing)
        XCTAssertEqual(players[0].log, ["prepare", "play"], "progress jumps to 1 on an edge-only Mac: no fade")
    }

    func testSwitchingOffDropsEverything() {
        let (controller, settings) = make()
        hinge(controller, 0.005, .closing)
        controller.closeBeginning()
        settings.isOn = false
        spin()
        XCTAssertNil(controller.playing)
        XCTAssertTrue(players[0].log.contains("stop"))
    }
}

extension LidSoundControllerTests {
    /// Starts at: with the screen effect (the overlay says when), or at an angle of its own
    /// (the hinge says when, and the overlay appearing is not it).
    func testAnAngleOfItsOwn() {
        let (controller, settings) = make()
        settings.startsWithEffect = false
        settings.startDegrees = 45
        spin()
        controller.hinge(HingeState(angle: 95, progress: 0.005, velocity: 0, direction: .closing, isClosed: false, timestamp: 0))
        XCTAssertEqual(players[0].log, ["prepare"])
        controller.closeBeginning()
        XCTAssertEqual(players[0].log, ["prepare"], "the overlay appearing at 60° is not 45°")
        controller.hinge(HingeState(angle: 50, progress: 0.2, velocity: 0, direction: .closing, isClosed: false, timestamp: 0))
        XCTAssertEqual(players[0].log, ["prepare"])
        controller.hinge(HingeState(angle: 44, progress: 0.3, velocity: 0, direction: .closing, isClosed: false, timestamp: 0))
        XCTAssertEqual(players[0].log, ["prepare", "play"], "45° reached")
        XCTAssertEqual(Int(controller.startDegrees), 45)
        settings.startsWithEffect = true
        spin()
        XCTAssertEqual(Int(controller.startDegrees), Int(controller.effectStartDegrees), "the dial shows the effect's angle")
    }

    /// A long file plays from the clip the user chose, and for thirty seconds at most.
    func testALongFileIsClipped() {
        let (controller, settings) = make()
        var song = settings.items[0]
        song.duration = 200; song.clipStart = 72
        settings.update(song)
        settings.onOpen = true
        settings.onOpenPick = .item(song.id)
        XCTAssertTrue(song.isLong)
        controller.openingBeginning()
        XCTAssertEqual(players[0].log, ["seek 72", "prepare", "play"], "from 1:12")
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].0, LidSoundLibrary.clipLength, "its thirty seconds are counted from play")
        pending.removeFirst().1()
        XCTAssertEqual(players[0].log.last, "fade 0.3", "then it fades, however the lid is held")
    }

    /// The opening's sound is made and prepared at wake, so the unlock only has to play it.
    func testTheOpeningIsWarmedAtWake() {
        let (controller, settings) = make()
        settings.onOpen = true
        settings.onOpenPick = .item(settings.items[2].id)
        controller.warmTheOpening()
        XCTAssertEqual(players.count, 1)
        XCTAssertEqual(players[0].log, ["prepare"], "ready, nothing heard")
        controller.openingBeginning()
        XCTAssertEqual(players.count, 1, "the warm player is the one that plays")
        XCTAssertEqual(players[0].log, ["prepare", "play"])
        XCTAssertEqual(controller.playing, "Hum")
    }
}
