import AppKit
import SwiftUI

// Colour bridging shared by rows.

extension Color {
    init(_ c: TunerColor) {
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}

extension TunerColor {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: Double(ns.redComponent), green: Double(ns.greenComponent),
                  blue: Double(ns.blueComponent), alpha: Double(ns.alphaComponent))
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
