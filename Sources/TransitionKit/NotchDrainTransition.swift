import Foundation
import simd
import Tuner

/// Every knob for Notch Drain, with the PRD 4.5 defaults. The Tuner schema at the
/// bottom is the single source of truth for ranges and grouping.
public struct NotchDrainParams: TunableParameters {
    // Motion
    public var progressCurve: TunerBezier = .easeIn
    public var falloff: Double = 0.5          // how much near-notch content leads
    public var twist: Double = 0.3            // turns at full progress (whole-screen swirl)
    public var vortex: Double = 1.0           // arc-shaped streaking near the sink, like water at a drain
    public var stretch: Double = 0.6          // funnel: horizontal squeeze toward the notch
    public var pull: Double = 0.7             // contraction exponent (γ): lower = more gradual collapse
    public var commitThreshold: Double = 1.0  // 1.0 = follow the lid all the way

    // Look
    public var blurSamples: Int = 8
    public var blurStrength: Double = 0.5
    public var darken: Double = 0.6
    public var aberration: Double = 2         // px
    public var glow: Double = 0.35
    public var glowColor: TunerColor = .white
    public var edgeSoftness: Double = 90      // pt; how softly content fades where it leaves the screen

    // Sink
    public var autoDetectNotch: Bool = true
    public var offsetX: Double = 0            // pt
    public var offsetY: Double = 0            // pt
    public var sinkRadius: Double = 16        // pt

    // Pour-out
    public var pourOutResponse: Double = 0.55
    public var pourOutDamping: Double = 0.72
    public var overshoot: Double = 0.06
    public var pourOutDelayMs: Double = 0

    public init() {}

    public static let tunerID = "notchDrain"
    public static let tunerDisplayName = "Notch Drain"
    public static let defaults = NotchDrainParams()
    public static let schema = TunerSchema<NotchDrainParams>([
        TunerFolder("Motion", [
            .bezier(\.progressCurve, "Progress curve"),
            .slider(\.falloff, "Falloff", 0...3),
            .slider(\.twist, "Twist", -2...2, unit: "turns"),
            .slider(\.vortex, "Vortex", 0...2),
            .slider(\.stretch, "Funnel stretch", 0...2),
            .slider(\.pull, "Pull", 0.5...3),
            .slider(\.commitThreshold, "Commit threshold", 0...1, step: 0.01, unit: "×", decimals: 2),
        ]),
        TunerFolder("Look", [
            .slider(\.blurSamples, "Motion blur samples", 0...16),
            .slider(\.blurStrength, "Motion blur strength", 0...1),
            .slider(\.darken, "Darken toward sink", 0...1),
            .slider(\.aberration, "Chromatic aberration", 0...10, unit: "px", decimals: 1),
            .slider(\.glow, "Rim glow", 0...1),
            .color(\.glowColor, "Glow color"),
            .slider(\.edgeSoftness, "Edge softness", 0...300, step: 5, unit: "pt", decimals: 0),
        ]),
        TunerFolder("Sink", [
            .toggle(\.autoDetectNotch, "Auto-detect notch"),
            .slider(\.offsetX, "Offset X", -200...200, step: 1, unit: "pt", decimals: 0),
            .slider(\.offsetY, "Offset Y", -200...200, step: 1, unit: "pt", decimals: 0),
            .slider(\.sinkRadius, "Sink radius", 0...60, unit: "pt", decimals: 0),
        ]),
        TunerFolder("Pour-out", [
            .spring(response: \.pourOutResponse, damping: \.pourOutDamping, "Spring"),
            .slider(\.overshoot, "Overshoot", 0...0.15, decimals: 3),
            .slider(\.pourOutDelayMs, "Delay after unlock", 0...500, step: 10, unit: "ms", decimals: 0),
        ]),
    ])
}

/// The headline transition: the desktop spirals into the notch. All the visual
/// work is in Shaders/NotchDrain.metal; this just packs the uniforms.
public final class NotchDrainTransition: Transition {
    public static let id = "notchDrain"
    public static let displayName = "Notch Drain"
    public static let fragmentFunctionName = "notchDrainFragment"

    public var params = NotchDrainParams()

    public init() {}

    public func uniforms(progress: Double, context: RenderContext) -> TransitionUniforms {
        var u = TransitionUniforms()
        let p = params
        let scale = context.scale

        // Sink placement: hardware notch (or the virtual pill) plus the user's offset.
        // With auto-detect off we ignore the hardware notch and draw the pill at the
        // top centre, which is handy for judging the pill on a Mac that has a notch.
        let usesVirtual = context.usesVirtualNotch || !p.autoDetectNotch
        var sink = context.sinkPoint
        var notch = context.notchSize
        if !p.autoDetectNotch {
            notch = SIMD2(Float(NotchDetector.virtualNotchSize.width) * scale,
                          Float(NotchDetector.virtualNotchSize.height) * scale)
            sink = SIMD2(context.snapshotSize.x / 2, notch.y)
        }
        sink += SIMD2(Float(p.offsetX), Float(p.offsetY)) * scale
        u.sink = sink
        u.notchSize = notch
        u.virtualNotch = usesVirtual ? 1 : 0

        // D: distance from the sink to the farthest corner, so d ∈ 0...1 everywhere.
        let corners: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(context.snapshotSize.x, 0),
            SIMD2(0, context.snapshotSize.y), context.snapshotSize,
        ]
        u.maxDistance = corners.map { simd_length($0 - sink) }.max() ?? 1

        u.progress = Float(progress)
        u.falloff = Float(p.falloff)
        u.twist = Float(p.twist)
        u.vortex = Float(p.vortex)
        u.stretch = Float(p.stretch)
        u.edgeSoftness = Float(p.edgeSoftness) * scale
        u.pull = Float(p.pull)
        u.overshoot = Float(p.overshoot)
        u.blurSamples = Int32(context.reduceTransparency ? 0 : p.blurSamples)
        u.blurStrength = Float(p.blurStrength)
        u.darken = Float(p.darken)
        u.aberration = Float(p.aberration) * scale
        u.glow = Float(p.glow)
        u.glowColor = SIMD4(Float(p.glowColor.red), Float(p.glowColor.green), Float(p.glowColor.blue), Float(p.glowColor.alpha))
        u.sinkRadius = Float(p.sinkRadius) * scale
        return u
    }
}
