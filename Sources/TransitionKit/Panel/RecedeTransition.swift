import Foundation
import Tuner

/// Recede: the desktop drops straight back into the dark, square to you the
/// whole way, with no rotation at all. Ported from Bendable's RecedePreset
/// (MIT, © 2026 Anti Ltd).
public struct RecedeParams: TunableParameters {
    public var intensity = 1.0
    public var depth = 1.0
    public var blur = 1.0
    public var variableBlur = 0.85
    public var washout = 1.0
    public var corners = 1.0
    public var dimming = 1.0

    public init() {}

    public static let tunerID = "recede"
    public static let tunerDisplayName = "Recede"
    public static let defaults = RecedeParams()
    public static let schema = TunerSchema<RecedeParams>([
        TunerFolder("Strength", [
            .slider(\.intensity, "Intensity", 0...1, featured: true, help: "How strongly the whole effect answers the lid."),
        ]),
        TunerFolder("Look", [
            .slider(\.depth, "Depth", 0...1, featured: true, help: "How small the desktop gets before it goes dark."),
            .slider(\.blur, "Blur", 0...1, featured: true, help: "How far out of focus the screen drifts."),
            .slider(\.variableBlur, "Variable blur", 0...1, help: "Keeps the bottom sharper than the top."),
            .slider(\.washout, "Washout", 0...1, help: "How much colour drains out."),
            .slider(\.corners, "Corner rounding", 0...1, help: "How rounded the corners are."),
            .slider(\.dimming, "Dimming", 0...1, featured: true, help: "How far the screen fades toward black."),
        ]),
    ])
}

public final class RecedeTransition: PanelTransition {
    public static let id = "recede"
    public static let displayName = "Recede"
    public static let summary = "The desktop drops straight back into the dark, square to you the whole way."
    public static let thumbnailProgress = 0.42

    public var params = RecedeParams()
    public init() {}

    public func frame(progress: Double, context: RenderContext) -> PanelFrame {
        let p = params
        let intensity = clamp(p.intensity, 0, 1)
        let velocity = Double(context.velocity)
        let closure = clamp(progress, 0, 1)

        var frame = PanelFrame()
        frame.usesSnapshot = true
        frame.opacity = 1

        // `depth` chooses how small it gets: 1 = Bendable's 0.42, 0 = no shrink.
        let smallestScale = lerp(1.0, 0.42, clamp(p.depth, 0, 1))
        let travelled = Easing.easeInOutCubic(closure) * intensity
        let size = lerp(1, smallestScale, travelled)
        frame.scale = SIMD2(Float(size), Float(size))

        frame.cornerRadius = Easing.smoothstep(normalize(closure, in: 0.0...0.35)) * 0.10 * intensity * p.corners

        let defocus = Easing.easeOutQuad(normalize(closure, in: 0.35...0.95))
        let motionBlur = clamp(abs(velocity) * 0.18, 0, 0.35)
        frame.blur = clamp((defocus * 0.7 + motionBlur) * intensity * p.blur, 0, 1)
        frame.blurGradient = clamp(0.45 * intensity * p.variableBlur, 0, 1)
        frame.wash = Easing.easeOutQuad(normalize(closure, in: 0.4...0.95)) * intensity * p.washout

        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.25...0.96)) * p.dimming
        frame.brightness = clamp(1 - dim, 0, 1)
        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.1...0.9)) * 0.7 * intensity
        return frame
    }
}
