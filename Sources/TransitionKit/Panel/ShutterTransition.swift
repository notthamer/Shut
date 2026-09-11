import Foundation
import Tuner

/// Shutter: bars close in from the top and bottom over the live desktop.
/// Ported from Bendable's ShutterPreset (MIT, © 2026 Anti Ltd).
public struct ShutterParams: TunableParameters {
    public var intensity = 1.0
    public var dimming = 1.0

    public init() {}

    public static let tunerID = "shutter"
    public static let tunerDisplayName = "Shutter"
    public static let defaults = ShutterParams()
    public static let schema = TunerSchema<ShutterParams>([
        TunerFolder("Look", [
            .slider(\.intensity, "Intensity", 0...1, featured: true, help: "How strongly the bars answer the lid."),
            .slider(\.dimming, "Dimming", 0...1, featured: true, help: "How dark the bars are."),
        ]),
    ])
}

public final class ShutterTransition: PanelTransition {
    public static let id = "shutter"
    public static let displayName = "Shutter"
    public static let summary = "Bars close in from the top and bottom. Needs no Screen Recording."
    public static let isTransparent = true
    public static let needsSnapshot = false
    public static let thumbnailProgress = 0.32

    public var params = ShutterParams()
    public init() {}

    public func frame(progress: Double, context: RenderContext) -> PanelFrame {
        let intensity = clamp(params.intensity, 0, 1)
        let closure = clamp(progress, 0, 1)
        var frame = PanelFrame()
        frame.usesSnapshot = false
        frame.brightness = 0
        frame.opacity = params.dimming
        let openness = 1 - Easing.easeInOutCubic(normalize(closure, in: 0.02...0.97))
        frame.mask = .shutter(openness: lerp(1, openness, intensity))
        return frame
    }
}
