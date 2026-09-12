// Draws the Shut app icon from code: a dark rounded square, a lid tipping shut
// over a lit screen with a notch, the screen draining into it. Run with
// scripts/make-icon.sh, which recuts every size into the asset catalogue.
import AppKit
import CoreGraphics

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
    fatalError("no context")
}

// macOS icon grid: the rounded square occupies ~82% of the canvas.
let inset = size * 0.09
let square = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let radius = square.width * 0.225

// Background: near-black with a faint top-left light.
ctx.addPath(CGPath(roundedRect: square, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [CGColor(gray: 0.17, alpha: 1), CGColor(gray: 0.09, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: square.minX, y: square.maxY), end: CGPoint(x: square.maxX, y: square.minY), options: [])

// The base of the laptop: a thin light bar near the bottom.
let baseY = square.minY + square.height * 0.26
let baseRect = CGRect(x: square.minX + square.width * 0.16, y: baseY, width: square.width * 0.68, height: square.height * 0.035)
ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
ctx.addPath(CGPath(roundedRect: baseRect, cornerWidth: baseRect.height / 2, cornerHeight: baseRect.height / 2, transform: nil)); ctx.fillPath()

// The lid: a keystone tipping toward the viewer, hinged at the base.
let hingeLeft = CGPoint(x: baseRect.minX + baseRect.width * 0.03, y: baseRect.maxY)
let hingeRight = CGPoint(x: baseRect.maxX - baseRect.width * 0.03, y: baseRect.maxY)
let topInset = square.width * 0.11
let lidHeight = square.height * 0.40
let topLeft = CGPoint(x: hingeLeft.x + topInset, y: hingeLeft.y + lidHeight)
let topRight = CGPoint(x: hingeRight.x - topInset, y: hingeRight.y + lidHeight)

let lid = CGMutablePath()
lid.move(to: hingeLeft); lid.addLine(to: hingeRight); lid.addLine(to: topRight); lid.addLine(to: topLeft); lid.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.55))
ctx.setFillColor(CGColor(gray: 0.86, alpha: 1))
ctx.addPath(lid); ctx.fillPath()
ctx.restoreGState()

// The screen inside the lid: a gradient that is brightest at the hinge and drains
// toward the notch at the top, with a swirl of thin arcs.
ctx.saveGState()
let screen = CGMutablePath()
let m = square.width * 0.02
screen.move(to: CGPoint(x: hingeLeft.x + m, y: hingeLeft.y + m))
screen.addLine(to: CGPoint(x: hingeRight.x - m, y: hingeRight.y + m))
screen.addLine(to: CGPoint(x: topRight.x - m * 0.7, y: topRight.y - m))
screen.addLine(to: CGPoint(x: topLeft.x + m * 0.7, y: topLeft.y - m))
screen.closeSubpath()
ctx.addPath(screen); ctx.clip()
let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                     colors: [CGColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1), CGColor(red: 0.75, green: 0.30, blue: 0.85, alpha: 1), CGColor(red: 0.08, green: 0.06, blue: 0.12, alpha: 1)] as CFArray,
                     locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: square.midX, y: hingeLeft.y), end: CGPoint(x: square.midX, y: topLeft.y), options: [])
// Swirl arcs converging on the notch.
let sink = CGPoint(x: square.midX, y: topLeft.y - m * 1.2)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
for i in 0..<7 {
    let r = square.width * (0.09 + Double(i) * 0.055)
    ctx.setLineWidth(size * 0.006)
    ctx.addArc(center: sink, radius: r, startAngle: .pi * 1.08, endAngle: .pi * 1.92 + Double(i) * 0.06, clockwise: false)
    ctx.strokePath()
}
ctx.restoreGState()

// The notch: a black pill hanging from the top edge of the lid.
let notchW = square.width * 0.16, notchH = square.height * 0.045
let notch = CGRect(x: square.midX - notchW / 2, y: topLeft.y - m - notchH, width: notchW, height: notchH)
ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
ctx.addPath(CGPath(roundedRect: notch.insetBy(dx: 0, dy: -notchH), cornerWidth: notchH * 0.5, cornerHeight: notchH * 0.5, transform: nil))
ctx.saveGState(); ctx.clip(to: notch.insetBy(dx: -2, dy: 0).offsetBy(dx: 0, dy: -notchH * 0.5).insetBy(dx: 0, dy: -notchH)); ctx.fillPath(); ctx.restoreGState()
ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
ctx.addPath(CGPath(roundedRect: notch, cornerWidth: notchH * 0.45, cornerHeight: notchH * 0.45, transform: nil)); ctx.fillPath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
