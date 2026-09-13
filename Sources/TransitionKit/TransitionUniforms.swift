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

    // Sinkhole
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
    public var pull: Float = 1.0        // Sinkhole contraction exponent (γ in the PRD)
    public var vortex: Float = 0        // Sinkhole whirlpool strength near the sink
    public var edgeSoftness: Float = 0  // px over which out-of-snapshot samples fade to black
    public var holeGrowth: Float = 0    // how much the notch hole widens by full progress (× sinkRadius)
    public var pad2: Float = 0          // offset 140; the block below starts at 144

    // MARK: Panel family (Fold, Crease, Recede, Slide, Fade, Shutter)
    // Appended after the original 144 bytes so the offsets above never move. Two
    // float2 first (8-aligned at 144/152), then scalars. Mirrors Bendable's Uniforms.
    public var meshScale: SIMD2<Float> = .one        // 144  NDC scale about the centre (Recede)
    public var meshTranslate: SIMD2<Float> = .zero   // 152  NDC translation (Slide)
    public var foldAngle: Float = 0                  // 160  radians; the panel above the crease turns away
    public var foldPosition: Float = 0.5             // 164  crease height from the bottom, 0...1
    public var perspective: Float = 0                // 168  0 = orthographic, 1 = full keystone
    public var curvature: Float = 0                  // 172  bow just past the crease
    public var creaseHighlight: Float = 0            // 176
    public var aspect: Float = 1                     // 180  output width / height (set by renderer)
    public var blur: Float = 0                       // 184  0...1 -> mip LOD via maxLOD
    public var blurGradient: Float = 0               // 188  1 = far edge blurs first
    public var wash: Float = 0                       // 192  colour drain toward grey
    public var cornerRadius: Float = 0               // 196  in half-heights
    public var brightness: Float = 1                 // 200
    public var opacity: Float = 1                    // 204  overlay alpha
    public var vignette: Float = 0                   // 208
    public var edgeOcclusion: Float = 0              // 212
    public var maskOpenness: Float = 1               // 216
    public var maskKind: UInt32 = 0                  // 220  0 none, 1 aperture, 2 shutter, 3 blinds
    public var blades: UInt32 = 0                    // 224  iris blades or slat count
    public var useTexture: UInt32 = 1                // 228  0 = paint flat black at `opacity`
    public var maxLOD: Float = 0                     // 232  mipLevels - 1 - 3, set by renderer
    public var pad3: Float = 0                       // 236  stride 240

    public init() {}
}
