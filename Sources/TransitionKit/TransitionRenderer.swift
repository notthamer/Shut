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
    /// sRGB everywhere: the GPU decodes on sample and re-encodes on store, so
    /// dimming, washout, blending and mip averaging all happen in linear light and
    /// a fade reaches the same black the overlay sits on.
    public static let pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
    /// Cells per side of the panel mesh. Enough for the fold's bow to look smooth.
    static let gridResolution = 48

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    private struct PipelineKey: Hashable { let vertex: String; let fragment: String; let blended: Bool }
    private var pipelines: [PipelineKey: MTLRenderPipelineState] = [:]
    private let uniformBuffer: MTLBuffer
    private let gridBuffer: MTLBuffer
    private let gridVertexCount: Int
    /// Bound when a transition needs no snapshot, so the pipeline always has a texture.
    private let placeholderTexture: MTLTexture

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

    /// Whether the shader sources ship with this build; see `ShaderLibrary.sourcesArePresent`.
    public static var shaderSourcesArePresent: Bool { ShaderLibrary.sourcesArePresent }

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

        let grid = Self.makeGrid(resolution: Self.gridResolution)
        guard let gridBuffer = device.makeBuffer(bytes: grid, length: grid.count * MemoryLayout<SIMD2<Float>>.stride,
                                                 options: .storageModeShared) else {
            throw RendererError.noDevice
        }
        self.gridBuffer = gridBuffer
        gridVertexCount = grid.count

        let placeholderDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat,
                                                                             width: 1, height: 1, mipmapped: false)
        placeholderDescriptor.usage = [.shaderRead]
        placeholderDescriptor.storageMode = .shared
        guard let placeholder = device.makeTexture(descriptor: placeholderDescriptor) else { throw RendererError.noDevice }
        var black: [UInt8] = [0, 0, 0, 255]
        placeholder.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)
        placeholderTexture = placeholder
    }

    /// Two triangles per cell, UVs in 0...1 with y down, matching the snapshot.
    static func makeGrid(resolution: Int) -> [SIMD2<Float>] {
        var vertices: [SIMD2<Float>] = []
        vertices.reserveCapacity(resolution * resolution * 6)
        let step = 1 / Float(resolution)
        for row in 0..<resolution {
            for column in 0..<resolution {
                let x0 = Float(column) * step, x1 = x0 + step
                let y0 = Float(row) * step, y1 = y0 + step
                vertices += [SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x0, y1),
                             SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1)]
            }
        }
        return vertices
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
        // Draw into sRGB explicitly so a Display P3 capture is converted, not reinterpreted.
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: colorSpace, bitmapInfo: bitmapInfo) else {
                throw RendererError.noDevice
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat,
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
    /// Returns false if nothing was encoded (no snapshot, no pipeline).
    @discardableResult
    public func draw(to drawable: CAMetalDrawable, transition: AnyTransition,
                     progress: Double, context: RenderContext,
                     onComplete: (@Sendable () -> Void)? = nil) -> Bool {
        guard let commandBuffer = encode(to: drawable.texture, transition: transition,
                                         progress: progress, context: context) else { return false }
        if let onComplete { commandBuffer.addCompletedHandler { _ in onComplete() } }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }

    /// Fills the drawable with opaque black. Used for the "drained" state between
    /// sleep and pour-out, when there is deliberately no snapshot in memory.
    public func drawBlack(to drawable: CAMetalDrawable, onComplete: (@Sendable () -> Void)? = nil) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { onComplete?(); return }
        encoder.endEncoding()
        if let onComplete { commandBuffer.addCompletedHandler { _ in onComplete() } }
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
        guard let pipeline = pipeline(for: transition) else { return nil }

        // Snapshot styles sample their (possibly mip-mapped) capture; mask styles
        // draw over the live desktop and get a 1×1 black stand-in.
        let source: MTLTexture
        if transition.needsSnapshot {
            guard let snapshot else { return nil }
            if preparedForTransitionID != transition.id || preparedTexture == nil {
                preparedTexture = transition.prepare(snapshot: snapshot, device: device, commandQueue: commandQueue)
                preparedForTransitionID = transition.id
            }
            guard let prepared = preparedTexture else { return nil }
            source = prepared
        } else {
            source = placeholderTexture
        }

        var uniforms = transition.uniforms(progress: progress, context: context)
        uniforms.snapshotSize = context.snapshotSize
        uniforms.outputSize = SIMD2(Float(target.width), Float(target.height))
        uniforms.time = context.time
        uniforms.reduceTransparency = context.reduceTransparency ? 1 : 0
        uniforms.mipLevels = Float(source.mipmapLevelCount)
        uniforms.aspect = Float(target.width) / Float(max(target.height, 1))
        // Stop three levels short of the smallest mip so a full blur stays legible.
        uniforms.maxLOD = max(Float(source.mipmapLevelCount - 1) - 3, 0)
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<TransitionUniforms>.stride)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0,
                                                             alpha: transition.isTransparent ? 0 : 1)
        pass.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        if transition.usesPanelMesh {
            encoder.setVertexBuffer(gridBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridVertexCount)
        } else {
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
        return commandBuffer
    }

    private func pipeline(for transition: AnyTransition) -> MTLRenderPipelineState? {
        let key = PipelineKey(vertex: transition.vertexFunctionName,
                              fragment: transition.fragmentFunctionName,
                              blended: transition.usesPanelMesh)
        if let cached = pipelines[key] { return cached }
        guard let vertex = library.makeFunction(name: key.vertex),
              let fragment = library.makeFunction(name: key.fragment) else {
            NSLog("TransitionKit: missing shader function \(key.vertex)/\(key.fragment)")
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
        if key.blended {
            // Premultiplied source-over: the panel blends onto the cleared backdrop,
            // which is what lets rounded corners and the mask styles resolve cleanly.
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        do {
            let state = try device.makeRenderPipelineState(descriptor: descriptor)
            pipelines[key] = state
            return state
        } catch {
            NSLog("TransitionKit: pipeline \(key.vertex)/\(key.fragment) failed: \(error)")
            return nil
        }
    }
}

/// Compiles the transition shaders at launch.
///
/// The `.metal` files ship as plain resources (SwiftPM's `.copy` rule), and we
/// concatenate them with `Common.metal` first, then hand the source to Metal's
/// runtime compiler. This takes tens of milliseconds once, and behaves identically
/// whether the app was built by Xcode or by `swift build` + `scripts/build.sh`.
enum ShaderLibrary {
    /// True when the `.metal` sources can be found. `shut --self-check` asks this of a
    /// packaged app, where a missing bundle would otherwise only show at the first close.
    static var sourcesArePresent: Bool {
        guard let dir = resourceBundle()?.url(forResource: "Shaders", withExtension: nil) else { return false }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.lastPathComponent == "Common.metal" }
    }

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
