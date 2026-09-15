import AppKit
import Metal

/// Renders any transition at its `thumbnailProgress` over a backdrop, for the
/// style gallery. Owns a private renderer so it never touches the overlay's or
/// the preview's snapshot. Results are cached by (style id, params, progress).
@MainActor
public final class TransitionThumbnailRenderer {
    public static let size = (width: 320, height: 200)

    private let renderer: TransitionRenderer
    private let target: MTLTexture
    private var backdrop: CGImage
    private var cache: [Key: CGImage] = [:]
    private var backdropIsPlaceholder = true

    private struct Key: Hashable { let id: String; let params: Data; let progress: Double; let backdrop: Int }
    private var backdropGeneration = 0

    public enum ThumbnailError: Error { case noTarget, noBackdrop }

    public init() throws {
        renderer = try TransitionRenderer()
        guard let target = TextureReadback.makeRenderTarget(device: renderer.device, width: Self.size.width, height: Self.size.height) else {
            throw ThumbnailError.noTarget
        }
        self.target = target
        guard let placeholder = PlaceholderDesktop.image() else { throw ThumbnailError.noBackdrop }
        backdrop = placeholder
        try renderer.setSnapshot(placeholder)
    }

    /// Swap the desktop the thumbnails are drawn over (the real one, once allowed).
    public func setBackdrop(_ image: CGImage, isPlaceholder: Bool) throws {
        backdrop = image
        backdropIsPlaceholder = isPlaceholder
        try renderer.setSnapshot(image)
        backdropGeneration += 1
        cache.removeAll()
    }

    public var usesPlaceholder: Bool { backdropIsPlaceholder }

    public func image(for transition: AnyTransition, progress: Double? = nil) -> CGImage? {
        let p = progress ?? transition.thumbnailProgress
        let key = Key(id: transition.id, params: transition.paramsJSON ?? Data(), progress: p, backdrop: backdropGeneration)
        if let cached = cache[key] { return cached }

        let size = renderer.snapshotSize
        let context = RenderContext(snapshotSize: size,
                                    sinkPoint: SIMD2(size.x / 2, size.y * 0.046),
                                    notchSize: SIMD2(size.x * 0.11, size.y * 0.046),
                                    usesVirtualNotch: false, scale: 1, hingeTravelDegrees: 45)
        renderer.render(to: target, transition: transition, progress: p, context: context)
        guard var image = TextureReadback.makeImage(from: target) else { return nil }
        if transition.isTransparent { image = composite(image, over: backdrop) ?? image }
        if cache.count > 64 { cache.removeAll() }
        cache[key] = image
        return image
    }

    public func invalidate(id: String) {
        cache = cache.filter { $0.key.id != id }
    }

    public func invalidateAll() { cache.removeAll() }

    private func composite(_ image: CGImage, over backdrop: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        context.draw(backdrop, in: rect)
        // Metal's row 0 is the top; CGContext's is the bottom, so flip the render.
        context.translateBy(x: 0, y: CGFloat(h)); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
