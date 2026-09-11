import Foundation
import Tuner

/// Slide: the desktop slides down out of sight behind the hinge, accelerating
/// as it goes. Ported from Bendable's SlidePreset (MIT, © 2026 Anti Ltd).
public struct SlideParams: TunableParameters {
    public var intensity = 1.0
    public var blur = 1.0
    public var washout = 1.0
    public var corners = 1.0
    public var dimming = 1.0

    public init() {}

    public static let tunerID = "slide"
    public static let tunerDisplayName = "Slide"
    public static let defaults = SlideParams()
    public static let schema = TunerSchema<SlideParams>([
        TunerFolder("Strength", [
            .slider(\.intensity, "Intensity", 0...1, featured: true, help: "How strongly the whole effect answers the lid."),
        ]),
        TunerFolder("Look", [
            .slider(\.blur, "Blur", 0...1, featured: true, help: "Motion blur as it drops, and defocus at the end."),
            .slider(\.washout, "Washout", 0...1, help: "How much colour drains out near the end."),
            .slider(\.corners, "Corner rounding", 0...1, featured: true, help: "How rounded the corners are."),
            .slider(\.dimming, "Dimming", 0...1, featured: true, help: "How far the screen fades toward black."),
        ]),
    ])
}

public final class SlideTransition: PanelTransition {
    public static let id = "slide"
    public static let displayName = "Slide"
    public static let summary = "The desktop slides down out of sight, behind the hinge."
    public static let thumbnailProgress = 0.7

    public var params = SlideParams()
    public init() {}

    /// Two half-heights: exactly one frame height, so it is fully gone at the end.
    private let travel = 2.0

    public func frame(progress: Double, context: RenderContext) -> PanelFrame {
        let p = params
        let intensity = clamp(p.intensity, 0, 1)
        let velocity = Double(context.velocity)
        let closure = clamp(progress, 0, 1)

        var frame = PanelFrame()
        frame.usesSnapshot = true
        frame.opacity = 1

        let distance = Easing.easeInCubic(closure) * travel * intensity
        frame.translate = SIMD2(0, Float(-distance))

        frame.cornerRadius = Easing.smoothstep(normalize(closure, in: 0.0...0.25)) * 0.09 * intensity * p.corners

        let motionBlur = clamp(abs(velocity) * 0.30, 0, 0.5)
        let defocus = Easing.easeOutQuad(normalize(closure, in: 0.6...1.0)) * 0.35
        frame.blur = clamp((defocus + motionBlur) * intensity * p.blur, 0, 1)

        frame.wash = Easing.easeOutQuad(normalize(closure, in: 0.55...1.0)) * 0.7 * intensity * p.washout
        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.55...1.0)) * 0.85 * p.dimming
        frame.brightness = clamp(1 - dim, 0, 1)
        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.5...1.0)) * 0.4 * intensity
        return frame
    }
}
