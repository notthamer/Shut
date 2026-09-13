import Foundation
import Metal
import Tuner

/// The classic iPhone Duo-style frost. Image locked in space, blur front moves
/// from the top edge toward the hinge, then fades to black. PRD 4.3 / 4.5.
public struct FrostParams: TunableParameters {
    public var maxBlur: Double = 64          // radius in px at the frostiest
    public var frostSpread: Double = 0.6     // softness of the frost front (fraction of height)
    public var darknessStart: Double = 0.30  // progress at which darkening begins
    public var progressCurve: TunerBezier = .linear

    public init() {}

    public static let tunerID = "frost"
    public static let tunerDisplayName = "Frost"
    public static let defaults = FrostParams()
    public static let schema = TunerSchema<FrostParams>([
        TunerFolder("Frost", [
            .slider(\.maxBlur, "Max blur radius", 0...120, unit: "px", decimals: 0),
            .slider(\.frostSpread, "Frost spread", 0...1.5),
            .slider(\.darknessStart, "Darkness start", 0...1),
        ]),
        TunerFolder("Motion", [
            .bezier(\.progressCurve, "Progress curve"),
        ]),
    ])
}

public final class FrostTransition: Transition {
    public static let id = "frost"
    public static let displayName = "Frost"
    public static let summary = "The screen frosts over from the top edge and fades to black."
    public static let thumbnailProgress = 0.4
    public static let fragmentFunctionName = "frostFragment"

    public var params = FrostParams()

    public init() {}

    public func prepare(snapshot: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) -> MTLTexture {
        MipChain.build(from: snapshot, device: device, commandQueue: commandQueue)
    }

    public func uniforms(progress: Double, context: RenderContext) -> TransitionUniforms {
        var u = TransitionUniforms()
        u.progress = Float(params.progressCurve.value(at: progress))
        u.maxBlur = context.reduceTransparency ? 0 : Float(params.maxBlur)
        u.frostSpread = Float(params.frostSpread)
        u.darknessStart = Float(params.darknessStart)
        return u
    }
}
