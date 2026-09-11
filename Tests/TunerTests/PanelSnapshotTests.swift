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
        let view = TunerPanelView(store: store) {
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.3))
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay(Text("preview slot").foregroundStyle(.secondary))
        }
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 900)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
        let container = NSView(frame: hosting.frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.addSubview(hosting)
        window.contentView = container
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let rep = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: container.bounds))
        container.cacheDisplay(in: container.bounds, to: rep)
        XCTAssertGreaterThan(rep.pixelsWide, 0)

        if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("tuner-panel.png"))
        }
    }
}
