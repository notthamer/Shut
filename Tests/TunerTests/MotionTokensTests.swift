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
        let glass = TunerTheme(reduceTransparency: false, increaseContrast: false)
        let solid = TunerTheme(reduceTransparency: true, increaseContrast: true)
        XCTAssertLessThan(NSColor(glass.glassTint).alphaComponent, 1, "the cream lets a hint of the desktop through")
        XCTAssertEqual(NSColor(solid.glassTint).alphaComponent, 1, "Reduce Transparency makes the panel solid")
        XCTAssertEqual(NSColor(solid.glassSheen).alphaComponent, 0, "no sheen on a solid panel")
        XCTAssertGreaterThan(NSColor(solid.glassEdgeDark).alphaComponent, NSColor(glass.glassEdgeDark).alphaComponent,
                             "Increase Contrast strengthens the edge")
        XCTAssertGreaterThan(NSColor(solid.ink).alphaComponent, NSColor(glass.ink).alphaComponent,
                             "Increase Contrast darkens ink")
    }
}
