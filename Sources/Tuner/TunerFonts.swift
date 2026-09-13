import AppKit
import CoreText
import SwiftUI

/// Apfel Grotezk (Collletttivo, SIL Open Font License 1.1): the round, airy
/// grotesk every label in Shut is set in. The four weights ship inside the
/// Tuner resource bundle and are registered for this process the first time a
/// font is asked for, so nothing has to be installed. Numbers stay in the
/// system's monospaced face, which Apfel does not offer.
public enum TunerFonts {
    public static let family = "Apfel Grotezk"

    /// PostScript names by weight. Apfel has no 600, so semibold rounds up to
    /// Fett (700); heavier weights get Satt (900).
    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return "ApfelGrotezk-Regular"
        case .medium: return "ApfelGrotezk-Mittel"
        case .semibold, .bold: return "ApfelGrotezk-Fett"
        default: return "ApfelGrotezk-Satt"
        }
    }

    /// True once the faces are available to CoreText. Registration is
    /// attempted once; a missing bundle falls back to the system font.
    public static let isAvailable: Bool = register()

    @discardableResult
    static func register() -> Bool {
        if NSFont(name: "ApfelGrotezk-Regular", size: 12) != nil { return true }
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "otf", subdirectory: "Fonts"), !urls.isEmpty else {
            return false
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: "ApfelGrotezk-Regular", size: 12) != nil
    }

    /// A text face at a size and weight, with the system font as the fallback.
    public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        isAvailable ? Font.custom(postScriptName(for: weight), size: size) : Font.system(size: size, weight: weight)
    }

    /// The AppKit counterpart, for places that draw with NSFont.
    public static func nsFont(_ size: CGFloat, weight: Font.Weight = .regular) -> NSFont {
        (isAvailable ? NSFont(name: postScriptName(for: weight), size: size) : nil) ?? NSFont.systemFont(ofSize: size)
    }
}
