import AppKit
import SwiftUI
import XCTest
@testable import Tuner

/// The host-page pieces: the share view (presets, copy, paste, import, export)
/// above the non-featured folders, at the popover column's width. Dumps a PNG
/// for review when SHUT_FRAME_DUMP is set.
@MainActor
final class ShareViewTests: XCTestCase {
    private func makeStore() -> (TunerStore<DemoParams>, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ShareView-\(UUID().uuidString)")
        let store = TunerStore<DemoParams>(presets: PresetStore(rootURL: tempDir),
                                           builtIns: [("Default", DemoParams()), ("Gentle", DemoParams())],
                                           defaults: UserDefaults(suiteName: "ShareView-\(UUID().uuidString)")!)
        return (store, tempDir)
    }

    func testSaveVersionRefusesBuiltInsAndReplacesOwn() throws {
        let (store, tempDir) = makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        XCTAssertEqual(store.saveVersion(named: "   "), .emptyName)
        XCTAssertEqual(store.saveVersion(named: "gentle"), .builtInName, "case-insensitive")
        XCTAssertEqual(store.saveVersion(named: " Slow drain "), .saved)
        XCTAssertEqual(store.activePresetName, "Slow drain")
        XCTAssertEqual(store.saveVersion(named: "Slow drain"), .replaced)
        XCTAssertEqual(store.allPresets.filter { $0.name == "Slow drain" }.count, 1)
    }

    func testPresetFileTextRoundTrips() throws {
        let (store, tempDir) = makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let text = store.presetFileText
        XCTAssertTrue(text.contains("\"transition\""), "a full preset file, not bare values")
        XCTAssertTrue(store.apply(json: text))
    }

    func testShareAndFoldersRenderOffscreen() throws {
        let (store, tempDir) = makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let view = VStack(alignment: .leading, spacing: 24) {
            Eyebrow("Adjust Demo", number: "03")
            TunerFoldersView(store: store, excludingFeatured: true)
            Eyebrow("Presets", number: "04")
            TunerShareView(store: store, expanded: .constant(true))
        }
        .padding(16)
        .tunerThemed()

        let frame = NSRect(x: 0, y: 0, width: 349, height: 1100)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = TunerTheme.appearance
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.62, green: 0.74, blue: 0.92, alpha: 1).cgColor
        let chrome = PanelChrome(frame: frame)
        let hosting = NSHostingView(rootView: AnyView(view))
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
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("share-view.png"))
        }
    }
}
