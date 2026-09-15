import Foundation
import simd

public enum PanelMask: Equatable {
    case none
    case aperture(blades: Int, openness: Double)
    case shutter(openness: Double)
    case blinds(slats: Int, openness: Double)
}

/// The pure output of a panel style's math, one step before packing into
/// uniforms. Port of Bendable's FrameDescription (MIT, © 2026 Anti Ltd).
public struct PanelFrame: Equatable {
    /// Rotation of the part above the crease, radians, away from the viewer.
    public var foldAngle = 0.0
    /// Height of the crease from the bottom, 0...1. 0 folds about the hinge edge.
    public var foldPosition = 0.5
    /// 0 orthographic, 1 full keystone.
    public var perspective = 0.0
    /// Bow just past the crease.
    public var curvature = 0.0
    public var creaseHighlight = 0.0
    public var scale: SIMD2<Float> = .one
    public var translate: SIMD2<Float> = .zero
    public var blur = 0.0
    /// 1 = far edge blurs first, 0 = evenly.
    public var blurGradient = 0.0
    public var wash = 0.0
    /// In half-heights; 0.1 is a clearly rounded corner.
    public var cornerRadius = 0.0
    public var brightness = 1.0
    /// Overlay alpha. Mask styles paint black at this alpha over the live desktop.
    public var opacity = 1.0
    public var vignette = 0.0
    public var edgeOcclusion = 0.0
    public var mask: PanelMask = .none
    /// False: paint flat black at `opacity` instead of the snapshot.
    public var usesSnapshot = true

    public init() {}

    /// Packs into the shared uniforms with the usual clamps.
    public func uniforms(progress: Double) -> TransitionUniforms {
        var u = TransitionUniforms()
        u.progress = Float(progress)
        u.meshScale = scale
        u.meshTranslate = translate
        u.foldAngle = Float(foldAngle)
        u.foldPosition = Float(clamp(foldPosition, 0, 1))
        u.perspective = Float(perspective)
        u.curvature = Float(curvature)
        u.creaseHighlight = Float(clamp(creaseHighlight, 0, 1))
        u.blur = Float(clamp(blur, 0, 1))
        u.blurGradient = Float(clamp(blurGradient, 0, 1))
        u.wash = Float(clamp(wash, 0, 1))
        u.cornerRadius = Float(clamp(cornerRadius, 0, 1))
        u.brightness = Float(max(brightness, 0))
        u.opacity = Float(clamp(opacity, 0, 1))
        u.vignette = Float(clamp(vignette, 0, 1))
        u.edgeOcclusion = Float(clamp(edgeOcclusion, 0, 1))
        u.useTexture = usesSnapshot ? 1 : 0
        switch mask {
        case .none:
            u.maskKind = 0
        case let .aperture(blades, openness):
            u.maskKind = 1
            u.blades = UInt32(clamp(blades, 3, 16))
            u.maskOpenness = Float(clamp(openness, 0, 1))
        case let .shutter(openness):
            u.maskKind = 2
            u.maskOpenness = Float(clamp(openness, 0, 1))
        case let .blinds(slats, openness):
            u.maskKind = 3
            // Shares the blade count: both answer "how many pieces is the mask made of".
            u.blades = UInt32(clamp(slats, 2, 24))
            u.maskOpenness = Float(clamp(openness, 0, 1))
        }
        return u
    }
}
