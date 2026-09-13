import AppKit

/// Images that ship inside the ShutApp package bundle, so they are available
/// whether the app was built by Xcode or by scripts/build.sh.
enum AppAssets {
    static let logo: NSImage? = {
        guard let url = resourceBundle()?.url(forResource: "Resources/logo", withExtension: "png")
                ?? resourceBundle()?.url(forResource: "logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// The status-item icon: the logo's glyph as a monochrome template so it
    /// follows the menu bar's light/dark appearance. The logo's white rounded
    /// square becomes transparent; the black S and its streaks become the mask.
    static let menuBarIcon: NSImage? = {
        guard let logo, let cg = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var mask = [UInt8](repeating: 0, count: w * h * 4)
        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4
            let luma = 0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])
            let alpha = Double(pixels[i + 3]) / 255
            // A steep ramp keeps the strokes and streaks and drops the glass
            // tile's faint tint, so the template glyph is clean.
            let raw = (1 - luma / 255) * alpha * 255
            var ink = UInt8(min(max((raw - 90) * 2.2, 0), 255))
            // The logo is the mark on a glass tile; drop everything in the outer
            // band so only the glyph and its streaks remain.
            let border = Double(min(w, h)) * 0.2
            let inBorder = Double(x) < border || Double(x) > Double(w) - border || Double(y) < border || Double(y) > Double(h) - border
            if inBorder { ink = 0 }
            mask[i + 3] = ink
            if ink > 110 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        } }
        guard maxX > minX, maxY > minY,
              let maskCtx = CGContext(data: &mask, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let full = maskCtx.makeImage() else { return nil }
        // Crop to the glyph with a little air, and keep it square so it centres.
        let side = max(maxX - minX, maxY - minY) + 8
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let crop = CGRect(x: max(cx - side / 2, 0), y: max(cy - side / 2, 0), width: min(side, w), height: min(side, h))
        guard let cropped = full.cropping(to: crop) else { return nil }
        let image = NSImage(cgImage: cropped, size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }()

    private static func resourceBundle() -> Bundle? {
        let name = "Shut_ShutApp.bundle"
        var candidates: [URL] = []
        if let url = Bundle.main.resourceURL { candidates.append(url) }
        candidates.append(Bundle.main.bundleURL)
        if let exe = Bundle.main.executableURL { candidates.append(exe.deletingLastPathComponent()) }
        let host = Bundle(for: PopoverModel.self)
        candidates.append(host.bundleURL)
        if let url = host.resourceURL { candidates.append(url) }
        candidates.append(host.bundleURL.deletingLastPathComponent())
        for dir in candidates {
            if let bundle = Bundle(url: dir.appendingPathComponent(name)) { return bundle }
        }
        return nil
    }
}
