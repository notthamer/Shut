import Foundation
import Tuner

/// Blinds: slats close down the screen, each shutting from its own edges inward.
/// Ported from Bendable's BlindsPreset (MIT, © 2026 Anti Ltd).
public struct BlindsParams: TunableParameters {
    public var intensity = 1.0
    public var dimming = 1.0
    public var slats = 6

    public init() {}

    public static let tunerID = "blinds"
    public static let tunerDisplayName = "Blinds"
    public static let defaults = BlindsParams()
    public static let schema = TunerSchema<BlindsParams>([
        TunerFolder("Look", [
            .slider(\.intensity, "Intensity", 0...1, featured: true, help: "How strongly the slats answer the lid."),
            .slider(\.slats, "Slats", 2...24, featured: true, help: "How many slats the screen is cut into."),
            .slider(\.dimming, "Dimming", 0...1, featured: true, help: "How dark the closed slats are."),
        ]),
    ])
}

public final class BlindsTransition: PanelTransition {
    public static let id = "blinds"
    public static let displayName = "Blinds"
    public static let summary = "Slats close down the screen, each one shutting from its edges in. Needs no Screen Recording."
    public static let isTransparent = true
    public static let needsSnapshot = false
    public static let thumbnailProgress = 0.5

    public var params = BlindsParams()
    public init() {}

    public func frame(progress: Double, context: RenderContext) -> PanelFrame {
        let intensity = clamp(params.intensity, 0, 1)
        let closure = clamp(progress, 0, 1)
        var frame = PanelFrame()
        frame.usesSnapshot = false
        frame.brightness = 0
        frame.opacity = params.dimming
        let openness = 1 - Easing.easeInOutCubic(normalize(closure, in: 0.0...0.95))
        frame.mask = .blinds(slats: params.slats, openness: lerp(1, openness, intensity))
        return frame
    }
}
