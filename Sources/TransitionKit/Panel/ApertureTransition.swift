import Foundation
import Tuner

/// Aperture: iris blades close over the live desktop. No snapshot needed.
/// Ported from Bendable's AperturePreset (MIT, © 2026 Anti Ltd).
public struct ApertureParams: TunableParameters {
    public var intensity = 1.0
    public var dimming = 1.0
    public var blades = 6

    public init() {}

    public static let tunerID = "aperture"
    public static let tunerDisplayName = "Aperture"
    public static let defaults = ApertureParams()
    public static let schema = TunerSchema<ApertureParams>([
        TunerFolder("Look", [
            .slider(\.intensity, "Intensity", 0...1, featured: true, help: "How strongly the iris answers the lid."),
            .slider(\.blades, "Blades", 3...16, featured: true, help: "How many blades the iris has."),
            .slider(\.dimming, "Dimming", 0...1, featured: true, help: "How dark the closed blades are."),
        ]),
    ])
}

public final class ApertureTransition: PanelTransition {
    public static let id = "aperture"
    public static let displayName = "Aperture"
    public static let summary = "Iris blades close over the screen. Needs no Screen Recording."
    public static let isTransparent = true
    public static let needsSnapshot = false
    public static let thumbnailProgress = 0.32

    public var params = ApertureParams()
    public init() {}

    public func frame(progress: Double, context: RenderContext) -> PanelFrame {
        let intensity = clamp(params.intensity, 0, 1)
        let closure = clamp(progress, 0, 1)
        var frame = PanelFrame()
        frame.usesSnapshot = false
        frame.brightness = 0
        frame.opacity = params.dimming
        let openness = 1 - Easing.easeOutQuad(normalize(closure, in: 0.0...0.94))
        frame.mask = .aperture(blades: params.blades, openness: lerp(1, openness, intensity))
        frame.vignette = Easing.smoothstep(closure) * 0.3 * intensity
        return frame
    }
}
