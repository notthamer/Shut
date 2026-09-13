#!/usr/bin/env swift
// Builds the app icon and the in-app mark from the designed "S" glyph, set on a
// tile of light liquid glass so the Dock icon matches the panels.
//
//   swift scripts/make-glass-icon.swift
//
// Reads the glyph from App/mark-source.png (the mark's ink is recovered from
// its luminance, the way the menu bar glyph is), draws it in Pure Black on a
// Paper White macOS squircle with a Silver edge and a soft shadow, then writes
// every icon size, rebuilds
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

guard let source = NSImage(contentsOf: FileManager.default.fileExists(atPath: sourceBackupURL.path) ? sourceBackupURL : sourceURL),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot read the source mark at \(sourceURL.path)")
}
// Keep the original artwork next to the project so the script is repeatable
// after it has overwritten the iconset.
if !FileManager.default.fileExists(atPath: sourceBackupURL.path),
   let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
    try? data.write(to: sourceBackupURL)
}

let w = cg.width, h = cg.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let rgb = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

var mask = [UInt8](repeating: 0, count: w * h * 4)
var minX = w, maxX = 0, minY = h, maxY = 0
let border = Double(min(w, h)) * 0.2   // the source bakes a white tile and shadow; ignore its outer band
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let luma = 0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])
        let alpha = Double(pixels[i + 3]) / 255
        // Sharpen: the source is anti-aliased with a soft halo around the S.
        // A steep ramp keeps the strokes and the motion streaks and drops the halo.
        let raw = (1 - luma / 255) * alpha * 255
        var ink = UInt8(min(max((raw - 90) * 2.2, 0), 255))
        let inBorder = Double(x) < border || Double(x) > Double(w) - border || Double(y) < border || Double(y) > Double(h) - border
        if inBorder { ink = 0 }
        mask[i + 3] = ink
        if ink > 110 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
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

    // Paper: a flat Paper White tile with a one-point Silver edge. No sheen.
    c.saveGState()
    c.addPath(path); c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); c.fillPath()
    c.addPath(path)
    c.setStrokeColor(CGColor(red: 0.776, green: 0.776, blue: 0.776, alpha: 1)); c.setLineWidth(max(s * 0.004, 1)); c.strokePath()
    c.restoreGState()

    // The mark, in ink, centred, at 52 % of the tile.
    let glyphAspect = CGFloat(glyph.width) / CGFloat(glyph.height)
    var markSize = CGSize(width: tile.width * 0.52, height: tile.width * 0.52 / glyphAspect)
    if markSize.height > tile.height * 0.52 { markSize = CGSize(width: tile.height * 0.52 * glyphAspect, height: tile.height * 0.52) }
    let markRect = CGRect(x: tile.midX - markSize.width / 2, y: tile.midY - markSize.height / 2, width: markSize.width, height: markSize.height)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.012, color: CGColor(gray: 0, alpha: 0.18))
    c.clip(to: markRect, mask: glyph)
    c.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))   // Pure Black
    c.fill(markRect)
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
