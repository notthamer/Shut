#!/usr/bin/env swift
// Builds the app icon and the in-app mark from the designed "S" glyph, set on a
// tile of light liquid glass so the Dock icon matches the panels.
//
//   swift scripts/make-glass-icon.swift
//
// Reads the mark from App/mark-source.png (a black glyph on transparency; its
// alpha is the mask), fills it with the Spectrum Marquee on a Void Black macOS
// squircle with a soft shadow, then writes every icon size, rebuilds
// App/Shut.icns with iconutil, and writes Sources/ShutApp/Resources/logo.png.
// Run it again whenever the glyph changes.

import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
let sourceURL = iconset.appendingPathComponent("icon_512x512@2x.png")
let logoURL = root.appendingPathComponent("Sources/ShutApp/Resources/logo.png")
let icnsURL = root.appendingPathComponent("App/Shut.icns")
let sourceBackupURL = root.appendingPathComponent("App/mark-source.png")

// MARK: Recover the glyph as an ink mask

guard let source = NSImage(contentsOf: sourceBackupURL),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot read the source mark at \(sourceURL.path)")
}
let w = cg.width, h = cg.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let rgb = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

// The mark ships as a clean black glyph on transparency; its alpha is the mask.
var mask = [UInt8](repeating: 0, count: w * h * 4)
var minX = w, maxX = 0, minY = h, maxY = 0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let alpha = pixels[i + 3]
        mask[i + 3] = alpha
        if alpha > 110 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    }
}
guard maxX > minX, maxY > minY,
      let maskCtx = CGContext(data: &mask, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let fullMask = maskCtx.makeImage(),
      let glyph = fullMask.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)) else {
    fatalError("no glyph found in the source mark")
}

// MARK: Draw one glass tile at a given pixel size

func squircle(in rect: CGRect) -> CGPath {
    // macOS icon shape: a rounded square with ~22.4 % corner radius.
    CGPath(roundedRect: rect, cornerWidth: rect.width * 0.224, cornerHeight: rect.height * 0.224, transform: nil)
}

func render(pixels size: Int) -> CGImage {
    let s = CGFloat(size)
    guard let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
    c.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // macOS icons leave a margin so the shadow has room: the tile is 80 % of the canvas.
    let tile = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = squircle(in: tile)

    // Soft shadow under the tile.
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.06, color: CGColor(gray: 0, alpha: 0.28))
    c.addPath(path); c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fillPath()
    c.restoreGState()

    // The stage: a Void Black tile with a faint inner edge.
    c.saveGState()
    c.addPath(path); c.setFillColor(CGColor(red: 0.008, green: 0.008, blue: 0.016, alpha: 1)); c.fillPath()
    c.addPath(squircle(in: tile.insetBy(dx: s * 0.004, dy: s * 0.004)))
    c.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); c.setLineWidth(max(s * 0.004, 1)); c.strokePath()
    c.restoreGState()

    // The mark, filled with the Spectrum Marquee, centred, at 54 % of the tile.
    let glyphAspect = CGFloat(glyph.width) / CGFloat(glyph.height)
    var markSize = CGSize(width: tile.width * 0.54, height: tile.width * 0.54 / glyphAspect)
    if markSize.height > tile.height * 0.54 { markSize = CGSize(width: tile.height * 0.54 * glyphAspect, height: tile.height * 0.54) }
    let markRect = CGRect(x: tile.midX - markSize.width / 2, y: tile.midY - markSize.height / 2, width: markSize.width, height: markSize.height)
    c.saveGState()
    c.clip(to: markRect, mask: glyph)
    if let spectrum = CGGradient(colorsSpace: rgb, colors: [
        CGColor(red: 0.012, green: 0.345, blue: 0.969, alpha: 1),   // blue
        CGColor(red: 0.882, green: 0.882, blue: 0.996, alpha: 1),   // lavender
        CGColor(red: 1.0, green: 0.690, blue: 0.020, alpha: 1),     // amber
        CGColor(red: 0.980, green: 0.239, blue: 0.114, alpha: 1),   // red
        CGColor(red: 0.992, green: 0.008, blue: 0.961, alpha: 1),   // magenta
    ] as CFArray, locations: [0, 0.275, 0.572, 0.84, 1]) {
        // Left to right with a slight rise, so the sweep reads as motion.
        c.drawLinearGradient(spectrum, start: CGPoint(x: markRect.minX, y: markRect.minY + markRect.height * 0.3),
                             end: CGPoint(x: markRect.maxX, y: markRect.maxY - markRect.height * 0.3), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    c.restoreGState()

    return c.makeImage()!
}

func write(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "icon", code: 1) }
    try data.write(to: url)
}

// MARK: Write every size

let sizes: [(String, Int)] = [
    ("icon_16x16@1x", 16), ("icon_16x16@2x", 32), ("icon_32x32@1x", 32), ("icon_32x32@2x", 64),
    ("icon_128x128@1x", 128), ("icon_128x128@2x", 256), ("icon_256x256@1x", 256), ("icon_256x256@2x", 512),
    ("icon_512x512@1x", 512), ("icon_512x512@2x", 1024),
]
let master = render(pixels: 1024)
for (name, px) in sizes {
    // Downsample the master rather than re-rendering: identical hairlines at every size.
    guard let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                            space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
    c.interpolationQuality = .high
    c.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    try write(c.makeImage()!, to: iconset.appendingPathComponent("\(name).png"))
}
try write(master, to: logoURL)

// iconutil wants a folder named *.iconset with the same file names.
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Shut.iconset")
try? FileManager.default.removeItem(at: tmp)
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
for (name, _) in sizes {
    try FileManager.default.copyItem(at: iconset.appendingPathComponent("\(name).png"), to: tmp.appendingPathComponent("\(name).png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", tmp.path, "-o", icnsURL.path]
try task.run(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote \(sizes.count) sizes, \(icnsURL.lastPathComponent) and \(logoURL.lastPathComponent)" : "iconutil failed")
