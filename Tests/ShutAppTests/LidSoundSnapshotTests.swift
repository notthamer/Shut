import AppKit
import Combine
@testable import StayAwake
import LidSensor
import Metal
import SwiftUI
import TransitionKit
import Tuner
import XCTest
@testable import ShutApp

/// The Lid sound page and the three-tab header, rasterised offscreen in each state, against
/// a fake player and a fake output so no test makes a sound or touches the Mac's mute.
@MainActor
final class LidSoundSnapshotTests: XCTestCase {
    override func setUpWithError() throws { try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "No Metal device on this machine") }

    private var players: [LidSoundControllerTests.FakePlayer] = []
    private var output = LidSoundControllerTests.FakeOutput()

    private func makeModel(on: Bool, items: [LidSoundItem]? = nil, capability: HingeCapability = .continuousAngle) throws -> (PopoverModel, LidSoundController) {
        let suite = UserDefaults(suiteName: "LidSoundSnapshot-\(UUID().uuidString)")!
        let soundSettings = LidSoundSettings(defaults: suite, starters: LidSoundLibrary.fallbackStarters)
        soundSettings.isOn = on
        if let items { soundSettings.items = items }
        let settings = AppSettings(defaults: suite)
        let registry = TransitionRegistry(transitions: TransitionCatalog.make(), currentID: "fold")
        let sensor = LidSensorMonitor(defaults: nil)
        let preview = try PreviewModel(registry: registry, settings: settings, sensor: sensor)
        preview.capturePlaceholder()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LidSoundSnapshot-\(UUID().uuidString)")
        let sound = LidSoundController(settings: soundSettings, appSettings: settings, sensor: sensor, hasLid: true,
                                       library: LidSoundLibrary(directory: folder, bundle: AppAssets.resourceBundle(), starters: LidSoundLibrary.fallbackStarters), output: output,
                                       makePlayer: { [unowned self] _ in let p = LidSoundControllerTests.FakePlayer(); self.players.append(p); return p },
                                       capability: { capability })
        sound.start()
        sound.setLiveUpdates(true)
        let awakeSettings = StayAwakeSettings(defaults: suite)
        awakeSettings.whenDisplayConnected = false
        let awake = StayAwakeController(settings: awakeSettings, hasLid: true, listensToTheRealLid: false)
        let model = PopoverModel(settings: settings, registry: registry, preview: preview, sensor: sensor,
                                 thumbnails: try TransitionThumbnailRenderer(), stayAwake: awake, lidSound: sound)
        model.page = .sound
        return (model, sound)
    }

    private func render(_ model: PopoverModel, name: String) throws {
        let hosting = NSHostingView(rootView: PopoverView(model: model))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        XCTAssertEqual(size.width, PopoverView.width)
        XCTAssertEqual(size.height, PopoverHeader.height + 1 + PopoverView.bodyHeight + 1 + 48, accuracy: 1, "one panel size, whatever the page shows")
        hosting.frame = NSRect(origin: .zero, size: size)
        let container = PanelChrome(frame: hosting.frame)
        container.addSubview(hosting)
        container.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let rep = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: container.bounds))
        container.cacheDisplay(in: container.bounds, to: rep)
        XCTAssertGreaterThan(rep.pixelsWide, 0)
        if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("sound-\(name).png"))
        }
    }

    func testThePageInItsStates() throws {
        let (off, _) = try makeModel(on: false)
        XCTAssertEqual(off.lidSoundTabLine, "Off")
        try render(off, name: "off")

        let (on, sound) = try makeModel(on: true)
        XCTAssertEqual(on.lidSoundTabLine, "3 sounds · random")
        try render(on, name: "on")
        sound.settings.mode = .inOrder
        on.showingSoundSettings = true
        try render(on, name: "settings")
        on.showingSoundSettings = false

        // One sound, playing: the glyph moves and the tab says so.
        sound.preview(sound.settings.items[0])
        XCTAssertEqual(sound.playing, "Click")
        XCTAssertEqual(on.lidSoundTabLine, "Playing Click…")
        try render(on, name: "playing")
        players.last?.onFinish?()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(sound.playing)

        // A long file, clipped: where it starts from is on the page.
        var song = sound.settings.items[1]
        song.duration = 200; song.clipStart = 72
        sound.settings.update(song)
        XCTAssertTrue(sound.settings.items[1].isLong)
        try render(on, name: "long")
        song.duration = 0.7; song.clipStart = 0
        sound.settings.update(song)

        // A part cut out and named, and a rename.
        var click = sound.settings.items[0]
        click.duration = 14
        sound.settings.update(click)
        on.cutSound(sound.settings.items[0], from: 2, to: 6.5, name: "Verse")
        XCTAssertEqual(sound.settings.shown.map(\.displayName), ["Click", "Verse", "Breath", "Hum"], "under its source")
        XCTAssertEqual(sound.settings.shown[1].heardLength, 4.5)
        on.renameSound(sound.settings.shown[1], to: "Chorus")
        on.renameSound(sound.settings.shown[0], to: "Chorus")
        XCTAssertEqual(sound.settings.shown.map(\.displayName), ["Chorus 2", "Chorus", "Breath", "Hum"], "never two the same")
        on.renameSound(sound.settings.shown[0], to: "   ")
        XCTAssertEqual(sound.settings.shown[0].displayName, "Chorus 2", "a blank name is no name")
        on.cutSound(sound.settings.items[0], from: 1, to: 1.2, name: "Blip")
        XCTAssertEqual(on.importNote, "A part is half a second at least.")
        on.importNote = nil
        try render(on, name: "parts")
        // The editor open on a row: the shape of the sound, with the part on it.
        sound.readWaveformNow(for: sound.settings.shown[2])
        XCTAssertEqual(sound.waveforms["Breath.wav"]?.count, LidSoundController.waveformBuckets)
        XCTAssertNotNil(sound.waveform(for: sound.settings.shown[2]), "read once, kept")
        on.cuttingSoundForTest = sound.settings.shown[2].id
        try render(on, name: "cut")
        on.cuttingSoundForTest = nil
        on.removeSound(sound.settings.shown[0])
        XCTAssertEqual(sound.library.state(of: sound.settings.shown[0]), .ok, "the part outlives its source row")
        on.removeSound(sound.settings.shown[0])
        XCTAssertEqual(sound.settings.shown.map(\.displayName), ["Breath", "Hum"])
        click.duration = 0.06
        sound.settings.update(click)
        on.restoreStarterSounds()
        XCTAssertEqual(sound.settings.shown.map(\.displayName), ["Click", "Breath", "Hum"])

        // A file that went missing, and an import that was refused.
        let gone = LidSoundItem(id: UUID(), fileName: "Rain.wav", displayName: "Rain", enabled: true, isStarter: false, duration: 2.4)
        sound.settings.items.append(gone)
        XCTAssertEqual(sound.library.state(of: gone), .missing)
        on.importNote = LidSoundText.refusal(.tooLong(45), name: "Song.mp3")
        try render(on, name: "missing-and-refused")
        on.importNote = nil
        sound.settings.items.removeAll { $0.id == gone.id }

        // Muted, Stay quiet: the page says so and offers the way to change it.
        output.muted = true
        sound.setLiveUpdates(true)
        XCTAssertEqual(on.lidSoundTabLine, "Muted")
        try render(on, name: "muted")
        sound.settings.whenMuted = .unmute
        XCTAssertEqual(on.lidSoundTabLine, "3 sounds · in order")
        output.muted = false
        sound.setLiveUpdates(true)

        // Nothing chosen, then nothing at all.
        for var item in sound.settings.items { item.enabled = false; sound.settings.update(item) }
        XCTAssertEqual(on.lidSoundTabLine, "No sound chosen")
        try render(on, name: "none-chosen")
        for item in sound.settings.items { on.removeSound(item) }
        XCTAssertEqual(on.lidSoundTabLine, "No sounds yet")
        XCTAssertEqual(sound.settings.items.count, 3, "starters are hidden, never deleted")
        try render(on, name: "none")
        on.restoreStarterSounds()
        XCTAssertEqual(sound.settings.shown.count, 3)

        let (edges, _) = try makeModel(on: true, capability: .lidStateOnly)
        XCTAssertTrue(LidSoundText.copy(edges.lidSound.situation()).detail.contains("only reports the lid shut"))
        sound.shutDown()
    }

    /// Three tabs beside the wordmark, the window button and the switch: the header's natural
    /// width must fit the panel in both forms, with the longest lines each tab can carry.
    func testTheHeaderFitsWithThreeTabs() throws {
        let (model, sound) = try makeModel(on: true)
        sound.settings.mode = .inOrder
        let since = Date().addingTimeInterval(-47 * 60)
        model.stayAwake.settings.hasConsented = true
        model.stayAwake.settings.isOn = true
        model.stayAwake.arbiter.add(AwakeSnapshotTests.FixedSource([
            HoldReason(id: "working:cursor", kind: .working, title: "Cursor", tool: "Claude Code", since: since)]))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(model.lidEffectsLine, "Fold · plain fade for now", "the longest Lid effects line")
        for hosted in [false, true] {
            let header = NSHostingView(rootView: PopoverHeader(model: model, hostedInWindow: hosted).fixedSize(horizontal: true, vertical: false).tunerThemed())
            header.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(header.fittingSize.width, PopoverView.width, "three tabs do not fit the header (window form: \(hosted))")
        }
        model.page = .awake
        try render(model, name: "header-three-tabs")
        sound.shutDown()
    }

    /// The glyph's clock is a pure function of time: it rests in a shape, breathes a little
    /// when on, moves to a sound, and leans toward a pointer.
    func testTheGlyph() {
        XCTAssertEqual(LidSoundGlyph.rest, [0.4, 1, 0.6])
        XCTAssertEqual(LidSoundGlyph.heights(at: 3, playing: false, breathing: false), LidSoundGlyph.rest, "off: still")
        for t in stride(from: 0.0, to: 6, by: 0.1) {
            for playing in [false, true] {
                let heights = LidSoundGlyph.heights(at: t, playing: playing, breathing: true)
                XCTAssertEqual(heights.count, 3)
                XCTAssertTrue(heights.allSatisfy { $0 >= 0.15 && $0 <= 1 })
            }
            let breath = LidSoundGlyph.heights(at: t, playing: false, breathing: true)
            for (b, r) in zip(breath, LidSoundGlyph.rest) { XCTAssertEqual(b, r, accuracy: 0.07, "a breath, not a dance") }
        }
        // The pointer on the right lifts the right bar and lets the left one dip, eased in.
        let before = LidSoundGlyph.heights(at: 10, playing: false, breathing: false)
        let leaning = LidSoundGlyph.heights(at: 10.5, playing: false, breathing: false, hover: .init(x: 1, since: 10))
        XCTAssertGreaterThan(leaning[2], before[2])
        XCTAssertLessThan(leaning[0], before[0])
        let justStarted = LidSoundGlyph.heights(at: 10.01, playing: false, breathing: false, hover: .init(x: 1, since: 10))
        XCTAssertLessThan(justStarted[2] - before[2], leaning[2] - before[2], "eased in over a moment, not a jump")
    }
}

extension LidSoundSnapshotTests {
    /// A row carried to a new place changes the order, which is the order "In order" plays.
    func testMovingARow() throws {
        let (model, sound) = try makeModel(on: true)
        XCTAssertEqual(sound.settings.shown.map(\.displayName), ["Click", "Breath", "Hum"])
        model.moveSound(from: 2, to: 0)
        XCTAssertEqual(sound.settings.shown.map(\.displayName), ["Hum", "Click", "Breath"])
        model.moveSound(from: 0, to: 2)
        XCTAssertEqual(sound.settings.shown.map(\.displayName), ["Click", "Breath", "Hum"])
        model.moveSound(from: 1, to: 1)
        model.moveSound(from: 5, to: 0)
        XCTAssertEqual(sound.settings.shown.map(\.displayName), ["Click", "Breath", "Hum"], "nothing to do, nothing done")
        // A hidden starter stays hidden and out of the way.
        model.removeSound(sound.settings.shown[1])
        model.moveSound(from: 1, to: 0)
        XCTAssertEqual(sound.settings.shown.map(\.displayName), ["Hum", "Click"])
        XCTAssertEqual(sound.settings.items.count, 3)
        sound.settings.mode = .inOrder
        sound.settings.nextIndex = 0
        XCTAssertEqual(LidSoundText.copy(sound.situation()).detail.contains("Next: Hum."), true, "the order is what In order plays")
        sound.shutDown()
    }
}
