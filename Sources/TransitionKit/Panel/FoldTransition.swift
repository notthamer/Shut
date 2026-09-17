import Foundation
import Tuner

/// Fold: the desktop turns against the lid, degree for degree, so it appears to
/// stand still in space while the machine folds away under it. Ported code
/// (MIT, © 2026 Anti Ltd).
public struct FoldParams: TunableParameters {
    public var intensity = 1.0
    public var perspective = 1.0
    public var tilt = 1.0
    public var blur = 1.0
    /// Where in the close the picture starts going out of focus. 0 is the first degree.
    public var blurOnset = 0.1
    public var variableBlur = 0.85
    public var washout = 1.0
    public var corners = 1.0
    public var dimming = 1.0

    public init() {}

    /// Saved values and presets from before a dial existed still load: any key
    /// that is missing keeps its default instead of failing the whole struct.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FoldParams()
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? d.intensity
        perspective = try c.decodeIfPresent(Double.self, forKey: .perspective) ?? d.perspective
        tilt = try c.decodeIfPresent(Double.self, forKey: .tilt) ?? d.tilt
        blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? d.blur
        blurOnset = try c.decodeIfPresent(Double.self, forKey: .blurOnset) ?? d.blurOnset
        variableBlur = try c.decodeIfPresent(Double.self, forKey: .variableBlur) ?? d.variableBlur
        washout = try c.decodeIfPresent(Double.self, forKey: .washout) ?? d.washout
        corners = try c.decodeIfPresent(Double.self, forKey: .corners) ?? d.corners
        dimming = try c.decodeIfPresent(Double.self, forKey: .dimming) ?? d.dimming
    }

    public static let tunerID = "fold"
    public static let tunerDisplayName = "Fold"
    public static let defaults = FoldParams()
    public static let schema = TunerSchema<FoldParams>([
        TunerFolder("Strength", [
            .slider(\.intensity, "Intensity", 0...1, featured: true, help: "How strongly the whole effect answers the lid."),
        ]),
        TunerFolder("Look", [
            .slider(\.perspective, "Perspective", 0...1, featured: true, help: "How much the screen appears to recede as it tips back."),
            .slider(\.tilt, "Tilt", 0...1, featured: true, help: "How far the screen turns away for a given lid angle."),
            .slider(\.blur, "Blur", 0...1, featured: true, help: "How far out of focus the screen drifts."),
            .slider(\.blurOnset, "Blur onset", 0...1, help: "How soon the picture softens. Left: from the first degree, like a Duo folding. Right: only near the end."),
            .slider(\.variableBlur, "Variable blur", 0...1, help: "Keeps the hinge edge sharper than the far edge. At zero, blur and washout apply evenly."),
            .slider(\.washout, "Washout", 0...1, help: "How much colour drains out."),
            .slider(\.corners, "Corner rounding", 0...1, help: "How rounded the corners are."),
            .slider(\.dimming, "Dimming", 0...1, featured: true, help: "How far the screen fades toward black."),
        ]),
    ])
}

public final class FoldTransition: PanelTransition {
    public static let id = "fold"
    public static let displayName = "Fold"
    public static let badge: String? = "iPhone Duo"
    public static let summary = "The iPhone Duo close: the desktop stays standing where it was while the lid folds away under it."
    public static let thumbnailProgress = 0.32

    public var params = FoldParams()
    public init() {}

    private let velocityLead = 0.016
    private let linearTiltLimit = 60.0
    private let maximumTilt = 85.0

    public func frame(progress: Double, context: RenderContext) -> PanelFrame {
        let p = params
        let intensity = clamp(p.intensity, 0, 1)
        let velocity = Double(context.velocity)
        let closure = panelClosure(progress: progress, velocity: velocity, lead: velocityLead)

        var frame = PanelFrame()
        frame.usesSnapshot = true
        frame.opacity = 1
        frame.foldPosition = 0

        // Turn by exactly the degrees the lid has swept, softly limited so a lid
        // that goes past 60° of travel never folds the picture through the desk.
        let swept = closure * Double(context.hingeTravelDegrees) * lerp(0.55, 1.0, intensity) * p.tilt
        frame.foldAngle = softLimited(swept, linearUpTo: linearTiltLimit, ceiling: maximumTilt) * .pi / 180
        frame.perspective = lerp(0.55, 1.0, intensity) * p.perspective

        // The Duo look: focus goes as soon as the panel starts to turn, so the
        // softening reads as depth rather than as a fade tacked on at the end.
        let onset = lerp(0.0, 0.6, clamp(p.blurOnset, 0, 1))
        let defocus = Easing.easeOutQuad(normalize(closure, in: onset...(onset + 0.5)))
        let motionBlur = clamp(abs(velocity) * 0.22, 0, 0.45)
        frame.blur = clamp((defocus * 0.95 + motionBlur) * intensity * p.blur, 0, 1)
        frame.blurGradient = clamp(
            lerp(1.0, 0.5, Easing.smoothstep(normalize(closure, in: 0.55...0.95))) * intensity * p.variableBlur, 0, 1)
        frame.wash = Easing.easeOutQuad(normalize(closure, in: 0.30...0.88)) * intensity * p.washout
        frame.cornerRadius = Easing.smoothstep(normalize(closure, in: 0.0...0.28)) * 0.085 * intensity * p.corners
        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.30...0.94)) * p.dimming
        frame.brightness = clamp(1 - dim, 0, 1)
        frame.edgeOcclusion = Easing.easeOutQuad(normalize(closure, in: 0.0...0.30)) * intensity
        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.3...0.9)) * 0.55 * intensity
        return frame
    }
}
