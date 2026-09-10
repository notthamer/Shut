import Foundation
import Metal
import MetalKit
import QuartzCore

/// The one renderer every transition shares.
///
/// It owns the Metal device, the compiled shader library, one pipeline state per
/// fragment function, the snapshot texture, and a small uniform buffer. Drawing a
/// frame is: bind the snapshot, write uniforms, draw one triangle.
public final class TransitionRenderer {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private let uniformBuffer: MTLBuffer

    /// The raw captured frame. Set with `setSnapshot`; released with `clearSnapshot`.
    public private(set) var snapshot: MTLTexture?
    /// Whatever the active transition wants to sample (Frost swaps in a mip chain).
    private var preparedTexture: MTLTexture?
    private var preparedForTransitionID: String?

    public var snapshotSize: SIMD2<Float> {
        guard let snapshot else { return .zero }
        return SIMD2(Float(snapshot.width), Float(snapshot.height))
    }

    public enum RendererError: Error { case noDevice, noLibrary, noFunction(String) }

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RendererError.noDevice }
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw RendererError.noDevice }
        commandQueue = queue
        library = try ShaderLibrary.load(device: device)
        guard let buffer = device.makeBuffer(length: MemoryLayout<TransitionUniforms>.stride,
                                             options: .storageModeShared) else {
            throw RendererError.noDevice
        }
        uniformBuffer = buffer
    }

    // MARK: - Snapshot

    /// Uploads a captured image. The image is converted to a texture and the
    /// CGImage is dropped on return; nothing is ever written to disk.
    public func setSnapshot(_ image: CGImage) throws {
        let loader = MTKTextureLoader(device: device)
        let texture = try loader.newTexture(cgImage: image, options: [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            .SRGB: NSNumber(value: false),
        ])
        snapshot = texture
        preparedTexture = nil
        preparedForTransitionID = nil
    }

    public func setSnapshot(texture: MTLTexture) {
        snapshot = texture
        preparedTexture = nil
        preparedForTransitionID = nil
    }

    public func clearSnapshot() {
        snapshot = nil
        preparedTexture = nil
        preparedForTransitionID = nil
    }

    // MARK: - Drawing

    /// Renders one frame of `transition` at `progress` into `drawable`.
    public func draw(to drawable: CAMetalDrawable, transition: AnyTransition,
                     progress: Double, context: RenderContext) {
        guard let snapshot else { return }
        guard let pipeline = pipeline(for: transition.fragmentFunctionName) else { return }

        if preparedForTransitionID != transition.id || preparedTexture == nil {
            preparedTexture = transition.prepare(snapshot: snapshot, device: device, commandQueue: commandQueue)
            preparedForTransitionID = transition.id
        }
        guard let source = preparedTexture else { return }

        var uniforms = transition.uniforms(progress: progress, context: context)
        uniforms.snapshotSize = context.snapshotSize
        uniforms.outputSize = SIMD2(Float(drawable.texture.width), Float(drawable.texture.height))
        uniforms.time = context.time
        uniforms.reduceTransparency = context.reduceTransparency ? 1 : 0
        uniforms.mipLevels = Float(source.mipmapLevelCount)
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<TransitionUniforms>.stride)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func pipeline(for fragmentName: String) -> MTLRenderPipelineState? {
        if let cached = pipelines[fragmentName] { return cached }
        guard let vertex = library.makeFunction(name: "fullscreenVertex"),
              let fragment = library.makeFunction(name: fragmentName) else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        pipelines[fragmentName] = state
        return state
    }
}

/// Compiles the transition shaders at launch.
///
/// The `.metal` files ship as plain resources (SwiftPM's `.copy` rule), and we
/// concatenate them with `Common.metal` first, then hand the source to Metal's
/// runtime compiler. This takes tens of milliseconds once, and behaves identically
/// whether the app was built by Xcode or by `swift build` + `scripts/build.sh`.
enum ShaderLibrary {
    static func load(device: MTLDevice) throws -> MTLLibrary {
        guard let shadersDir = resourceBundle()?.url(forResource: "Shaders", withExtension: nil) else {
            throw TransitionRenderer.RendererError.noLibrary
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: shadersDir, includingPropertiesForKeys: nil)) ?? []
        let metalFiles = files.filter { $0.pathExtension == "metal" }
            .sorted { a, b in
                // Common.metal defines the shared structs, so it must come first.
                if a.lastPathComponent == "Common.metal" { return true }
                if b.lastPathComponent == "Common.metal" { return false }
                return a.lastPathComponent < b.lastPathComponent
            }
        let source = try metalFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n\n")
        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        return try device.makeLibrary(source: source, options: options)
    }

    /// Locates `Sinkhole_TransitionKit.bundle` without using `Bundle.module`, whose
    /// generated accessor crashes when the bundle isn't in one of its two fixed spots.
    static func resourceBundle() -> Bundle? {
        let name = "Sinkhole_TransitionKit.bundle"
        var candidates: [URL] = []
        if let url = Bundle.main.resourceURL { candidates.append(url) }        // Sinkhole.app/Contents/Resources
        candidates.append(Bundle.main.bundleURL)                                // .app root, or swift build dir
        if let exe = Bundle.main.executableURL { candidates.append(exe.deletingLastPathComponent()) }
        let hostBundle = Bundle(for: TransitionRenderer.self)
        candidates.append(hostBundle.bundleURL)
        if let url = hostBundle.resourceURL { candidates.append(url) }
        // `swift test`: the resource bundle sits next to the .xctest bundle.
        candidates.append(hostBundle.bundleURL.deletingLastPathComponent())
        for dir in candidates {
            if let bundle = Bundle(url: dir.appendingPathComponent(name)) { return bundle }
        }
        return nil
    }
}
