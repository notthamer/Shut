import AppKit
import SwiftUI
import XCTest
@testable import Tuner

/// The motion system's contract: Reduce Motion keeps fades and drops movement,
/// press feedback uses the documented scale, and the accessibility flags change
/// the surfaces they are meant to.
final class MotionTokensTests: XCTestCase {
    func testNothingMovesAndColourChangesEase() {
        XCTAssertNil(TunerTheme.resolve(TunerTheme.ease, motion: true, reduceMotion: false),
                     "movement is never animated: things change colour, not position")
        XCTAssertNil(TunerTheme.resolve(TunerTheme.ease, motion: true, reduceMotion: true))
        XCTAssertNotNil(TunerTheme.resolve(TunerTheme.ease, motion: false, reduceMotion: false),
                        "colour and opacity changes ease over 0.2 s")
        XCTAssertNotNil(TunerTheme.resolve(TunerTheme.ease, motion: false, reduceMotion: true),
                        "and stay, shorter, under Reduce Motion")
    }

    func testMotionScaleIsRealTimeUnlessAsked() {
        // Tests run without SHUT_MOTION_SCALE; the slow-motion switch is opt-in.
        XCTAssertEqual(TunerTheme.motionScale, 1)
    }

    func testAccessibilityFlagsChangeSurfaces() {
        let glass = TunerTheme(reduceTransparency: false, increaseContrast: false)
        let solid = TunerTheme(reduceTransparency: true, increaseContrast: true)
        XCTAssertLessThan(NSColor(glass.paper).alphaComponent, 1, "the paper lets a hint of the desktop through")
        XCTAssertEqual(NSColor(solid.paper).alphaComponent, 1, "Reduce Transparency makes the paper solid")
        XCTAssertLessThan(NSColor(solid.border).brightnessComponent, NSColor(glass.border).brightnessComponent,
                          "Increase Contrast darkens the border from Silver to Carbon")
        XCTAssertLessThan(NSColor(solid.inkLabel).brightnessComponent, NSColor(glass.inkLabel).brightnessComponent,
                          "Increase Contrast darkens secondary text from Carbon to Pure Black")
    }
}
