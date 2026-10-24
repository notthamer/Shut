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

    private func makeModel(on: Bool, items: [LidSoundItem]? = nil, capability: HingeCapability = .continuousAngle,
                           manifest: [LidSoundLibrary.ManifestPack] = LidSoundLibrary.fallbackPacks) throws -> (PopoverModel, LidSoundController) {
        let suite = UserDefaults(suiteName: "LidSoundSnapshot-\(UUID().uuidString)")!
        let soundSettings = LidSoundSettings(defaults: suite, manifest: manifest)
        soundSettings.isOn = on
        if let items { soundSettings.items = items }
        let settings = AppSettings(defaults: suite)
        let registry = TransitionRegistry(transitions: TransitionCatalog.make(), currentID: "fold")
        let sensor = LidSensorMonitor(defaults: nil)
        let preview = try PreviewModel(registry: registry, settings: settings, sensor: sensor)
        preview.capturePlaceholder()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LidSoundSnapshot-\(UUID().uuidString)")
        let sound = LidSoundController(settings: soundSettings, appSettings: settings, sensor: sensor, hasLid: true,
                                       library: LidSoundLibrary(directory: folder, bundle: AppAssets.resourceBundle(), packs: manifest), output: output,
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
        XCTAssertEqual(sound.settings.items.map(\.displayName), ["Click", "Verse", "Breath", "Hum"], "under its source")
        XCTAssertEqual(sound.settings.items[1].heardLength, 4.5)
        on.renameSound(sound.settings.items[1], to: "Chorus")
        on.renameSound(sound.settings.items[0], to: "Chorus")
        XCTAssertEqual(sound.settings.items.map(\.displayName), ["Chorus 2", "Chorus", "Breath", "Hum"], "never two the same")
        on.renameSound(sound.settings.items[0], to: "   ")
        XCTAssertEqual(sound.settings.items[0].displayName, "Chorus 2", "a blank name is no name")
        on.cutSound(sound.settings.items[0], from: 1, to: 1.2, name: "Blip")
        XCTAssertEqual(on.importNote, "A part is half a second at least.")
        on.importNote = nil
        try render(on, name: "parts")
        // Seven sounds: the well is as long as the list and the column scrolls once; no
        // scroll inside a scroll, however many there are.
        for i in 1...3 { on.cutSound(sound.settings.items[0], from: Double(i), to: Double(i) + 1, name: "Part \(i)") }
        XCTAssertEqual(on.stage.count, 7)
        try render(on, name: "many")
        for part in sound.settings.items where part.displayName.hasPrefix("Part ") { on.removeSound(part) }
        XCTAssertEqual(on.stage.count, 4)
        // The editor open on a row: the shape of the sound, with the part on it.
        sound.readWaveformNow(for: sound.settings.items[2])
        XCTAssertEqual(sound.waveforms["Breath.wav"]?.count, LidSoundController.waveformBuckets)
        XCTAssertNotNil(sound.waveform(for: sound.settings.items[2]), "read once, kept")
        on.cuttingSoundForTest = sound.settings.items[2].id
        try render(on, name: "cut")
        on.cuttingSoundForTest = nil
        // Several parts at once, named; a blank name gets the part's own; a blip is refused, once.
        let long = sound.settings.items[0]
        XCTAssertEqual(long.duration, 14)
        on.cutSounds(long, parts: [(0...2, "In"), (2...4, "  "), (4...4.1, "Blip"), (5...5.2, "Blip 2")])
        XCTAssertEqual(Array(sound.settings.items.map(\.displayName).prefix(3)), ["Chorus 2", "In", "Chorus 2 · 0:02–0:04"])
        XCTAssertEqual(on.importNote, "A part is half a second at least.", "said once, however many were refused")
        on.importNote = nil
        for part in sound.settings.items where part.isCut && part.displayName != "Chorus" { on.removeSound(part) }
        on.removeSound(sound.settings.items[0])   // a starter: off the lid, still on its shelf
        XCTAssertEqual(sound.library.state(of: sound.settings.items[0]), .ok, "the part outlives its source on the lid")
        XCTAssertEqual(on.stage.map(\.displayName), ["Chorus", "Breath", "Hum"])
        on.removeSound(sound.settings.items[1])   // the user's own cut: gone
        XCTAssertEqual(on.stage.map(\.displayName), ["Breath", "Hum"])
        XCTAssertEqual(sound.settings.items.map(\.displayName), ["Chorus 2", "Breath", "Hum"], "the starter waits on its shelf")
        click.duration = 0.06
        sound.settings.update(click)   // the row as it was: its name back, on the lid
        XCTAssertEqual(on.stage.map(\.displayName), ["Click", "Breath", "Hum"])

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
        XCTAssertEqual(on.lidSoundTabLine, "In order · next Click")
        output.muted = false
        sound.setLiveUpdates(true)

        // Nothing on the lid, then nothing at all (a bundle with no sounds: never on a real Mac).
        for var item in sound.settings.items { item.enabled = false; sound.settings.update(item) }
        XCTAssertEqual(on.lidSoundTabLine, "Nothing on the lid")
        try render(on, name: "stage-empty")
        let shelved = sound.settings.items
        sound.settings.items = []
        XCTAssertEqual(on.lidSoundTabLine, "No sounds yet")
        try render(on, name: "none")
        sound.settings.items = shelved
        for item in shelved { on.setOnLid(item, true) }
        XCTAssertEqual(on.stage.count, 3)

        // A sleep from the last close still going, and the note about a slow one.
        on.sleep.sleepBegan(now: Date().addingTimeInterval(-12))
        XCTAssertEqual(on.lidSoundTabLine, "Still going to sleep")
        try render(on, name: "sleep-pending")
        on.sleep.woke(now: Date())
        XCTAssertEqual(on.lidSoundTabLine, "In order · next Click")
        on.sleep.sleepBegan(now: Date().addingTimeInterval(-31))
        on.sleep.woke(now: Date())
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNil(on.sleep.slow, "with no power log to read, nothing is pinned on anyone")

        // The stage and the packs: a sound on the lid is picked, one in its pack only is not.
        // The packs open one at a time; a drop lands a sound where it is dropped; Play this
        // pack makes the stage the pack; a user's pack is a playlist of their own.
        let (packed, packedSound) = try makeModel(on: true)
        XCTAssertNil(packed.openPackID, "every pack closed to start")
        XCTAssertEqual(packed.shelf("generated").map(\.displayName), ["Click", "Breath", "Hum"])
        packed.showingSoundTiming = true
        try render(packed, name: "packs-closed")
        packed.showingSoundTiming = false
        packed.showingBundledPacks = true
        packed.openPackID = "generated"
        packed.setOnLid(packedSound.settings.items[1], false)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Click", "Hum"])
        XCTAssertEqual(packed.lidSoundTabLine, "2 sounds · random")
        XCTAssertEqual(packed.shelf("generated").count, 3, "off the lid, still in its pack")
        try render(packed, name: "packs-open")
        // Dropped on the stage at a place, it lands there; dropped again, it moves.
        let breath = try XCTUnwrap(packedSound.settings.items.first { $0.displayName == "Breath" })
        packed.putOnLid(breath.id, at: 0)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Breath", "Click", "Hum"])
        packed.putOnLid(breath.id, at: 3)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Click", "Hum", "Breath"], "past the last row: last")
        packed.putOnLid(breath.id, at: 1)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Click", "Breath", "Hum"])
        packed.putOnLid(breath.id, at: 1)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Click", "Breath", "Hum"], "dropped where it was: nothing moves")
        // A whole pack dropped on the stage: every sound in it, together, where it was dropped.
        for name in ["Breath", "Click"] { packed.setOnLid(try XCTUnwrap(packedSound.settings.items.first { $0.displayName == name }), false) }
        XCTAssertEqual(packed.stage.map(\.displayName), ["Hum"])
        packed.putPackOnLid("generated", at: 0)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Click", "Breath", "Hum"], "the pack's own order; Hum, already on, joins the group")
        packed.putPackOnLid("generated", at: 3)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Click", "Breath", "Hum"], "nothing else on the lid: the group is the stage")
        let voices = try XCTUnwrap(packed.newPack(named: "Voices"))
        packed.moveSound(breath, to: voices.id)
        XCTAssertEqual(packedSound.settings.packs.map(\.name), ["Mine", "Voices", "Starters"])
        packed.openPackID = voices.id
        XCTAssertEqual(packed.shelf(voices.id).map(\.displayName), ["Breath"])
        packed.playOnly(voices)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Breath"], "Play this pack: the stage is the pack")
        let starters = try XCTUnwrap(packedSound.settings.packs.first { $0.id == "generated" })
        packed.setShelf(starters, onLid: true)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Click", "Breath", "Hum"], "Add all: list order, whatever the pack")
        // Reorder on the stage: the sounds on the lid take one another's places; a sound in
        // its pack only keeps its place in the list.
        packed.moveSound(from: 0, to: 2)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Breath", "Hum", "Click"])
        XCTAssertEqual(packedSound.settings.items.first { $0.displayName == "Breath" }?.packID, voices.id, "a move on the stage changes no pack")
        packed.setOnLid(try XCTUnwrap(packedSound.settings.items.first { $0.displayName == "Hum" }), false)
        packed.moveSound(from: 1, to: 0)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Click", "Breath"])
        XCTAssertEqual(packedSound.settings.items.map(\.displayName), ["Click", "Hum", "Breath"])
        packed.removePack(voices)
        XCTAssertEqual(packedSound.settings.items.first { $0.displayName == "Breath" }?.packID, LidSoundPack.mineID, "a removed pack's sounds go to Mine")
        XCTAssertNil(packed.openPackID, "the open pack gone: none open")
        packed.removePack(starters)
        XCTAssertEqual(packedSound.settings.packs.count, 2, "a bundled pack is a playlist that came with the app: it cannot be removed")
        packed.setShelf(starters, onLid: false)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Breath"], "Take all off: the pack's sounds leave the stage")
        packed.openPackID = LidSoundPack.mineID
        try render(packed, name: "stage")
        // In order shows its queue: numbers, NEXT on the next, and the band's own line.
        packed.setShelf(starters, onLid: true)
        packedSound.settings.mode = .inOrder
        packedSound.settings.nextIndex = 1
        XCTAssertEqual(packed.nextOnLid?.displayName, packed.stage[1].displayName)
        try render(packed, name: "stage-queue")
        packedSound.settings.mode = .random
        // A drag from a pack in flight: the stage says Drop here before the pointer arrives.
        packed.dragBegan()
        XCTAssertTrue(packed.dragging)
        try render(packed, name: "stage-dragging")
        packed.dragBegan()   // the render above took longer than the grace the start gets
        packed.pointerMoved()
        XCTAssertTrue(packed.dragging, "a pointer event right after the start is the start itself")
        packed.draggingSince = Date().addingTimeInterval(-1)
        packed.pointerMoved()
        XCTAssertFalse(packed.dragging, "the first movement after the drag ends it")
        packed.setShelf(starters, onLid: false)
        packed.setOnLid(try XCTUnwrap(packedSound.settings.items.first { $0.displayName == "Breath" }), false)
        XCTAssertTrue(packed.stage.isEmpty)
        try render(packed, name: "stage-empty-zone")
        XCTAssertTrue(packedSound.settings.hasPutOnLid, "a sound was put on the lid by hand above: the hint is done")
        packed.setOnLid(try XCTUnwrap(packedSound.settings.items.first { $0.displayName == "Breath" }), true)
        // Added into a pack: in it, off the lid; added from the stage: in Mine, on the lid.
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("LidSoundImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let rain = scratch.appendingPathComponent("Rain.wav")
        try Self.tone(seconds: 1, tone: 440).write(to: rain)
        packed.importSounds([rain], to: .pack(starters))
        XCTAssertEqual(packedSound.settings.items.last?.packID, "generated")
        XCTAssertEqual(packedSound.settings.items.last?.enabled, false)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Breath"])
        let thunder = scratch.appendingPathComponent("Thunder.wav")
        try Self.tone(seconds: 1, tone: 220).write(to: thunder)
        packed.importSounds([thunder])
        XCTAssertEqual(packedSound.settings.items.last?.packID, LidSoundPack.mineID)
        XCTAssertEqual(packed.stage.map(\.displayName), ["Breath", "Thunder"])
        for own in packedSound.settings.items where !own.isStarter { packed.removeSound(own) }
        // Edit: tick rows, Remove takes them off the lid together, and Edit ends.
        packed.setShelf(starters, onLid: true)
        XCTAssertEqual(packed.stage.count, 3)
        packed.editingStage = true
        packed.toggleStageSelection(packed.stage[0].id)
        packed.toggleStageSelection(packed.stage[2].id)
        XCTAssertEqual(packed.stageSelection.count, 2)
        try render(packed, name: "stage-editing")
        packed.removeSelectedFromLid()
        XCTAssertEqual(packed.stage.map(\.displayName), ["Hum"])
        XCTAssertFalse(packed.editingStage)
        XCTAssertTrue(packed.stageSelection.isEmpty)
        XCTAssertEqual(packedSound.settings.items.count, 3, "off the lid, not gone")
        packed.editingStage = true
        packed.selectWholeStage(true)
        XCTAssertEqual(packed.stageSelection.count, 1)
        packed.selectWholeStage(false)
        XCTAssertTrue(packed.stageSelection.isEmpty)
        packed.editingStage = false
        packedSound.shutDown()

        // A new user with a pack that is an offer: in its pack, off the lid, one click from it.
        let offer = [LidSoundLibrary.ManifestPack(id: "adhkar", name: "Adhkar", credit: "Recorded by the author.", onByDefault: false, sounds: [
            LidSoundLibrary.Starter(name: "اذكر الله", file: "Adhkar.mp3", from: 2.7, to: 4.7),
            LidSoundLibrary.Starter(name: "توكل على الله", file: "Adhkar.mp3", from: 11.2, to: 13.1)])] + LidSoundLibrary.fallbackPacks
        let (offered, offeredSound) = try makeModel(on: true, manifest: offer)
        XCTAssertEqual(offered.stage.map(\.displayName), ["Click", "Breath", "Hum"], "not on the lid until asked for")
        XCTAssertEqual(offeredSound.settings.packs.map(\.name), ["Mine", "Adhkar", "Starters"])
        XCTAssertEqual(offered.shelf("adhkar").count, 2)
        offered.showingBundledPacks = true
        offered.openPackID = "adhkar"
        try render(offered, name: "packs-offer")
        offered.setOnLid(offered.shelf("adhkar")[0], true)
        XCTAssertEqual(offered.stage.count, 4)
        XCTAssertEqual(offered.lidSoundTabLine, "4 sounds · random")
        offeredSound.shutDown()

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
        model.sleep.sleepBegan(now: Date().addingTimeInterval(-12))   // "Still going to sleep" on two tabs at once
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        // The longest Lid effects line on a MacBook; a Mac with no built-in display (the CI
        // runner) says the lid has nothing to play, which is shorter, so the fit is checked
        // at its widest on the hardware the panel is for.
        XCTAssertTrue(["Fold · plain fade for now", "Lid shut · nothing to play"].contains(model.lidEffectsLine), model.lidEffectsLine)
        XCTAssertEqual(model.lidSoundTabLine, "Still going to sleep")
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
    /// A one-second 16-bit mono WAV of a tone, written the way scripts/make-sounds.swift does.
    static func tone(seconds: Double, tone: Double) -> Data {
        let rate = 8_000.0, count = Int(seconds * rate)
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + count * 2)); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(UInt32(count * 2))
        for i in 0..<count { put(Int16(sin(Double(i) / rate * tone * 2 * .pi) * 8_000)) }
        return data
    }

    /// A row carried to a new place changes the order, which is the order "In order" plays.
    func testMovingARow() throws {
        let (model, sound) = try makeModel(on: true)
        XCTAssertEqual(sound.settings.items.map(\.displayName), ["Click", "Breath", "Hum"])
        model.moveSound(from: 2, to: 0)
        XCTAssertEqual(sound.settings.items.map(\.displayName), ["Hum", "Click", "Breath"])
        model.moveSound(from: 0, to: 2)
        XCTAssertEqual(sound.settings.items.map(\.displayName), ["Click", "Breath", "Hum"])
        model.moveSound(from: 1, to: 1)
        model.moveSound(from: 5, to: 0)
        XCTAssertEqual(sound.settings.items.map(\.displayName), ["Click", "Breath", "Hum"], "nothing to do, nothing done")
        // A sound on its shelf keeps its place in the list; the stage reorders around it.
        model.removeSound(sound.settings.items[1])   // Breath, a starter: off the lid, on its shelf
        XCTAssertEqual(model.stage.map(\.displayName), ["Click", "Hum"])
        model.moveSound(from: 1, to: 0)
        XCTAssertEqual(model.stage.map(\.displayName), ["Hum", "Click"])
        XCTAssertEqual(sound.settings.items.map(\.displayName), ["Hum", "Breath", "Click"])
        sound.settings.mode = .inOrder
        sound.settings.nextIndex = 0
        XCTAssertEqual(sound.situation().next, "Hum", "the order is what In order plays")
        XCTAssertEqual(model.nextOnLid?.displayName, "Hum")
        XCTAssertEqual(model.lidSoundTabLine, "In order · next Hum")
        model.playNext(model.stage[1])
        XCTAssertEqual(model.nextOnLid?.displayName, "Click", "Play this next: In order carries on from that row")
        sound.settings.mode = .random
        XCTAssertNil(model.nextOnLid)
        sound.settings.lastPickID = model.stage[0].id
        XCTAssertEqual(model.lastPlayedOnLid?.displayName, "Hum", "Random: the one that just played")
        sound.shutDown()
    }
}
