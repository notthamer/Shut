import XCTest
import Tuner
import simd
import Metal
@testable import TransitionKit

final class TransitionKitTests: XCTestCase {
    /// Compiles every shader from source. Catches Metal syntax errors and struct
    /// layout mismatches before anyone closes a lid.
    func testRendererCompilesShaders() throws {
        let renderer = try TransitionRenderer()
        XCTAssertNotNil(renderer.device)
    }

    func testUniformsLayoutMatchesMetalExpectations() {
        // float4 (16) + 4×float2 (32) + 24 scalars (96) = 144, a multiple of 16.
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.stride, 144)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.snapshotSize), 16)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.progress), 48)
    }

    func testSpringSettlesAtTarget() {
        var spring = Spring(response: 0.3, dampingFraction: 1.0, from: 1, to: 0)
        for _ in 0..<240 { spring.step(dt: 1.0 / 120) }
        XCTAssertTrue(spring.isSettled)
        XCTAssertEqual(spring.position, 0, accuracy: 0.001)
    }

    func testUnderdampedSpringOvershoots() {
        var spring = Spring(response: 0.55, dampingFraction: 0.5, from: 1, to: 0)
        var minimum = 1.0
        for _ in 0..<240 {
            minimum = min(minimum, spring.step(dt: 1.0 / 120))
        }
        XCTAssertLessThan(minimum, -0.02, "damping below 1 must overshoot past the target")
    }

    func testNotchGeometryOnCurrentScreen() {
        let geometry = NotchDetector.geometry(for: BuiltInDisplay.screen)
        XCTAssertGreaterThan(geometry.sinkPoint.x, 0)
        XCTAssertGreaterThan(geometry.sinkPoint.y, 0)
        XCTAssertGreaterThan(geometry.notchSize.x, 0)
    }

    func testFadeUniforms() {
        let fade = FadeTransition()
        let context = RenderContext(snapshotSize: SIMD2(100, 100), sinkPoint: .zero, notchSize: .zero, usesVirtualNotch: false)
        XCTAssertEqual(fade.uniforms(progress: 0.5, context: context).progress, 0.5, accuracy: 0.001)
    }

    func testAnyTransitionRoundTripsParams() throws {
        let fade = AnyTransition(FadeTransition())
        let json = try XCTUnwrap(fade.paramsJSON)
        XCTAssertTrue(fade.setParams(json: json))
        XCTAssertFalse(fade.setParams(json: Data("nonsense".utf8)))
    }
}

final class SinkholeTests: XCTestCase {
    func testSinkGeometryAndMaxDistance() {
        let t = SinkholeTransition()
        let context = RenderContext(snapshotSize: SIMD2(3024, 1964), sinkPoint: SIMD2(1512, 64),
                                    notchSize: SIMD2(360, 64), usesVirtualNotch: false, scale: 2)
        let u = t.uniforms(progress: 0.3, context: context)
        XCTAssertEqual(u.sink, SIMD2(1512, 64))
        XCTAssertEqual(u.maxDistance, simd_length(SIMD2<Float>(1512, 1900)), accuracy: 0.5)
        XCTAssertEqual(u.sinkRadius, 80, "40 pt × scale 2")
        XCTAssertEqual(u.virtualNotch, 0)
    }

    func testOffsetsAndAutoDetectOff() {
        let t = SinkholeTransition()
        t.params.autoDetectNotch = false
        t.params.offsetX = 10
        let context = RenderContext(snapshotSize: SIMD2(3024, 1964), sinkPoint: SIMD2(1512, 64),
                                    notchSize: SIMD2(360, 64), usesVirtualNotch: false, scale: 2)
        let u = t.uniforms(progress: 0, context: context)
        XCTAssertEqual(u.virtualNotch, 1)
        XCTAssertEqual(u.sink.x, 1512 + 20)
    }

    /// Defaults follow PRD 4.5 except where visual tuning moved them (falloff,
    /// twist, stretch were softened after judging rendered frames).
    func testDefaultsMatchTunedValues() {
        let p = SinkholeParams.defaults
        XCTAssertEqual(p.falloff, 0.5); XCTAssertEqual(p.twist, 0.3); XCTAssertEqual(p.stretch, 0.6)
        XCTAssertEqual(p.blurSamples, 8); XCTAssertEqual(p.darken, 0.6); XCTAssertEqual(p.sinkRadius, 40)
        XCTAssertEqual(p.pourOutResponse, 0.55); XCTAssertEqual(p.pourOutDamping, 0.72)
        XCTAssertEqual(p.progressCurve, TunerBezier(0.45, 0, 0.85, 0.55))
    }
}
