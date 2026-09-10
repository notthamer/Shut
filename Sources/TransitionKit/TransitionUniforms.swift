import simd

/// Mirror of `TransitionUniforms` in Shaders/Common.metal. One struct serves every
/// transition; unused fields are simply zero. Keeping a single layout means the
/// renderer never has to know which transition is active.
///
/// Field order matters: Metal aligns `float4` to 16 bytes and `float2` to 8, and
/// Swift's SIMD types use the same rules, so listing the wide fields first keeps
/// both sides byte-identical without manual padding.
public struct TransitionUniforms {
    // 16-byte aligned
    public var glowColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    // 8-byte aligned
    public var snapshotSize: SIMD2<Float> = .zero
    public var outputSize: SIMD2<Float> = .zero
    public var sink: SIMD2<Float> = .zero
    public var notchSize: SIMD2<Float> = .zero

    // 4-byte
    public var progress: Float = 0
    public var time: Float = 0
    public var maxDistance: Float = 1   // D in the PRD: sink to farthest corner

    // Notch Drain
    public var falloff: Float = 0
    public var twist: Float = 0
    public var stretch: Float = 0
    public var overshoot: Float = 0
    public var blurSamples: Int32 = 0
    public var blurStrength: Float = 0
    public var darken: Float = 0
    public var aberration: Float = 0
    public var glow: Float = 0
    public var sinkRadius: Float = 0
    public var virtualNotch: Float = 0  // 0 = hardware notch, 1 = draw the pill

    // Frost
    public var maxBlur: Float = 0
    public var frostSpread: Float = 0
    public var darknessStart: Float = 0
    public var mipLevels: Float = 1

    // Shared
    public var reduceTransparency: Float = 0
    public var pad0: Float = 0
    public var pad1: Float = 0

    public init() {}
}
