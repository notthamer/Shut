import AppKit
import SwiftUI
import XCTest
@testable import Tuner

/// The motion system's contract: Reduce Motion keeps fades and drops movement,
/// press feedback uses the documented scale, and the accessibility flags change
/// the surfaces they are meant to.
final class MotionTokensTests: XCTestCase {
    func testReduceMotionKeepsFadesAndDropsMovement() {
        XCTAssertNil(TunerTheme.resolve(TunerTheme.quick, motion: true, reduceMotion: true),
                     "movement is dropped under Reduce Motion")
        XCTAssertNotNil(TunerTheme.resolve(TunerTheme.quick, motion: false, reduceMotion: true),
                        "fades and colour changes stay, shorter")
        XCTAssertNotNil(TunerTheme.resolve(TunerTheme.quick, motion: true, reduceMotion: false))
    }

    func testPressFeedbackScale() {
        XCTAssertEqual(PressScaleStyle().scale, 0.97)
        XCTAssertEqual(PressScaleStyle(scale: 0.96).scale, 0.96)
    }

    func testMotionScaleIsRealTimeUnlessAsked() {
        // Tests run without SHUT_MOTION_SCALE; the slow-motion switch is opt-in.
        XCTAssertEqual(TunerTheme.motionScale, 1)
    }

    func testAccessibilityFlagsChangeSurfaces() {
        let glass = TunerTheme(colorScheme: .dark, reduceTransparency: false, increaseContrast: false)
        let solid = TunerTheme(colorScheme: .dark, reduceTransparency: true, increaseContrast: true)
        XCTAssertLessThan(NSColor(glass.panelGlass).alphaComponent, 1, "glass lets the blur through")
        XCTAssertEqual(NSColor(solid.panelGlass).alphaComponent, 1, "Reduce Transparency makes the panel solid")
        XCTAssertGreaterThan(NSColor(solid.border).alphaComponent, NSColor(glass.border).alphaComponent,
                             "Increase Contrast strengthens the hairline")
    }
}
