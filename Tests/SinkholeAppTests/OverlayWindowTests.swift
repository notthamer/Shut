import AppKit
import XCTest
import TransitionKit
@testable import SinkholeApp

/// Constructs the overlay exactly as AppController does, without ordering it on
/// screen. Guards against NSWindow subclass initializer traps, which only show up
/// at runtime.
@MainActor
final class OverlayWindowTests: XCTestCase {
    func testOverlayWindowConstructs() throws {
        let renderer = try TransitionRenderer()
        let screen = try XCTUnwrap(BuiltInDisplay.screen ?? NSScreen.main)
        let context = RenderContext(snapshotSize: SIMD2(100, 100), sinkPoint: SIMD2(50, 10),
                                    notchSize: SIMD2(20, 10), usesVirtualNotch: false)
        let window = OverlayWindow(screen: screen, renderer: renderer,
                                   transition: AnyTransition(FadeTransition()), context: context)
        XCTAssertEqual(window.frame, screen.frame)
        XCTAssertEqual(window.level, .screenSaver)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.isVisible)
        // Rendering with no snapshot must be a no-op, not a crash.
        window.metalView.render()
        window.metalView.isBlackedOut = true
        window.metalView.render()
    }

    func testProgressDriverFollowsLidThenSprings() {
        var driver = ProgressDriver(startAngle: 80, endAngle: 12)
        XCTAssertEqual(driver.rawProgress(angle: 80), 0)
        XCTAssertEqual(driver.rawProgress(angle: 12), 1)
        XCTAssertEqual(driver.rawProgress(angle: 46), 0.5, accuracy: 0.001)

        driver.commitThreshold = 0.5
        driver.step(dt: 1.0 / 120, angle: 60)     // raw 0.29: still following
        XCTAssertEqual(driver.mode, .follow)
        driver.step(dt: 1.0 / 120, angle: 44)     // raw 0.53: commit
        XCTAssertEqual(driver.mode, .spring)
        for _ in 0..<240 { driver.step(dt: 1.0 / 120, angle: 44) }
        XCTAssertEqual(driver.progress, 1, accuracy: 0.001, "commit spring finishes the close on its own")
    }
}

@MainActor
final class FollowGlideTests: XCTestCase {
    /// A sensor that steps 1° at 30 Hz must not produce visible steps at 120 Hz.
    func testGlideRemovesSensorSteps() {
        var driver = ProgressDriver(startAngle: 80, endAngle: 12)
        var maxJump = 0.0
        var last = driver.progress
        var angle = 80.0
        let closingSpeed = -120.0  // °/s
        for frame in 0..<120 {
            if frame % 4 == 0 { angle = (80 + closingSpeed * Double(frame) / 120).rounded() }  // 30 Hz, whole degrees
            let p = driver.step(dt: 1.0 / 120, angle: angle, velocity: closingSpeed)
            maxJump = max(maxJump, abs(p - last))
            last = p
        }
        // Raw would jump 4°/68° ≈ 0.059 every 4th frame; glided must be well under that.
        XCTAssertLessThan(maxJump, 0.03)
        XCTAssertGreaterThan(driver.progress, 0.9, "look-ahead keeps it from lagging far behind")
    }
}
