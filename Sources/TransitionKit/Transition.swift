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

    public init(snapshotSize: SIMD2<Float>, sinkPoint: SIMD2<Float>, notchSize: SIMD2<Float>,
                usesVirtualNotch: Bool, reduceTransparency: Bool = false, time: Float = 0) {
        self.snapshotSize = snapshotSize
        self.sinkPoint = sinkPoint
        self.notchSize = notchSize
        self.usesVirtualNotch = usesVirtualNotch
        self.reduceTransparency = reduceTransparency
        self.time = time
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
    /// Name of the fragment function in the TransitionKit Metal library.
    static var fragmentFunctionName: String { get }

    var params: Params { get set }

    /// Called once per snapshot before the first frame. Return the texture the
    /// fragment shader should sample; Frost uses this to build a mip chain.
    func prepare(snapshot: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) -> MTLTexture

    /// Packs params plus progress into the shared uniform struct.
    func uniforms(progress: Double, context: RenderContext) -> TransitionUniforms
}

public extension Transition {
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
    public let fragmentFunctionName: String
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
        fragmentFunctionName = T.fragmentFunctionName
        prepareImpl = { transition.prepare(snapshot: $0, device: $1, commandQueue: $2) }
        uniformsImpl = { transition.uniforms(progress: $0, context: $1) }
        jsonGet = { try? JSONEncoder().encode(transition.params) }
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
    @discardableResult public func setParams(json: Data) -> Bool { jsonSet(json) }
    public func resetParams() { resetImpl() }
}
