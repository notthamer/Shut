import Foundation
import Metal

/// A style drawn through the panel mesh pipeline. Conformers implement only the
/// math (`frame`); the pipeline, blending and mip chain are shared.
public protocol PanelTransition: Transition {
    func frame(progress: Double, context: RenderContext) -> PanelFrame
}

public extension PanelTransition {
    static var vertexFunctionName: String { "panelVertex" }
    static var fragmentFunctionName: String { "panelFragment" }
    static var usesPanelMesh: Bool { true }

    func uniforms(progress: Double, context: RenderContext) -> TransitionUniforms {
        frame(progress: progress, context: context).uniforms(progress: progress)
    }

    func prepare(snapshot: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) -> MTLTexture {
        MipChain.build(from: snapshot, device: device, commandQueue: commandQueue)
    }
}

/// Builds the mip chain the defocus shaders blur from. Runs once per snapshot,
/// so a 120 Hz frame never pays for the blur pyramid. Shared by Frost and the
/// panel styles.
public enum MipChain {
    public static func build(from snapshot: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: snapshot.pixelFormat,
                                                                  width: snapshot.width, height: snapshot.height,
                                                                  mipmapped: true)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .private
        guard let mipped = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return snapshot }
        blit.copy(from: snapshot, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: snapshot.width, height: snapshot.height, depth: 1),
                  to: mipped, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.generateMipmaps(for: mipped)
        blit.endEncoding()
        commandBuffer.commit()
        return mipped
    }
}
