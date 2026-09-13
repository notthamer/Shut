import Foundation
import Tuner

/// Fade: a plain dim to black over the live desktop. Needs no snapshot and no
/// Screen Recording, which also makes it the Reduce Motion fallback and the
/// stand-in when a snapshot style has no permission. Math from Bendable's
/// FadePreset (MIT, © 2026 Anti Ltd).
public struct FadeParams: TunableParameters {
    public var intensity = 1.0
    public var dimming = 1.0

    public init() {}

    public static let tunerID = "fade"
    public static let tunerDisplayName = "Fade"
    public static let defaults = FadeParams()
    public static let schema = TunerSchema<FadeParams>([
        TunerFolder("Look", [
            .slider(\.intensity, "Intensity", 0...1, featured: true, help: "How strongly the fade answers the lid."),
            .slider(\.dimming, "Dimming", 0...1, featured: true, help: "How dark it gets when fully shut."),
        ]),
    ])
}

public final class FadeTransition: PanelTransition {
    public static let id = "fade"
    public static let displayName = "Fade"
    public static let summary = "A plain dim to black. Needs no Screen Recording."
    public static let isTransparent = true
    public static let needsSnapshot = false
    public static let thumbnailProgress = 0.22

    public var params = FadeParams()
    public init() {}

    public func frame(progress: Double, context: RenderContext) -> PanelFrame {
        var frame = PanelFrame()
        frame.usesSnapshot = false
        frame.brightness = 0
        frame.opacity = Easing.easeInOutCubic(normalize(progress, in: 0.05...0.95))
            * clamp(params.intensity, 0, 1) * params.dimming
        return frame
    }
}
