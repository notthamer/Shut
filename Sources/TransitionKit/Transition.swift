import Foundation
import Metal
import Tuner

/// Everything the renderer needs to know about the output surface and the
/// screen geometry. All lengths are in *snapshot pixels* with a top-left origin,
/// which is also the coordinate space the shaders work in. The preview window
/// draws the same snapshot scaled down, so it shares this context unchanged.
public struct RenderContext: Equatable {
    /// Size of the snapshot texture in pixels.
    public var snapshotSize: SIMD2<Float>
    /// Where content drains to, in snapshot pixels.
    public var sinkPoint: SIMD2<Float>
    /// Width/height of the notch (or virtual notch) in snapshot pixels.
    public var notchSize: SIMD2<Float>
    /// True when there is no hardware notch and the shader should draw a pill.
    public var usesVirtualNotch: Bool
    /// Accessibility: Reduce Transparency is on, so blur must be disabled.
    public var reduceTransparency: Bool
    /// Seconds since the transition was shown; lets shaders animate glow etc.
    public var time: Float
    /// Snapshot pixels per screen point (2 on every Retina MacBook).
    public var scale: Float
    /// dp/dt in progress units per second, positive while closing. Drives motion
    /// blur and the small velocity lead in Fold and Crease. 0 when scrubbing.
    public var velocity: Float
    /// Degrees of lid travel the effect spans. Fold and Crease turn their panel
    /// by exactly the degrees the lid has swept, so this makes the counter-rotation
    /// degree-for-degree.
    public var hingeTravelDegrees: Float

    public init(snapshotSize: SIMD2<Float>, sinkPoint: SIMD2<Float>, notchSize: SIMD2<Float>,
                usesVirtualNotch: Bool, reduceTransparency: Bool = false, time: Float = 0, scale: Float = 2,
                velocity: Float = 0, hingeTravelDegrees: Float = 85) {
        self.snapshotSize = snapshotSize
        self.sinkPoint = sinkPoint
        self.notchSize = notchSize
        self.usesVirtualNotch = usesVirtualNotch
        self.reduceTransparency = reduceTransparency
        self.time = time
        self.scale = scale
        self.velocity = velocity
        self.hingeTravelDegrees = hingeTravelDegrees
    }
}

/// A screen transition: a parameter struct plus a Metal fragment function.
///
/// The renderer is shared. Adding a transition means one Swift file (the params
/// and this conformance) and one fragment function in a `.metal` file.
public protocol Transition: AnyObject {
    associatedtype Params: TunableParameters

    static var id: String { get }
    static var displayName: String { get }
    /// One line for the gallery, e.g. "The desktop drains into the notch."
    static var summary: String { get }
    /// Name of the fragment function in the TransitionKit Metal library.
    static var fragmentFunctionName: String { get }
    /// Vertex function paired with the fragment. Default: the full-screen triangle.
    static var vertexFunctionName: String { get }
    /// True: draw the 48×48 panel grid with premultiplied blending instead of one triangle.
    static var usesPanelMesh: Bool { get }
    /// True: the output has alpha and composites over the live desktop, so the
    /// overlay window goes transparent for it.
    static var isTransparent: Bool { get }
    /// False: plays without a snapshot, and therefore without Screen Recording.
    static var needsSnapshot: Bool { get }
    /// Progress at which the gallery thumbnail is rendered.
    static var thumbnailProgress: Double { get }
    /// A short tag shown next to the name where there is room ("iPhone Duo").
    static var badge: String? { get }

    var params: Params { get set }

    /// Called once per snapshot before the first frame. Return the texture the
    /// fragment shader should sample; Frost uses this to build a mip chain.
    func prepare(snapshot: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) -> MTLTexture

    /// Packs params plus progress into the shared uniform struct.
    func uniforms(progress: Double, context: RenderContext) -> TransitionUniforms
}

public extension Transition {
    static var summary: String { "" }
    static var vertexFunctionName: String { "fullscreenVertex" }
    static var usesPanelMesh: Bool { false }
    static var isTransparent: Bool { false }
    static var needsSnapshot: Bool { true }
    static var thumbnailProgress: Double { 0.35 }
    static var badge: String? { nil }

    var id: String { Self.id }
    var displayName: String { Self.displayName }
    var fragmentFunctionName: String { Self.fragmentFunctionName }

    func prepare(snapshot: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) -> MTLTexture {
        snapshot
    }
}

/// Type-erased transition so the renderer, menu, and preview can hold "the
/// current transition" without generics leaking everywhere.
public final class AnyTransition {
    public let id: String
    public let displayName: String
    public let summary: String
    public let fragmentFunctionName: String
    public let vertexFunctionName: String
    public let usesPanelMesh: Bool
    public let isTransparent: Bool
    public let needsSnapshot: Bool
    public let thumbnailProgress: Double
    public let badge: String?
    private let prepareImpl: (MTLTexture, MTLDevice, MTLCommandQueue) -> MTLTexture
    private let uniformsImpl: (Double, RenderContext) -> TransitionUniforms
    private let jsonGet: () -> Data?
    private let jsonSet: (Data) -> Bool
    private let resetImpl: () -> Void
    public let base: AnyObject

    public init<T: Transition>(_ transition: T) {
        base = transition
        id = T.id
        displayName = T.displayName
        summary = T.summary
        fragmentFunctionName = T.fragmentFunctionName
        vertexFunctionName = T.vertexFunctionName
        usesPanelMesh = T.usesPanelMesh
        isTransparent = T.isTransparent
        needsSnapshot = T.needsSnapshot
        thumbnailProgress = T.thumbnailProgress
        badge = T.badge
        prepareImpl = { transition.prepare(snapshot: $0, device: $1, commandQueue: $2) }
        uniformsImpl = { transition.uniforms(progress: $0, context: $1) }
        jsonGet = {
            // Sorted keys so the JSON is a stable cache key and diff-friendly on disk.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try? encoder.encode(transition.params)
        }
        jsonSet = { data in
            guard let p = try? JSONDecoder().decode(T.Params.self, from: data) else { return false }
            transition.params = p
            return true
        }
        resetImpl = { transition.params = T.Params.defaults }
    }

    public func prepare(snapshot: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) -> MTLTexture {
        prepareImpl(snapshot, device, commandQueue)
    }

    public func uniforms(progress: Double, context: RenderContext) -> TransitionUniforms {
        uniformsImpl(progress, context)
    }

    /// Current params as JSON, for presets and the menu bar.
    public var paramsJSON: Data? { jsonGet() }

    /// Params as a dictionary, for the few places the app needs a value without
    /// knowing the concrete struct (progress curve, pour-out spring).
    public var paramsObject: [String: Any] {
        guard let data = paramsJSON,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    public func doubleParam(_ key: String, default value: Double) -> Double {
        paramsObject[key] as? Double ?? value
    }

    public func bezierParam(_ key: String) -> TunerBezier {
        guard let curve = paramsObject[key] as? [String: Double],
              let x1 = curve["x1"], let y1 = curve["y1"], let x2 = curve["x2"], let y2 = curve["y2"] else {
            return .linear
        }
        return TunerBezier(x1, y1, x2, y2)
    }
    @discardableResult public func setParams(json: Data) -> Bool { jsonSet(json) }
    public func resetParams() { resetImpl() }
}
