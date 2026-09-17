import XCTest
import Tuner
import simd
import Metal
@testable import TransitionKit

final class TransitionKitTests: XCTestCase {
    /// GitHub-hosted macOS runners have no GPU. Skip, do not fail.
    override func setUpWithError() throws { try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "No Metal device on this machine") }
    /// Compiles every shader from source. Catches Metal syntax errors and struct
    /// layout mismatches before anyone closes a lid.
    func testRendererCompilesShaders() throws {
        let renderer = try TransitionRenderer()
        XCTAssertNotNil(renderer.device)
    }

    func testGridCoversUnitSquare() {
        let grid = TransitionRenderer.makeGrid(resolution: 4)
        XCTAssertEqual(grid.count, 4 * 4 * 6)
        XCTAssertEqual(grid.map(\.x).min(), 0); XCTAssertEqual(grid.map(\.x).max(), 1)
        XCTAssertEqual(grid.map(\.y).min(), 0); XCTAssertEqual(grid.map(\.y).max(), 1)
    }

    func testUniformsLayoutMatchesMetalExpectations() {
        // Original block: float4 (16) + 4×float2 (32) + 24 scalars (96) = 144.
        // Panel block: 2×float2 (16) + 20 scalars (80) = 96. Total 240, a multiple of 16.
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.stride, 240)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.snapshotSize), 16)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.progress), 48)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.pad2), 140)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.meshScale), 144)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.meshTranslate), 152)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.foldAngle), 160)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.aspect), 180)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.maskOpenness), 216)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.maskKind), 220)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.useTexture), 228)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.maxLOD), 232)
        XCTAssertEqual(MemoryLayout<TransitionUniforms>.offset(of: \.pad3), 236)
    }

    /// Runs the probe kernel so the GPU itself confirms it reads every field where
    /// Swift wrote it. MemoryLayout arithmetic cannot catch a Metal-side mismatch.
    func testUniformsLayoutOnGPU() throws {
        let renderer = try TransitionRenderer()
        var u = TransitionUniforms()
        u.glowColor.w = 0.25; u.notchSize.y = 64; u.progress = 0.5; u.blurSamples = 7; u.pad2 = 9
        u.meshScale.y = 0.7; u.meshTranslate.x = -0.3; u.foldAngle = 1.25; u.aspect = 1.54
        u.maskOpenness = 0.33; u.maskKind = 3; u.blades = 6; u.useTexture = 0; u.maxLOD = 4; u.pad3 = 11
        let expected: [Float] = [0.25, 64, 0.5, 7, 9, 0.7, -0.3, 1.25, 1.54, 0.33, 3, 6, 0, 4, 11]

        let device = renderer.device
        let function = try XCTUnwrap(renderer.library.makeFunction(name: "uniformsLayoutProbe"))
        let pipeline = try device.makeComputePipelineState(function: function)
        let input = try XCTUnwrap(device.makeBuffer(bytes: &u, length: MemoryLayout<TransitionUniforms>.stride, options: .storageModeShared))
        let output = try XCTUnwrap(device.makeBuffer(length: 16 * MemoryLayout<Float>.stride, options: .storageModeShared))
        let commandBuffer = try XCTUnwrap(renderer.commandQueue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setBuffer(output, offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let got = Array(UnsafeBufferPointer(start: output.contents().assumingMemoryBound(to: Float.self), count: 15))
        for (i, (g, e)) in zip(got, expected).enumerated() {
            XCTAssertEqual(g, e, accuracy: 1e-5, "field \(i) read back wrong on the GPU")
        }
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

    func testNotchGeometryOnCurrentScreen() throws {
        try XCTSkipUnless(BuiltInDisplay.screen != nil, "No built-in display on this machine")
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

final class PanelTests: XCTestCase {
    func testPanelFrameToUniformsClamps() {
        var frame = PanelFrame()
        frame.opacity = 1.5
        frame.mask = .aperture(blades: 2, openness: 2)
        var u = frame.uniforms(progress: 0.5)
        XCTAssertEqual(u.opacity, 1); XCTAssertEqual(u.maskKind, 1); XCTAssertEqual(u.blades, 3); XCTAssertEqual(u.maskOpenness, 1)
        frame.mask = .blinds(slats: 40, openness: 0.5)
        u = frame.uniforms(progress: 0.5)
        XCTAssertEqual(u.maskKind, 3); XCTAssertEqual(u.blades, 24)
        frame.usesSnapshot = false
        XCTAssertEqual(frame.uniforms(progress: 0).useTexture, 0)
    }

    func testFoldIsDegreeForDegree() {
        let fold = FoldTransition()
        let still = RenderContext(snapshotSize: SIMD2(100, 100), sinkPoint: .zero, notchSize: .zero,
                                  usesVirtualNotch: false, velocity: 0, hingeTravelDegrees: 80)
        XCTAssertEqual(fold.frame(progress: 0.5, context: still).foldAngle, 40 * .pi / 180, accuracy: 1e-6)
        XCTAssertEqual(fold.frame(progress: 0, context: still).foldAngle, 0)
        let moving = RenderContext(snapshotSize: SIMD2(100, 100), sinkPoint: .zero, notchSize: .zero,
                                   usesVirtualNotch: false, velocity: 1, hingeTravelDegrees: 80)
        XCTAssertGreaterThan(fold.frame(progress: 0.5, context: moving).foldAngle,
                             fold.frame(progress: 0.5, context: still).foldAngle, "a fast close leads a little")
    }

    func testEveryStyleDeclaresConsistentFlags() {
        for t in [AnyTransition(FoldTransition()), AnyTransition(ShutterTransition()), AnyTransition(FadeTransition()),
                  AnyTransition(SinkholeTransition()), AnyTransition(FrostTransition())] {
            if t.isTransparent { XCTAssertFalse(t.needsSnapshot, "\(t.id): transparent styles don't need a snapshot") }
            XCTAssertFalse(t.summary.isEmpty, "\(t.id) needs a summary for the gallery")
        }
    }
}

final class FoldParamsCompatibilityTests: XCTestCase {
    /// A preset saved before "Blur onset" existed still loads, with the new dial
    /// at its default rather than the whole preset failing to decode.
    func testPresetWithoutBlurOnsetStillDecodes() throws {
        let json = #"{"blur":0.5,"intensity":0.6,"washout":0.5}"#.data(using: .utf8)!
        let params = try JSONDecoder().decode(FoldParams.self, from: json)
        XCTAssertEqual(params.blur, 0.5)
        XCTAssertEqual(params.intensity, 0.6)
        XCTAssertEqual(params.blurOnset, FoldParams.defaults.blurOnset)
        XCTAssertEqual(params.tilt, FoldParams.defaults.tilt)
    }
}
