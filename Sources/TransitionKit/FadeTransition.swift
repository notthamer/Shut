import Foundation
import Tuner

/// Parameters for the fade. Deliberately tiny; it's the pipeline smoke test and
/// the Reduce Motion fallback.
public struct FadeParams: TunableParameters {
    public var progressCurve: TunerBezier = .linear

    public init() {}

    public static let tunerID = "fade"
    public static let tunerDisplayName = "Fade"
    public static let defaults = FadeParams()
    public static let schema = TunerSchema<FadeParams>([
        TunerFolder("Motion", [
            .bezier(\.progressCurve, "Progress curve"),
        ]),
    ])
}

public final class FadeTransition: Transition {
    public static let id = "fade"
    public static let displayName = "Fade"
    public static let fragmentFunctionName = "fadeFragment"

    public var params = FadeParams()

    public init() {}

    public func uniforms(progress: Double, context: RenderContext) -> TransitionUniforms {
        var u = TransitionUniforms()
        u.progress = Float(params.progressCurve.value(at: progress))
        return u
    }
}
