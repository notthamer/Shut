import CoreGraphics
import Metal

/// Reads a rendered texture back into a CGImage, and makes readable targets.
public enum TextureReadback {
    public static func makeRenderTarget(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: TransitionRenderer.pixelFormat,
                                                                  width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    /// Premultiplied BGRA8 → CGImage in sRGB.
    public static func makeImage(from texture: MTLTexture) -> CGImage? {
        let w = texture.width, h = texture.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        texture.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
