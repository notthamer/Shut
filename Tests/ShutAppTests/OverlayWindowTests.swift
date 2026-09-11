import AppKit
import XCTest
import TransitionKit
@testable import ShutApp

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

    func testProgressDriverFollowsHingeThenSprings() {
        var driver = ProgressDriver()
        driver.followLag = 0
        driver.step(dt: 1.0 / 120, hinge: 0.5)
        XCTAssertEqual(driver.progress, 0.5, accuracy: 0.001)

        driver.commitThreshold = 0.5
        driver.reset(); driver.followLag = 0
        driver.step(dt: 1.0 / 120, hinge: 0.29)
        XCTAssertEqual(driver.mode, .follow)
        driver.step(dt: 1.0 / 120, hinge: 0.53)
        XCTAssertEqual(driver.mode, .spring)
        for _ in 0..<240 { driver.step(dt: 1.0 / 120, hinge: 0.53) }
        XCTAssertEqual(driver.progress, 1, accuracy: 0.001, "commit spring finishes the close on its own")
    }

    func testTimedModeEasesToTargetAndSettles() {
        var driver = ProgressDriver()
        driver.timed(to: 1, duration: 0.5)
        var last = 0.0
        for _ in 0..<30 { last = driver.step(dt: 1.0 / 60, hinge: nil) }
        XCTAssertEqual(last, 1, accuracy: 0.001)
        XCTAssertTrue(driver.isSettled)
        driver.timed(to: 0, duration: 0.5)
        driver.step(dt: 0.25, hinge: nil)
        XCTAssertEqual(driver.progress, 0.5, accuracy: 0.01, "ease-in-out is symmetric at the midpoint")
    }

    func testOverlayTransparentRoundTrip() throws {
        let renderer = try TransitionRenderer()
        let screen = try XCTUnwrap(BuiltInDisplay.screen ?? NSScreen.main)
        let window = OverlayWindow(screen: screen, renderer: renderer, transition: AnyTransition(ApertureTransition()),
                                   context: RenderContext(snapshotSize: SIMD2(10, 10), sinkPoint: .zero, notchSize: .zero, usesVirtualNotch: true))
        window.setTransparent(true)
        XCTAssertFalse(window.isOpaque); XCTAssertTrue(window.metalView.isTransparent)
        window.setTransparent(false)
        XCTAssertTrue(window.isOpaque); XCTAssertFalse(window.metalView.isTransparent)
    }
}

@MainActor
final class FollowGlideTests: XCTestCase {
    /// Hinge progress that steps every 4 frames must not produce visible steps.
    func testGlideRemovesSteps() {
        var driver = ProgressDriver()
        var maxJump = 0.0, last = 0.0, hinge = 0.0
        for frame in 0..<120 {
            if frame % 4 == 0 { hinge = Double(frame) / 120 }
            let p = driver.step(dt: 1.0 / 120, hinge: hinge)
            maxJump = max(maxJump, abs(p - last)); last = p
        }
        XCTAssertLessThan(maxJump, 0.02)
        XCTAssertGreaterThan(driver.progress, 0.85)
    }
}
