import AppKit
import XCTest
@testable import ShutApp

/// The one fact every clock in the panel reads: is this window on screen.
@MainActor
final class WindowPresenceTests: XCTestCase {
    func testOnScreenMeansVisibleUnminimizedAndUncovered() {
        XCTAssertFalse(WindowWatcherView.isOnScreen(nil), "no window: no clock")
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 200, height: 100), styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        XCTAssertFalse(WindowWatcherView.isOnScreen(window), "ordered out: not on screen")
        window.orderFrontRegardless()
        // Off the edge of every screen, so macOS may call it occluded; what the rule must
        // never do is call a window on screen while it is minimized or ordered out.
        window.miniaturize(nil)
        if window.isMiniaturized { XCTAssertFalse(WindowWatcherView.isOnScreen(window), "minimized: not on screen") }
        window.orderOut(nil)
        XCTAssertFalse(WindowWatcherView.isOnScreen(window))
        window.close()
    }
}
