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

    /// Uploads a captured image. The image is drawn into a BGRA8 bitmap of known
    /// layout and copied straight into a texture; the CGImage and the bitmap are
    /// dropped on return. Nothing is ever written to disk.
    ///
    /// Drawing through CoreGraphics rather than MTKTextureLoader means any CGImage
    /// works (ScreenCaptureKit's, NSImage's, tests'), at the cost of one copy.
    public func setSnapshot(_ image: CGImage) throws {
        let width = image.width, height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else {
                throw RendererError.noDevice
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                  width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared   // unified memory on Apple silicon: no blit needed
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RendererError.noDevice }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: bytesPerRow)
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
        guard let commandBuffer = encode(to: drawable.texture, transition: transition,
                                         progress: progress, context: context) else { return }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Fills the drawable with opaque black. Used for the "drained" state between
    /// sleep and pour-out, when there is deliberately no snapshot in memory.
    public func drawBlack(to drawable: CAMetalDrawable) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Offscreen variant, used by tests and the frame-time profiler. Blocks until
    /// the GPU has finished so the texture can be read back.
    public func render(to texture: MTLTexture, transition: AnyTransition,
                       progress: Double, context: RenderContext) {
        guard let commandBuffer = encode(to: texture, transition: transition,
                                         progress: progress, context: context) else { return }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func encode(to target: MTLTexture, transition: AnyTransition,
                        progress: Double, context: RenderContext) -> MTLCommandBuffer? {
        guard let snapshot else { return nil }
        guard let pipeline = pipeline(for: transition.fragmentFunctionName) else { return nil }

        if preparedForTransitionID != transition.id || preparedTexture == nil {
            preparedTexture = transition.prepare(snapshot: snapshot, device: device, commandQueue: commandQueue)
            preparedForTransitionID = transition.id
        }
        guard let source = preparedTexture else { return nil }

        var uniforms = transition.uniforms(progress: progress, context: context)
        uniforms.snapshotSize = context.snapshotSize
        uniforms.outputSize = SIMD2(Float(target.width), Float(target.height))
        uniforms.time = context.time
        uniforms.reduceTransparency = context.reduceTransparency ? 1 : 0
        uniforms.mipLevels = Float(source.mipmapLevelCount)
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<TransitionUniforms>.stride)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return commandBuffer
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

    /// Locates `Shut_TransitionKit.bundle` without using `Bundle.module`, whose
    /// generated accessor crashes when the bundle isn't in one of its two fixed spots.
    static func resourceBundle() -> Bundle? {
        let name = "Shut_TransitionKit.bundle"
        var candidates: [URL] = []
        if let url = Bundle.main.resourceURL { candidates.append(url) }        // Shut.app/Contents/Resources
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
