import AppKit
import CoreText
import os
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
/// Nothing has to be installed, and the faces reach CoreText by two separate roads:
/// inside Shut.app, `ATSApplicationFontsPath` in Info.plist has macOS register them
/// before any of our code runs; everywhere else (and as the backup in the app) they
/// register from `Shut_Tuner.bundle` the first time a font is asked for. The third
/// precaution is the system font, face by face: a broken install shows plain text
/// rather than crashing. `shut --self-check` tests all three and fails a build where
/// any face is missing, so a release never needs the third.
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

    /// Every face the interface asks for by name.
    static let requiredFaces = ["ApfelGrotezk-Regular", "ApfelGrotezk-Mittel", "ApfelGrotezk-Fett", "ApfelGrotezk-Satt", displayPostScriptName]

    /// The faces CoreText cannot find, after registering. Empty in a healthy build.
    public static var missingFaces: [String] {
        _ = isAvailable
        return requiredFaces.filter { NSFont(name: $0, size: 12) == nil }
    }

    /// True when macOS had already registered every face before we did anything
    /// (the `ATSApplicationFontsPath` road). Read it before `isAvailable`.
    public static let registeredBySystem: Bool = requiredFaces.allSatisfy { NSFont(name: $0, size: 12) != nil }

    /// True once the faces are available to CoreText.
    public static let isAvailable: Bool = {
        _ = registeredBySystem
        let registered = register()
        if !registered { Logger(subsystem: "app.shut", category: "fonts").fault("Bundled fonts missing; using the system font") }
        return registered
    }()

    @discardableResult
    static func register() -> Bool {
        if requiredFaces.allSatisfy({ NSFont(name: $0, size: 12) != nil }) { return true }
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

    /// The faces CoreText really has, asked once after registering. Every accessor
    /// below checks the exact face it wants here, so the third precaution works face
    /// by face: if one weight is gone, that weight alone is set in the system font
    /// and the rest of the interface keeps its typefaces.
    static let availableFaces: Set<String> = {
        _ = isAvailable
        return Set(requiredFaces.filter { NSFont(name: $0, size: 12) != nil })
    }()

    /// Body text at a size and weight, with the system font as the fallback.
    public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(named: postScriptName(for: weight), size: size, weight: weight)
    }

    /// The serif display face, with the system serif as the fallback.
    public static func display(_ size: CGFloat) -> Font {
        availableFaces.contains(displayPostScriptName)
            ? Font.custom(displayPostScriptName, size: size)
            : Font.system(size: size, weight: .regular, design: .serif)
    }

    /// Eyebrows, numbers and values.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }

    /// The AppKit counterpart of `font`, for places that draw with NSFont.
    public static func nsFont(_ size: CGFloat, weight: Font.Weight = .regular) -> NSFont {
        nsFont(named: postScriptName(for: weight), size: size, weight: weight)
    }

    // The two below take the face by name so the tests can ask for one that does not exist.

    static func font(named name: String, size: CGFloat, weight: Font.Weight) -> Font {
        availableFaces.contains(name) ? Font.custom(name, size: size) : Font.system(size: size, weight: weight)
    }

    static func nsFont(named name: String, size: CGFloat, weight: Font.Weight) -> NSFont {
        (availableFaces.contains(name) ? NSFont(name: name, size: size) : nil)
            ?? NSFont.systemFont(ofSize: size, weight: nsWeight(weight))
    }

    /// The system-font weight that stands in for an Apfel weight.
    static func nsWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return .regular
        case .medium: return .medium
        case .semibold, .bold: return .bold
        default: return .black
        }
    }

    /// True when asking for a face that is not there gives the system font at the right
    /// size and weight. `shut --self-check` runs it: the last precaution is tested too.
    public static var systemFallbackWorks: Bool {
        let font = nsFont(named: "NoSuchFace-Regular", size: 13, weight: .medium)
        return font.pointSize == 13 && font.familyName == NSFont.systemFont(ofSize: 13).familyName
    }
}
