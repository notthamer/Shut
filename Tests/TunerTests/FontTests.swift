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
}
