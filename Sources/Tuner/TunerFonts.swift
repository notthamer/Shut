import AppKit
import CoreText
import SwiftUI

/// The three voices of the interface:
///
/// - **Display**: Playfair Display (OFL), a light serif for the wordmark, headlines
///   and style names. Weight 400 with tight tracking; authority through restraint.
/// - **Body**: Apfel Grotezk (Collletttivo, OFL), a round humanist grotesk for
///   labels and copy. Weight 500 only for emphasis.
/// - **Mono**: the system monospaced face for eyebrows, chapter numbers and
///   values, all-caps with wide tracking for the eyebrows.
///
/// The bundled faces register for this process the first time a font is asked
/// for, so nothing has to be installed. A missing bundle falls back to the
/// system font.
public enum TunerFonts {
    public static let bodyFamily = "Apfel Grotezk"
    public static let displayFamily = "Playfair Display"

    /// Apfel's PostScript names by weight. The family has no 600, so semibold
    /// rounds up to Fett (700); heavier weights get Satt (900).
    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return "ApfelGrotezk-Regular"
        case .medium: return "ApfelGrotezk-Mittel"
        case .semibold, .bold: return "ApfelGrotezk-Fett"
        default: return "ApfelGrotezk-Satt"
        }
    }

    static let displayPostScriptName = "PlayfairDisplay-Regular"

    /// True once the faces are available to CoreText.
    public static let isAvailable: Bool = register()

    @discardableResult
    static func register() -> Bool {
        if NSFont(name: "ApfelGrotezk-Regular", size: 12) != nil, NSFont(name: displayPostScriptName, size: 12) != nil { return true }
        guard let bundle = resourceBundle() else { return false }
        let urls = (bundle.urls(forResourcesWithExtension: "otf", subdirectory: "Fonts") ?? [])
            + (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: "ApfelGrotezk-Regular", size: 12) != nil
    }

    /// Locates `Shut_Tuner.bundle` by looking where the bundle can really be. The
    /// accessor SwiftPM generates only knows the .app root and the absolute build
    /// directory of the Mac that compiled it, and traps when neither is there:
    /// inside Shut.app that is every Mac but the one that built it (0.2.0 and earlier
    /// crashed on launch this way).
    static func resourceBundle() -> Bundle? {
        let name = "Shut_Tuner.bundle"
        var candidates: [URL] = []
        if let url = Bundle.main.resourceURL { candidates.append(url) }        // Shut.app/Contents/Resources
        candidates.append(Bundle.main.bundleURL)                                // .app root, or swift build dir
        if let exe = Bundle.main.executableURL { candidates.append(exe.deletingLastPathComponent()) }
        let hostBundle = Bundle(for: PresetStore.self)
        candidates.append(hostBundle.bundleURL)
        if let url = hostBundle.resourceURL { candidates.append(url) }
        // `swift test`: the resource bundle sits next to the .xctest bundle.
        candidates.append(hostBundle.bundleURL.deletingLastPathComponent())
        for dir in candidates {
            if let bundle = Bundle(url: dir.appendingPathComponent(name)) { return bundle }
        }
        return nil
    }

    /// Body text at a size and weight, with the system font as the fallback.
    public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        isAvailable ? Font.custom(postScriptName(for: weight), size: size) : Font.system(size: size, weight: weight)
    }

    /// The serif display face.
    public static func display(_ size: CGFloat) -> Font {
        (isAvailable && NSFont(name: displayPostScriptName, size: size) != nil)
            ? Font.custom(displayPostScriptName, size: size)
            : Font.system(size: size, weight: .regular, design: .serif)
    }

    /// Eyebrows, numbers and values.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }

    /// The AppKit counterpart of `font`, for places that draw with NSFont.
    public static func nsFont(_ size: CGFloat, weight: Font.Weight = .regular) -> NSFont {
        (isAvailable ? NSFont(name: postScriptName(for: weight), size: size) : nil) ?? NSFont.systemFont(ofSize: size)
    }
}
