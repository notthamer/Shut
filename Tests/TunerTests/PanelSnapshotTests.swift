import AppKit
import SwiftUI
import XCTest
@testable import Tuner

/// Lays the panel out in an offscreen window and rasterises it. Proves every
/// control type renders without throwing, and dumps a PNG for review when
/// SHUT_FRAME_DUMP is set.
@MainActor
final class PanelSnapshotTests: XCTestCase {
    func testPanelRendersEveryControlType() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PanelSnapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = TunerStore<DemoParams>(presets: PresetStore(rootURL: tempDir),
                                           builtIns: [("Default", DemoParams())],
                                           defaults: UserDefaults(suiteName: "PanelSnapshot-\(UUID().uuidString)")!)
        let view = TunerPanelView(store: store, title: "Demo", onCollapse: {}) {
            RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.3))
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay(Text("preview slot").foregroundStyle(.secondary))
        }
        // Glass over a coloured backdrop, and the solid variant Reduce
        // Transparency and Increase Contrast ask for.
        let variants: [(String, TunerTheme?)] = [("tuner-panel", nil), ("tuner-panel-solid", TunerTheme(reduceTransparency: true, increaseContrast: true))]
        for (name, theme) in variants {
            var root = AnyView(view)
            if let theme { root = AnyView(root.environment(\.tunerTheme, theme)) }
            let frame = NSRect(x: 0, y: 0, width: 360, height: 1180)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = TunerTheme.appearance
            let container = NSView(frame: frame)
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(red: 0.62, green: 0.74, blue: 0.92, alpha: 1).cgColor
            let chrome = PanelChrome(frame: frame)
            let hosting = NSHostingView(rootView: root)
            chrome.install(hosting)
            container.addSubview(chrome)
            window.contentView = container
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))

            let rep = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: container.bounds))
            container.cacheDisplay(in: container.bounds, to: rep)
            XCTAssertGreaterThan(rep.pixelsWide, 0)

            if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"],
               let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
    }
}

@MainActor
final class PanelChromeTests: XCTestCase {
    func testChromeInstallsContentAboveBlur() {
        let chrome = PanelChrome(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let content = NSView(frame: .zero)
        chrome.install(content)
        XCTAssertEqual(chrome.subviews.count, 2, "blur plus content")
        XCTAssertTrue(chrome.subviews.last === content, "content sits above the blur")
        XCTAssertEqual(chrome.appearance?.name, .aqua, "light glass, whatever the system appearance")
        XCTAssertEqual(content.frame, chrome.bounds)
    }
}
