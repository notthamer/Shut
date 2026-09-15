import XCTest
@testable import Tuner

@MainActor
final class TunerStoreTests: XCTestCase {
    var tempDir: URL!
    var defaults: UserDefaults!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TunerTests-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: "TunerTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makeStore() -> TunerStore<DemoParams> {
        TunerStore(presets: PresetStore(rootURL: tempDir), builtIns: [("Wild", { var p = DemoParams(); p.twist = 2; return p }())], defaults: defaults)
    }

    func testPersistsAcrossInstances() {
        let a = makeStore()
        a.values.twist = 1.25
        let b = makeStore()
        XCTAssertEqual(b.values.twist, 1.25)
    }

    func testResetFolderAndAll() {
        let s = makeStore()
        s.values.twist = 2
        s.values.color = .black
        s.reset(folder: 0)
        XCTAssertEqual(s.values.twist, DemoParams.defaults.twist)
        XCTAssertEqual(s.values.color, .black)
        s.resetAll()
        XCTAssertEqual(s.values, DemoParams.defaults)
    }

    func testPresetSaveListApplyDelete() throws {
        let s = makeStore()
        s.values.twist = -1
        let saved = try XCTUnwrap(s.savePreset(named: "Lefty"))
        XCTAssertEqual(s.activePresetName, "Lefty")
        XCTAssertEqual(s.allPresets.map(\.name), ["Wild", "Lefty"])

        s.values.twist = 0.1
        XCTAssertNil(s.activePresetName, "editing clears the active preset")

        XCTAssertTrue(s.apply(preset: saved))
        XCTAssertEqual(s.values.twist, -1)

        s.deletePreset(saved)
        XCTAssertEqual(s.allPresets.map(\.name), ["Wild"])
        XCTAssertTrue(s.apply(preset: s.allPresets[0]))
        XCTAssertEqual(s.values.twist, 2)
    }

    func testPresetFileFormatIsReadable() throws {
        let s = makeStore()
        let preset = try XCTUnwrap(s.savePreset(named: "Readable"))
        let text = preset.fileText
        XCTAssertTrue(text.contains("\"transition\" : \"demo\""))
        XCTAssertTrue(text.contains("\"twist\""))
        let reparsed = try JSONDecoder().decode(Preset.self, from: Data(text.utf8))
        XCTAssertEqual(reparsed.decode(DemoParams.self), s.values)
    }

    func testApplyJSONAcceptsBareValuesAndPresetFiles() {
        let s = makeStore()
        XCTAssertTrue(s.apply(json: "{\"twist\": 1.5, \"samples\": 4, \"enabled\": false, \"color\": {\"red\":1,\"green\":1,\"blue\":1,\"alpha\":1}, \"response\": 0.5, \"damping\": 0.7, \"curve\": {\"x1\":0,\"y1\":0,\"x2\":1,\"y2\":1}, \"mode\": \"b\"}"))
        XCTAssertEqual(s.values.samples, 4)
        XCTAssertFalse(s.apply(json: "not json"))
        let file = Preset(name: "F", tunerID: "demo", values: DemoParams.defaults, builtIn: false)!.fileText
        XCTAssertTrue(s.apply(json: file))
        XCTAssertEqual(s.values, DemoParams.defaults)
    }
}
