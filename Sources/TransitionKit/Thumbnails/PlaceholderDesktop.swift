import AppKit
import CoreGraphics

/// A drawn stand-in for the desktop: a soft wallpaper gradient, a menu bar strip,
/// and two windows with text lines. Nothing is read from the screen, so previews
/// and thumbnails work before Screen Recording is granted.
public enum PlaceholderDesktop {
    public static let defaultSize = CGSize(width: 1024, height: 640)

    public static func image(size: CGSize = defaultSize, notchWidth: CGFloat = 112, dark: Bool = false) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }

        // Wallpaper: a diagonal gradient with a soft highlight, like a stock macOS wallpaper.
        let colors: [CGColor] = dark
            ? [CGColor(red: 0.12, green: 0.16, blue: 0.36, alpha: 1), CGColor(red: 0.42, green: 0.18, blue: 0.48, alpha: 1), CGColor(red: 0.86, green: 0.42, blue: 0.30, alpha: 1)]
            : [CGColor(red: 0.55, green: 0.72, blue: 0.95, alpha: 1), CGColor(red: 0.80, green: 0.66, blue: 0.92, alpha: 1), CGColor(red: 0.99, green: 0.80, blue: 0.62, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: [0, 0.55, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        }
        if let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1]) {
            context.drawRadialGradient(glow, startCenter: CGPoint(x: size.width * 0.7, y: size.height * 0.75), startRadius: 0,
                                       endCenter: CGPoint(x: size.width * 0.7, y: size.height * 0.75), endRadius: size.width * 0.5, options: [])
        }

        // Menu bar strip with a notch.
        let barHeight = size.height * 0.046
        context.setFillColor(CGColor(gray: dark ? 0.08 : 0.94, alpha: 0.55))
        context.fill(CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        let notch = CGRect(x: (size.width - notchWidth) / 2, y: size.height - barHeight, width: notchWidth, height: barHeight)
        context.addPath(CGPath(roundedRect: notch.insetBy(dx: 0, dy: -barHeight * 0.5).offsetBy(dx: 0, dy: barHeight * 0.5), cornerWidth: barHeight * 0.45, cornerHeight: barHeight * 0.45, transform: nil))
        context.fillPath()
        // Menu bar glyphs
        context.setFillColor(CGColor(gray: dark ? 0.9 : 0.15, alpha: 0.8))
        for x in stride(from: size.width * 0.02, through: size.width * 0.28, by: size.width * 0.052) {
            context.fill(CGRect(x: x, y: size.height - barHeight * 0.68, width: size.width * 0.03, height: barHeight * 0.3))
        }
        for x in stride(from: size.width * 0.86, through: size.width * 0.97, by: size.width * 0.035) {
            context.fill(CGRect(x: x, y: size.height - barHeight * 0.68, width: size.width * 0.02, height: barHeight * 0.3))
        }

        // Two windows.
        drawWindow(context, CGRect(x: size.width * 0.07, y: size.height * 0.12, width: size.width * 0.52, height: size.height * 0.66), dark: dark, lines: 9)
        drawWindow(context, CGRect(x: size.width * 0.55, y: size.height * 0.30, width: size.width * 0.38, height: size.height * 0.5), dark: dark, lines: 6)

        // Dock.
        let dockWidth = size.width * 0.42, dockHeight = size.height * 0.07
        let dock = CGRect(x: (size.width - dockWidth) / 2, y: size.height * 0.018, width: dockWidth, height: dockHeight)
        context.setFillColor(CGColor(gray: dark ? 0.2 : 0.95, alpha: 0.6))
        context.addPath(CGPath(roundedRect: dock, cornerWidth: dockHeight * 0.3, cornerHeight: dockHeight * 0.3, transform: nil)); context.fillPath()
        let tile = dockHeight * 0.68
        var x = dock.minX + dockHeight * 0.25
        let tints: [CGColor] = [CGColor(red: 0.3, green: 0.6, blue: 1, alpha: 1), CGColor(red: 1, green: 0.5, blue: 0.3, alpha: 1), CGColor(red: 0.5, green: 0.85, blue: 0.5, alpha: 1), CGColor(red: 0.9, green: 0.35, blue: 0.5, alpha: 1), CGColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1), CGColor(red: 0.6, green: 0.5, blue: 0.95, alpha: 1)]
        for tint in tints {
            context.setFillColor(tint)
            context.addPath(CGPath(roundedRect: CGRect(x: x, y: dock.midY - tile / 2, width: tile, height: tile), cornerWidth: tile * 0.25, cornerHeight: tile * 0.25, transform: nil)); context.fillPath()
            x += tile * 1.35
        }
        return context.makeImage()
    }

    private static func drawWindow(_ c: CGContext, _ r: CGRect, dark: Bool, lines: Int) {
        c.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
        c.setFillColor(CGColor(gray: dark ? 0.16 : 0.98, alpha: 1))
        c.addPath(CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil)); c.fillPath()
        c.setShadow(offset: .zero, blur: 0, color: nil)
        // title bar + traffic lights
        c.setFillColor(CGColor(gray: dark ? 0.22 : 0.92, alpha: 1))
        c.fill(CGRect(x: r.minX, y: r.maxY - 28, width: r.width, height: 28))
        for (i, color) in [CGColor(red: 1, green: 0.38, blue: 0.35, alpha: 1), CGColor(red: 1, green: 0.74, blue: 0.2, alpha: 1), CGColor(red: 0.3, green: 0.8, blue: 0.35, alpha: 1)].enumerated() {
            c.setFillColor(color)
            c.fillEllipse(in: CGRect(x: r.minX + 12 + CGFloat(i) * 16, y: r.maxY - 19, width: 10, height: 10))
        }
        // text lines
        c.setFillColor(CGColor(gray: dark ? 0.45 : 0.72, alpha: 1))
        let lineHeight = (r.height - 60) / CGFloat(lines)
        for i in 0..<lines {
            let width = r.width * (0.35 + 0.5 * abs(sin(Double(i) * 1.3)))
            c.fill(CGRect(x: r.minX + 18, y: r.maxY - 48 - CGFloat(i) * lineHeight, width: width, height: max(lineHeight * 0.35, 3)))
        }
    }
}
