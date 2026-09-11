import Foundation
import Tuner

/// Curl: the top edge rolls over and away on a soft bend, the way a sheet of
/// paper lifts off a desk. Ported from Bendable's CurlPreset (MIT, © 2026 Anti Ltd).
public struct CurlParams: TunableParameters {
    public var intensity = 1.0
    public var perspective = 1.0
    public var tilt = 1.0
    public var blur = 1.0
    public var variableBlur = 0.85
    public var washout = 1.0
    public var corners = 1.0
    public var dimming = 1.0

    public init() {}

    public static let tunerID = "curl"
    public static let tunerDisplayName = "Curl"
    public static let defaults = CurlParams()
    public static let schema = TunerSchema<CurlParams>([
        TunerFolder("Strength", [
            .slider(\.intensity, "Intensity", 0...1, featured: true, help: "How strongly the whole effect answers the lid."),
        ]),
        TunerFolder("Look", [
            .slider(\.tilt, "Roll", 0...1, featured: true, help: "How far the top edge rolls over."),
            .slider(\.perspective, "Perspective", 0...1, featured: true, help: "How much the rolled part recedes."),
            .slider(\.blur, "Blur", 0...1, help: "How far out of focus the screen drifts."),
            .slider(\.variableBlur, "Variable blur", 0...1, help: "Keeps the hinge edge sharper than the far edge."),
            .slider(\.washout, "Washout", 0...1, help: "How much colour drains out."),
            .slider(\.corners, "Corner rounding", 0...1, help: "How rounded the corners are."),
            .slider(\.dimming, "Dimming", 0...1, featured: true, help: "How far the screen fades toward black."),
        ]),
    ])
}

public final class CurlTransition: PanelTransition {
    public static let id = "curl"
    public static let displayName = "Curl"
    public static let summary = "The top edge curls over and away, the way a sheet of paper lifts."
    public static let thumbnailProgress = 0.54

    public var params = CurlParams()
    public init() {}

    private let creasePosition = 0.68
    private let maximumRoll = 95.0

    public func frame(progress: Double, context: RenderContext) -> PanelFrame {
        let p = params
        let intensity = clamp(p.intensity, 0, 1)
        let velocity = Double(context.velocity)
        let closure = clamp(progress, 0, 1)

        var frame = PanelFrame()
        frame.usesSnapshot = true
        frame.opacity = 1
        frame.foldPosition = creasePosition

        let rolled = Easing.easeInOutCubic(closure) * maximumRoll * lerp(0.6, 1.0, intensity) * p.tilt
        frame.foldAngle = min(rolled, maximumRoll) * .pi / 180
        frame.perspective = lerp(0.5, 1.0, intensity) * p.perspective

        frame.curvature = sin(min(frame.foldAngle, .pi)) * 0.16 * intensity
        frame.creaseHighlight = sin(min(frame.foldAngle, .pi)) * 0.30 * intensity

        frame.cornerRadius = Easing.smoothstep(normalize(closure, in: 0.0...0.3)) * 0.06 * intensity * p.corners

        let defocus = Easing.easeOutQuad(normalize(closure, in: 0.45...0.95))
        let motionBlur = clamp(abs(velocity) * 0.20, 0, 0.40)
        frame.blur = clamp((defocus * 0.75 + motionBlur) * intensity * p.blur, 0, 1)
        frame.blurGradient = clamp(0.9 * intensity * p.variableBlur, 0, 1)
        frame.wash = Easing.easeOutQuad(normalize(closure, in: 0.45...0.95)) * intensity * p.washout

        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.5...0.98)) * p.dimming
        frame.brightness = clamp(1 - dim, 0, 1)
        frame.edgeOcclusion = Easing.easeOutQuad(normalize(closure, in: 0.0...0.4)) * intensity
        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.4...0.95)) * 0.5 * intensity
        return frame
    }
}
