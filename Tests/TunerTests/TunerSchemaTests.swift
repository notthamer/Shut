import XCTest
@testable import Tuner

struct DemoParams: TunableParameters {
    enum Mode: String, CaseIterable, Codable { case a, b }
    var twist = 0.6
    var samples = 8
    var enabled = true
    var color = TunerColor.white
    var response = 0.55
    var damping = 0.72
    var curve = TunerBezier.easeIn
    var mode = Mode.a

    static let tunerID = "demo"
    static let tunerDisplayName = "Demo"
    static let defaults = DemoParams()
    static let schema = TunerSchema<DemoParams>([
        TunerFolder("Motion", [
            .slider(\.twist, "Twist", -2...2),
            .slider(\.samples, "Samples", 0...16),
            .toggle(\.enabled, "Enabled"),
        ]),
        TunerFolder("Look", [
            .color(\.color, "Color"),
            .spring(response: \.response, damping: \.damping, "Spring"),
            .bezier(\.curve, "Curve"),
            .segmented(\.mode, "Mode"),
        ]),
    ])
}

final class TunerSchemaTests: XCTestCase {
    func testBezierEndpointsAndLinear() {
        XCTAssertEqual(TunerBezier.linear.value(at: 0.3), 0.3, accuracy: 1e-4)
        XCTAssertEqual(TunerBezier.easeIn.value(at: 0), 0)
        XCTAssertEqual(TunerBezier.easeIn.value(at: 1), 1)
        XCTAssertLessThan(TunerBezier.easeIn.value(at: 0.5), 0.5, "ease-in lags below the diagonal")
        XCTAssertGreaterThan(TunerBezier.easeOut.value(at: 0.5), 0.5)
    }

    func testControlsReadAndWriteThroughKeyPaths() {
        var p = DemoParams()
        guard case .slider(let twist) = DemoParams.schema.folders[0].controls[0] else { return XCTFail() }
        twist.set(&p, 1.5)
        XCTAssertEqual(p.twist, 1.5)
        XCTAssertEqual(twist.get(p), 1.5)

        guard case .slider(let samples) = DemoParams.schema.folders[0].controls[1] else { return XCTFail() }
        samples.set(&p, 3.7)
        XCTAssertEqual(p.samples, 4, "int sliders round")

        guard case .segmented(let mode) = DemoParams.schema.folders[1].controls[3] else { return XCTFail() }
        mode.setIndex(&p, 1)
        XCTAssertEqual(p.mode, .b)
        XCTAssertEqual(mode.options, ["A", "B"])
    }

    func testResetGroupOnlyTouchesThatFolder() {
        var p = DemoParams()
        p.twist = 2
        p.color = .black
        for control in DemoParams.schema.folders[0].controls {
            control.copyValue(from: DemoParams.defaults, into: &p)
        }
        XCTAssertEqual(p.twist, DemoParams.defaults.twist)
        XCTAssertEqual(p.color, .black, "other folder untouched")
    }

    func testJSONRoundTrip() throws {
        var p = DemoParams()
        p.curve = TunerBezier(0.1, 0.2, 0.3, 0.4)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(DemoParams.self, from: data)
        XCTAssertEqual(back, p)
    }
}
