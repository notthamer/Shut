import AppKit

/// Images that ship inside the ShutApp package bundle, so they are available
/// whether the app was built by Xcode or by scripts/build.sh.
enum AppAssets {
    static let logo: NSImage? = {
        guard let url = resourceBundle()?.url(forResource: "Resources/logo", withExtension: "png")
                ?? resourceBundle()?.url(forResource: "logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// The Stay awake eyes: six 16 × 12 frames cut from one sheet (see `AwakeEyes`), each
    /// as the list of its inked pixels. Kept as pixels rather than images because SwiftUI
    /// smooths a scaled template image whatever `interpolation` says; squares drawn one
    /// by one stay squares at any size.
    static let eyesFrameWidth = 16
    static let eyes: [[CGPoint]] = {
        guard let url = resourceBundle()?.url(forResource: "Resources/eyes", withExtension: "png")
                ?? resourceBundle()?.url(forResource: "eyes", withExtension: "png"),
              let sheet = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let w = sheet.width, h = sheet.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(sheet, in: CGRect(x: 0, y: 0, width: w, height: h))
        let side = eyesFrameWidth
        return stride(from: 0, to: w, by: side).map { left in
            var inked: [CGPoint] = []
            for y in 0..<h { for x in 0..<side where pixels[(y * w + left + x) * 4 + 3] > 127 {
                inked.append(CGPoint(x: x, y: y))
            } }
            return inked
        }
    }()

    /// The clean mark (a black glyph on transparency), for the menu bar.
    static let mark: NSImage? = {
        guard let url = resourceBundle()?.url(forResource: "Resources/mark", withExtension: "png")
                ?? resourceBundle()?.url(forResource: "mark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// The mark cropped to its glyph (the source has generous empty margins), so
    /// a 26-pt mark is 26 pt of glyph.
    static let markCropped: NSImage? = {
        guard let mark, let cg = mark.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h { for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 40 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX > minX, maxY > minY else { return nil }
        let side = max(maxX - minX, maxY - minY) + 4
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let crop = CGRect(x: max(cx - side / 2, 0), y: max(cy - side / 2, 0), width: min(side, w), height: min(side, h))
        guard let cropped = cg.cropping(to: crop) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: crop.width, height: crop.height))
    }()

    /// The status-item icon: the mark's alpha as a monochrome template, cropped
    /// to the glyph with a little air, so it follows the menu bar's appearance.
    static let menuBarIcon: NSImage? = {
        guard let mark, let cg = mark.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4
            pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0   // template: alpha only
            if pixels[i + 3] > 110 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        } }
        guard maxX > minX, maxY > minY,
              let maskCtx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let full = maskCtx.makeImage() else { return nil }
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
