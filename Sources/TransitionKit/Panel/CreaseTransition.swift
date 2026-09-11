import Foundation
import Tuner

/// Crease: a book fold. The desktop creases across its middle and only the upper
/// half rotates away, with a bowed crease and a highlight catching the bend.
/// Ported from Bendable's CreasePreset (MIT, © 2026 Anti Ltd).
public struct CreaseParams: TunableParameters {
    public var intensity = 1.0
    public var perspective = 1.0
    public var tilt = 1.0
    public var blur = 1.0
    public var corners = 1.0
    public var dimming = 1.0
    public var creasePosition = 0.5

    public init() {}

    public static let tunerID = "crease"
    public static let tunerDisplayName = "Crease"
    public static let defaults = CreaseParams()
    public static let schema = TunerSchema<CreaseParams>([
        TunerFolder("Strength", [
            .slider(\.intensity, "Intensity", 0...1, featured: true, help: "How strongly the whole effect answers the lid."),
        ]),
        TunerFolder("Look", [
            .slider(\.creasePosition, "Crease height", 0.2...0.8, featured: true, help: "Where the fold line sits, from the hinge up."),
            .slider(\.perspective, "Perspective", 0...1, featured: true, help: "How much the upper half recedes as it tips back."),
            .slider(\.tilt, "Tilt", 0...1, help: "How far the upper half turns for a given lid angle."),
            .slider(\.blur, "Blur", 0...1, help: "How far out of focus the screen drifts near the end."),
            .slider(\.corners, "Corner rounding", 0...1, help: "How rounded the corners are."),
            .slider(\.dimming, "Dimming", 0...1, featured: true, help: "How far the screen fades toward black."),
        ]),
    ])
}

public final class CreaseTransition: PanelTransition {
    public static let id = "crease"
    public static let displayName = "Crease"
    public static let summary = "The desktop creases across the middle and folds away in perspective."
    public static let thumbnailProgress = 0.32

    public var params = CreaseParams()
    public init() {}

    private let velocityLead = 0.016

    public func frame(progress: Double, context: RenderContext) -> PanelFrame {
        let p = params
        let intensity = clamp(p.intensity, 0, 1)
        let velocity = Double(context.velocity)
        let closure = panelClosure(progress: progress, velocity: velocity, lead: velocityLead)

        var frame = PanelFrame()
        frame.usesSnapshot = true
        frame.opacity = 1
        frame.foldPosition = p.creasePosition

        let sweptDegrees = closure * Double(context.hingeTravelDegrees) * lerp(0.6, 1.0, intensity) * p.tilt
        frame.foldAngle = sweptDegrees * .pi / 180
        frame.perspective = lerp(0.5, 1.0, intensity) * p.perspective
        frame.cornerRadius = Easing.smoothstep(normalize(closure, in: 0.0...0.3)) * 0.07 * intensity * p.corners

        let bend = sin(min(frame.foldAngle, .pi))
        frame.curvature = bend * 0.07 * intensity

        let defocus = Easing.easeInOutCubic(normalize(closure, in: 0.72...0.99))
        let motionBlur = clamp(abs(velocity) * 0.20, 0, 0.40)
        frame.blur = clamp((defocus * 0.8 + motionBlur) * intensity * p.blur, 0, 1)

        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.66...1.0)) * p.dimming
        frame.brightness = clamp(1 - dim, 0, 1)
        frame.creaseHighlight = bend * 0.55 * intensity * frame.brightness
        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.35...0.95)) * 0.55 * intensity
        frame.edgeOcclusion = Easing.smoothstep(normalize(closure, in: 0.0...0.55)) * intensity
        return frame
    }
}
