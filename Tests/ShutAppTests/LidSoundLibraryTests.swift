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

    func testUniqueNames() {
        XCTAssertEqual(LidSoundLibrary.uniqueName("Rain", among: []), "Rain")
        XCTAssertEqual(LidSoundLibrary.uniqueName("rain", among: ["Rain"]), "rain 2", "case does not make a new name")
        XCTAssertEqual(LidSoundLibrary.uniqueName("Rain", among: ["Rain", "Rain 2"]), "Rain 3")
        XCTAssertEqual(LidSoundLibrary.uniqueName("  ", among: []), "Sound")
    }

    func testStartersComeFromTheBundleAndAStarterIsNeverDeleted() throws {
        let bundled = LidSoundLibrary(directory: folder, bundle: AppAssets.resourceBundle())
        XCTAssertEqual(bundled.starterURLs().count, 3, "Click, Breath and Hum ship with the app")
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
        let settings = LidSoundSettings(defaults: suite)
        XCTAssertEqual(settings.items.map(\.displayName), ["Click", "Breath", "Hum"])
        XCTAssertTrue(settings.items.allSatisfy { $0.isStarter && $0.enabled })
        XCTAssertFalse(settings.isOn, "off until turned on")
        XCTAssertEqual(settings.volume, 0.7)
        XCTAssertEqual(settings.whenMuted, .stayQuiet)
        var hum = settings.items[2]; hum.hidden = true
        settings.update(hum)
        settings.onOpenPick = .item(settings.items[0].id)
        let again = LidSoundSettings(defaults: suite)
        XCTAssertEqual(again.shown.map(\.displayName), ["Click", "Breath"], "a removed starter stays hidden")
        XCTAssertEqual(again.onOpenPick, .item(settings.items[0].id))
        XCTAssertEqual(again.items.count, 3, "and is still there to restore")
    }
}
