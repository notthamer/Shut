import AppKit
import XCTest
@testable import Tuner

/// The bundled typeface registers from the package resources, so labels are
/// set in Apfel Grotezk wherever the app was built.
final class FontTests: XCTestCase {
    func testApfelGrotezkRegisters() {
        XCTAssertTrue(TunerFonts.isAvailable, "Apfel Grotezk should register from the Tuner bundle")
        for name in ["ApfelGrotezk-Regular", "ApfelGrotezk-Mittel", "ApfelGrotezk-Fett", "ApfelGrotezk-Satt"] {
            XCTAssertNotNil(NSFont(name: name, size: 13), name)
        }
        XCTAssertEqual(TunerFonts.postScriptName(for: .semibold), "ApfelGrotezk-Fett", "no 600 in the family; titles round up")
        XCTAssertNotNil(NSFont(name: TunerFonts.displayPostScriptName, size: 28), "Playfair Display registers from the bundle")
        XCTAssertEqual(TunerFonts.nsFont(13, weight: .medium).fontName, "ApfelGrotezk-Mittel")
    }

    /// The third precaution: a face that is not there is set in the system font, at the
    /// size and weight asked for, and the faces that are there are left alone.
    func testSystemFontStandsInForAMissingFace() {
        let system = NSFont.systemFont(ofSize: 15)
        let standIn = TunerFonts.nsFont(named: "NoSuchFace-Bold", size: 15, weight: .bold)
        XCTAssertEqual(standIn.familyName, system.familyName)
        XCTAssertEqual(standIn.pointSize, 15)
        XCTAssertTrue(NSFontManager.shared.traits(of: standIn).contains(.boldFontMask), "the weight survives the fallback")
        XCTAssertTrue(TunerFonts.systemFallbackWorks)
        XCTAssertEqual(TunerFonts.nsFont(named: "ApfelGrotezk-Fett", size: 15, weight: .bold).fontName, "ApfelGrotezk-Fett")
    }
}
