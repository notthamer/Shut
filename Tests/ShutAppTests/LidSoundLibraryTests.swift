import XCTest
@testable import ShutApp

/// Files in, files out, and which one a close picks. A temp folder stands in for Shut's.
final class LidSoundLibraryTests: XCTestCase {
    private var folder: URL!
    private var library: LidSoundLibrary!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("LidSound-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        library = LidSoundLibrary(directory: folder.appendingPathComponent("Sounds"), bundle: nil)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    /// A silent 16-bit mono WAV of the given length, written the way scripts/make-sounds.swift does.
    private func wav(seconds: Double, name: String, tone: Double = 440) throws -> URL {
        let rate = 8_000.0, count = Int(seconds * rate)
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + count * 2)); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(UInt32(count * 2))
        for i in 0..<count { put(Int16(sin(Double(i) / rate * tone * 2 * .pi) * 8_000)) }
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testImportCopiesAndNamesAndRefuses() throws {
        let rain = try wav(seconds: 1.5, name: "Rain.wav")
        let first = try library.importFile(rain, existing: []).get()
        XCTAssertEqual(first.displayName, "Rain")
        XCTAssertEqual(first.fileName, "Rain.wav")
        XCTAssertEqual(try XCTUnwrap(first.duration), 1.5, accuracy: 0.01)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: first)!.path), "copied into Shut's folder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rain.path), "the original is left alone")
        XCTAssertEqual(library.state(of: first), .ok)

        // The same bytes again is one row; a different file with the same name gets a number.
        XCTAssertEqual(library.importFile(rain, existing: [first]), .failure(.duplicate(of: first.id)))
        let other = try wav(seconds: 0.5, name: "Rain.wav", tone: 880)
        let second = try library.importFile(other, existing: [first]).get()
        XCTAssertEqual(second.displayName, "Rain 2")
        XCTAssertEqual(second.fileName, "Rain 2.wav")

        // Longer than the lid plays: taken in, to be clipped. An album is not.
        let long = try wav(seconds: 31, name: "Long.wav")
        let song = try library.importFile(long, existing: []).get()
        XCTAssertTrue(song.isLong)
        XCTAssertEqual(song.clipStart, 0, "from the start until the user chooses")
        let album = try wav(seconds: 601, name: "Album.wav")
        guard case .failure(.tooLong(let seconds)) = library.importFile(album, existing: []) else { return XCTFail("ten minutes and more is refused") }
        XCTAssertEqual(seconds, 601, accuracy: 0.01)
        let text = folder.appendingPathComponent("Notes.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertEqual(library.importFile(text, existing: []), .failure(.unreadable))

        // Gone behind Shut's back: the row says so; removing deletes an own file.
        try FileManager.default.removeItem(at: library.url(for: first)!)
        XCTAssertEqual(library.state(of: first), .missing)
        XCTAssertEqual(library.candidates([first, second]).map(\.id), [second.id])
        library.remove(second)
        XCTAssertEqual(library.state(of: second), .missing)
    }

    /// A part cut from a sound shares its file; the file lives as long as any row plays it.
    func testCutsShareTheFile() throws {
        let song = try library.importFile(try wav(seconds: 14, name: "Song.wav"), existing: []).get()
        let verse = try LidSoundLibrary.cut(song, from: 2, to: 6.5, name: "Verse", existing: [song]).get()
        XCTAssertTrue(verse.isCut)
        XCTAssertEqual(verse.fileName, song.fileName)
        XCTAssertEqual(verse.clipStart, 2)
        XCTAssertEqual(verse.clipEnd, 6.5)
        XCTAssertEqual(try XCTUnwrap(verse.heardLength), 4.5, accuracy: 0.01)
        XCTAssertFalse(verse.isLong)
        XCTAssertNil(verse.contentHash, "a part never counts as the same file added twice")
        XCTAssertEqual(LidSoundLibrary.cut(song, from: 2, to: 2.2, name: "Blip", existing: []), .failure(.tooShort))
        XCTAssertEqual(LidSoundLibrary.cut(song, from: 10, to: 20, name: "Past", existing: []), .failure(.outside))
        XCTAssertEqual(try LidSoundLibrary.cut(song, from: 0, to: 1, name: "Verse", existing: [song, verse]).get().displayName, "Verse 2")

        library.remove(song, keptBy: [song, verse])
        XCTAssertEqual(library.state(of: verse), .ok, "the source row went; the part still plays")
        library.remove(verse, keptBy: [verse])
        XCTAssertEqual(library.state(of: song), .missing, "the last row playing the file takes it with it")
    }

    /// The shape: one peak per slice, loudest at 1, and a louder second half shows as such.
    func testTheShapeOfASound() throws {
        let quietThenLoud = try wav(seconds: 2, name: "Swell.wav")
        let peaks = try XCTUnwrap(LidSoundLibrary.peaks(of: quietThenLoud, buckets: 20))
        XCTAssertEqual(peaks.count, 20)
        XCTAssertEqual(peaks.max(), 1)
        XCTAssertTrue(peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertNil(LidSoundLibrary.peaks(of: folder.appendingPathComponent("nothing.wav"), buckets: 20))
        let click = LidSoundLibrary(directory: folder, bundle: AppAssets.resourceBundle())
        let starter = LidSoundItem(id: UUID(), fileName: "Click.wav", displayName: "Click", enabled: true, isStarter: true)
        let shape = try XCTUnwrap(LidSoundLibrary.peaks(of: try XCTUnwrap(click.url(for: starter)), buckets: 140))
        XCTAssertGreaterThan(shape[0], shape[139], "a click is loud at once and gone by the end")
    }

    /// Three words with silence between them are three parts; a blip joins its neighbour;
    /// a hum with no silence is one part.
    func testPartsBySilence() {
        func burst(_ on: [ClosedRange<Int>], count: Int = 140) -> [Float] {
            (0..<count).map { i in on.contains { $0.contains(i) } ? 0.9 : 0.01 }
        }
        let words = LidSoundLibrary.parts(in: burst([0...19, 40...59, 90...119]), duration: 14)
        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(words[0].lowerBound, 0, accuracy: 0.01)
        XCTAssertEqual(words[0].upperBound, 2.05, accuracy: 0.01, "a little air after")
        XCTAssertEqual(words[1].lowerBound, 3.95, accuracy: 0.01, "and before")
        XCTAssertEqual(words[2].upperBound, 12.05, accuracy: 0.01)
        XCTAssertEqual(LidSoundLibrary.parts(in: burst([0...139]), duration: 14).count, 1, "no silence: one part")
        XCTAssertEqual(LidSoundLibrary.parts(in: burst([0...19, 21...39]), duration: 14).count, 1, "a 0.1 s pause is not a gap")
        XCTAssertEqual(LidSoundLibrary.parts(in: burst([0...19, 60...61, 100...119]), duration: 14).count, 2, "a blip joins its neighbour")
        XCTAssertEqual(LidSoundLibrary.parts(in: burst((0..<20).map { ($0 * 7)...($0 * 7 + 3) }), duration: 14).count, 12, "twelve at most")
        XCTAssertTrue(LidSoundLibrary.parts(in: [], duration: 14).isEmpty)
        XCTAssertTrue(LidSoundLibrary.parts(in: burst([]), duration: 14).isEmpty, "all silence: nothing to cut")
    }

    func testUniqueNames() {
        XCTAssertEqual(LidSoundLibrary.uniqueName("Rain", among: []), "Rain")
        XCTAssertEqual(LidSoundLibrary.uniqueName("rain", among: ["Rain"]), "rain 2", "case does not make a new name")
        XCTAssertEqual(LidSoundLibrary.uniqueName("Rain", among: ["Rain", "Rain 2"]), "Rain 3")
        XCTAssertEqual(LidSoundLibrary.uniqueName("  ", among: []), "Sound")
    }

    func testStartersComeFromTheBundleAndAStarterIsNeverDeleted() throws {
        let bundled = LidSoundLibrary(directory: folder, bundle: AppAssets.resourceBundle())
        let packs = bundled.packs()
        XCTAssertEqual(packs.map(\.id), ["generated", "pops", "toys", "machines", "retro", "night", "encore", "ode-to-joy", "adhkar"], "the manifest, in packs")
        XCTAssertEqual(packs.map(\.sounds.count), [8, 6, 7, 10, 8, 8, 8, 15, 5])
        XCTAssertTrue(packs.allSatisfy { $0.credit != nil }, "where a bundled pack's audio came from is written beside it")
        let starters = bundled.starters()
        XCTAssertEqual(starters.count, 75)
        XCTAssertEqual(starters.prefix(8).map(\.name), ["Click", "Blob", "Pop", "Boing", "Coin", "CRT off", "Breath", "Hum"], "the fun ones first, the 0.4.0 three kept")
        XCTAssertEqual(Set(starters.map(\.file)).count, 57, "one file per sound; the tune's notes and the adhkar are parts of one file each")
        XCTAssertEqual(bundled.starterURLs().count, 57, "all in the bundle")
        XCTAssertTrue(bundled.startersAreComplete)
        let verse = try XCTUnwrap(starters.last)
        XCTAssertTrue(verse.item().isCut && verse.item().isStarter && verse.item().fromManifest)
        XCTAssertEqual(verse.item().packID, "adhkar")
        let notes = starters.filter { $0.packID == "ode-to-joy" }
        XCTAssertEqual(notes.count, 15)
        XCTAssertTrue(notes.allSatisfy { $0.item().isCut && $0.file == "OdeToJoy.m4a" }, "a tune is one file, each note a part of it")
        XCTAssertTrue(zip(notes, notes.dropFirst()).allSatisfy { ($0.to ?? 0) <= ($1.from ?? 0) }, "the notes do not overlap, so In order plays the tune")
        // An older list, saved before `fromManifest` and packs: whole starters were from the manifest, cuts were not.
        let old = Data(#"[{"id":"\#(UUID().uuidString)","fileName":"Click.wav","displayName":"Click","enabled":true,"isStarter":true},{"id":"\#(UUID().uuidString)","fileName":"Click.wav","displayName":"Tick","enabled":true,"isStarter":true,"isCut":true,"clipEnd":0.03}]"#.utf8)
        let decoded = try JSONDecoder().decode([LidSoundItem].self, from: old)
        XCTAssertEqual(decoded.map(\.fromManifest), [true, false])
        XCTAssertEqual(decoded.map(\.packID), [LidSoundPack.startersID, LidSoundPack.mineID], "settled against the manifest at launch; the user's cut is theirs")
        XCTAssertEqual(decoded.map(\.kept), [false, false])
        XCTAssertEqual(library.packs().map(\.id), ["generated"], "no manifest: the generated three, as one pack")
        let click = LidSoundItem(id: UUID(), fileName: "Click.wav", displayName: "Click", enabled: true, isStarter: true)
        XCTAssertEqual(bundled.state(of: click), .ok)
        XCTAssertEqual(try XCTUnwrap(LidSoundLibrary.duration(of: try XCTUnwrap(bundled.url(for: click)))), 0.06, accuracy: 0.01)
        bundled.remove(click)
        XCTAssertEqual(bundled.state(of: click), .ok, "a starter is hidden by the settings, not deleted")
        XCTAssertEqual(library.state(of: click), .missing, "no bundle: it degrades to a missing row, never a crash")
    }

    func testThePick() {
        let a = LidSoundItem(id: UUID(), fileName: "a", displayName: "A", enabled: true, isStarter: false)
        let b = LidSoundItem(id: UUID(), fileName: "b", displayName: "B", enabled: true, isStarter: false)
        let c = LidSoundItem(id: UUID(), fileName: "c", displayName: "C", enabled: true, isStarter: false)
        XCTAssertNil(LidSoundLibrary.pick(from: [], mode: .random, lastPickID: nil, nextIndex: 0))
        XCTAssertEqual(LidSoundLibrary.pick(from: [a], mode: .random, lastPickID: a.id, nextIndex: 0)?.item, a, "alone, it may repeat")
        var last: UUID? = a.id
        for _ in 0..<1000 {
            let pick = LidSoundLibrary.pick(from: [a, b, c], mode: .random, lastPickID: last, nextIndex: 0)!.item
            XCTAssertNotEqual(pick.id, last, "random never plays the same sound twice running")
            last = pick.id
        }
        // The dice are injectable: 0 is "the first that is not the last one".
        XCTAssertEqual(LidSoundLibrary.pick(from: [a, b], mode: .random, lastPickID: a.id, nextIndex: 0, random: { _ in 0 })?.item, b)
        // In order carries on and wraps, whatever was removed since.
        XCTAssertEqual(LidSoundLibrary.pick(from: [a, b, c], mode: .inOrder, lastPickID: nil, nextIndex: 0).map { ($0.item.id, $0.nextIndex) }.map { "\($0 == a.id) \($1)" }, "true 1")
        XCTAssertEqual(LidSoundLibrary.pick(from: [a, b, c], mode: .inOrder, lastPickID: nil, nextIndex: 2)?.nextIndex, 0, "wraps")
        XCTAssertEqual(LidSoundLibrary.pick(from: [a, b], mode: .inOrder, lastPickID: nil, nextIndex: 5)?.item, b, "an index past the list still lands")
    }

    @MainActor
    func testSettingsSeedTheStartersOnceAndKeepTheList() {
        let suite = UserDefaults(suiteName: "LidSound-\(UUID().uuidString)")!
        let settings = LidSoundSettings(defaults: suite, manifest: LidSoundLibrary.fallbackPacks)
        XCTAssertEqual(settings.items.map(\.displayName), ["Click", "Breath", "Hum"])
        XCTAssertTrue(settings.items.allSatisfy { $0.isStarter && !$0.enabled }, "a new list: everything in its pack, nothing on the lid")
        XCTAssertTrue(settings.playsToEnd, "the whole sound by default: the Mac waits for it")
        for item in settings.items { var on = item; on.enabled = true; settings.update(on) }
        XCTAssertFalse(settings.isOn, "off until turned on")
        XCTAssertEqual(settings.volume, 0.7)
        XCTAssertEqual(settings.whenMuted, .stayQuiet)
        XCTAssertEqual(settings.volumeMode, .ownLevel)
        var hum = settings.items[2]; hum.enabled = false
        settings.update(hum)
        settings.onOpenPick = .item(settings.items[0].id)
        let again = LidSoundSettings(defaults: suite, manifest: LidSoundLibrary.fallbackPacks)
        XCTAssertEqual(again.onTheLid.map(\.displayName), ["Click", "Breath"], "a sound taken off the lid stays off")
        XCTAssertEqual(again.onOpenPick, .item(settings.items[0].id))
        XCTAssertEqual(again.items.count, 3, "and is still on its shelf")

        // A release with new packs and sounds: what the list has not got is added to its
        // shelf, off the lid; one the user already cut themselves, by that name and part, is
        // not doubled.
        var own = LidSoundItem(id: UUID(), fileName: "Mine.mp3", displayName: "اذكر الله", enabled: true, isStarter: false, duration: 14)
        own.clipStart = 2.7; own.clipEnd = 4.7; own.isCut = true
        again.items.append(own)
        let release = LidSoundLibrary.fallbackPacks + [
            LidSoundLibrary.ManifestPack(id: "adhkar", name: "Adhkar", credit: "Recorded by the author.", sounds: [
                LidSoundLibrary.Starter(name: "اذكر الله", file: "Adhkar.mp3", from: 2.7, to: 4.7),
                LidSoundLibrary.Starter(name: "توكل على الله", file: "Adhkar.mp3", from: 11.2, to: 13.1)])]
        again.adoptNewPacks(release)
        XCTAssertEqual(again.items.map(\.displayName), ["Click", "Breath", "Hum", "اذكر الله", "توكل على الله"])
        XCTAssertEqual(again.packs.map(\.id), [LidSoundPack.mineID, "generated", "adhkar"], "Mine first, then the bundled packs")
        XCTAssertEqual(again.items.last?.packID, "adhkar")
        XCTAssertEqual(again.items.last?.enabled, false, "a release puts nothing on the lid")
        XCTAssertEqual(again.items[3].packID, "adhkar", "the user's own cut of a manifest sound is claimed by its pack, out of Mine")
        XCTAssertEqual(again.items[3].id, own.id, "the same row, not a copy")
        XCTAssertTrue(again.items[3].enabled, "and stays on the lid, where the user had it")
        XCTAssertFalse(again.items[2].enabled, "Hum stays off")
        again.adoptNewPacks(release)
        XCTAssertEqual(again.items.count, 5, "adopting twice adds nothing")
        XCTAssertEqual(again.shelf("adhkar").map(\.displayName), ["اذكر الله", "توكل على الله"])
        XCTAssertEqual(again.onTheLid.map(\.displayName), ["Click", "Breath", "اذكر الله"])
        let library = LidSoundLibrary(directory: folder, bundle: AppAssets.resourceBundle(), packs: release)
        XCTAssertEqual(library.candidates(again.items).map(\.displayName), ["Click", "Breath"], "on the lid and on disk; the user's file is not on disk")

        // A new user: every pack in place, nothing on the lid.
        let fresh = UserDefaults(suiteName: "LidSound-\(UUID().uuidString)")!
        let offer = [LidSoundLibrary.ManifestPack(id: "adhkar", name: "Adhkar", sounds: release[1].sounds)] + LidSoundLibrary.fallbackPacks
        let newUser = LidSoundSettings(defaults: fresh, manifest: offer)
        XCTAssertTrue(newUser.onTheLid.isEmpty, "nothing imposed")
        XCTAssertEqual(newUser.shelf("adhkar").count, 2)
        XCTAssertEqual(newUser.shelf("generated").count, 3)
        XCTAssertEqual(newUser.packs.map(\.id), [LidSoundPack.mineID, "adhkar", "generated"])

        // The claim takes the author's cuts only: a whole file of the user's that shares a
        // name stays theirs in Mine and the manifest sound is added; a user's pack keeps its place.
        let named = UserDefaults(suiteName: "LidSound-\(UUID().uuidString)")!
        let shared = LidSoundSettings(defaults: named, manifest: LidSoundLibrary.fallbackPacks)
        shared.items.append(LidSoundItem(id: UUID(), fileName: "abc.mp3", displayName: "Rain", enabled: true, isStarter: false))
        shared.packs.insert(LidSoundPack(id: "user-work", name: "Work", bundled: false), at: 1)
        let nature = LidSoundLibrary.fallbackPacks + [LidSoundLibrary.ManifestPack(id: "nature", name: "Nature", sounds: [
            LidSoundLibrary.Starter(name: "Rain", file: "Rain.wav"), LidSoundLibrary.Starter(name: "Thunder", file: "Thunder.wav", from: 1, to: 3)])]
        shared.adoptNewPacks(nature)
        XCTAssertEqual(shared.items.first { $0.fileName == "abc.mp3" }?.packID, LidSoundPack.mineID, "a whole file of the user's is not claimed")
        XCTAssertEqual(shared.items.filter { $0.packID == "nature" }.map(\.displayName), ["Rain", "Thunder"], "the manifest sounds are added")
        XCTAssertEqual(shared.packs.map(\.id), [LidSoundPack.mineID, "user-work", "generated", "nature"])
        XCTAssertEqual(LidSoundSettings(defaults: named, manifest: nature).packs.map(\.id), [LidSoundPack.mineID, "user-work", "generated", "nature"], "the user's pack is kept")

        // An older list's manifest sounds find their pack at launch.
        let older = UserDefaults(suiteName: "LidSound-\(UUID().uuidString)")!
        var oldItems = offer.flatMap(\.starters).map { $0.item() }
        oldItems = oldItems.map { var i = $0; i.packID = LidSoundPack.startersID; return i }
        older.set(try? JSONEncoder().encode(oldItems), forKey: "lidSound.items")
        let migrated = LidSoundSettings(defaults: older, manifest: offer)
        XCTAssertEqual(Set(migrated.items.map(\.packID)), ["adhkar", "generated"], "settled against the manifest")
        XCTAssertEqual(migrated.onTheLid.count, 5, "they were on the lid before: they stay on it; only a new list starts empty")
    }

    /// 0.4.0 had three ways for a sound to be out of the pick besides its switch: kept for
    /// later, a starter hidden, a pack put away. Each is now off the lid, on its shelf, and
    /// nothing that was silent starts playing.
    @MainActor
    func testAnOlderListComesToTheStageAndTheShelves() throws {
        let suite = UserDefaults(suiteName: "LidSound-\(UUID().uuidString)")!
        let adhkar = LidSoundLibrary.ManifestPack(id: "adhkar", name: "Adhkar", sounds: [
            LidSoundLibrary.Starter(name: "اذكر الله", file: "Adhkar.mp3", from: 2.7, to: 4.7)])
        let manifest = LidSoundLibrary.fallbackPacks + [adhkar]
        let click = LidSoundLibrary.fallbackPacks[0].starters[0].item()
        var breath = LidSoundLibrary.fallbackPacks[0].starters[1].item(); breath.kept = true
        var hum = LidSoundLibrary.fallbackPacks[0].starters[2].item(); hum.hidden = true
        let verse = adhkar.starters[0].item()   // switched on, in a pack the user had put away
        let rain = LidSoundItem(id: UUID(), fileName: "Rain.wav", displayName: "Rain", enabled: false, isStarter: false)
        suite.set(try JSONEncoder().encode([click, breath, hum, verse, rain]), forKey: "lidSound.items")
        suite.set(["adhkar"], forKey: "lidSound.hiddenPacks")
        suite.set("adhkar", forKey: "lidSound.playsFrom")
        let settings = LidSoundSettings(defaults: suite, manifest: manifest)
        XCTAssertEqual(settings.onTheLid.map(\.displayName), ["Click"], "kept, hidden, put away, or off: all off the lid")
        XCTAssertEqual(settings.items.count, 5, "nothing lost")
        XCTAssertTrue(settings.items.allSatisfy { !$0.kept && !$0.hidden })
        XCTAssertEqual(settings.shelf("adhkar").count, 1)
        XCTAssertNil(suite.object(forKey: "lidSound.hiddenPacks"))
        XCTAssertNil(suite.object(forKey: "lidSound.playsFrom"))
        XCTAssertEqual(LidSoundSettings(defaults: suite, manifest: manifest).onTheLid.map(\.displayName), ["Click"], "and it stays so")
    }
}
