import AppKit
import LidSensor
import SwiftUI
import TransitionKit
import XCTest
@testable import ShutApp

/// Lays the popover out offscreen with real model objects (no running app) and
/// rasterises it, so the whole primary UI is checked as an image.
@MainActor
final class PopoverSnapshotTests: XCTestCase {
    func testPopoverRendersOffscreen() throws {
        let defaults = UserDefaults(suiteName: "PopoverSnapshot-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let registry = TransitionRegistry(transitions: TransitionCatalog.make(), currentID: "fold")
        let sensor = LidSensorMonitor(defaults: nil)
        let preview = try PreviewModel(registry: registry, settings: settings, sensor: sensor)
        let thumbnails = try TransitionThumbnailRenderer()
        let model = PopoverModel(settings: settings, registry: registry, preview: preview, sensor: sensor, thumbnails: thumbnails)
        registry.captureAvailable = false   // exercise the permission card
        preview.capture()                    // no permission in tests → placeholder desktop
        XCTAssertTrue(preview.hasSnapshot)
        XCTAssertTrue(preview.usesPlaceholder)

        XCTAssertEqual(model.statusLine, "Fold needs Screen Recording")
        XCTAssertTrue(model.needsPermissionCard)

        let variants: [(String, NSAppearance.Name, Bool)] = [("dark", .darkAqua, false), ("light", .aqua, false), ("window", .darkAqua, true)]
        for (name, appearance, inWindow) in variants {
            let hosting = NSHostingView(rootView: AnyView(PopoverView(model: model, hostedInWindow: inWindow)))
            hosting.frame = NSRect(x: 0, y: 0, width: PopoverView.width, height: 640)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let container = NSView(frame: hosting.frame)
            container.wantsLayer = true
            container.addSubview(hosting)
            window.contentView = container
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))

            let rep = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: container.bounds))
            container.cacheDisplay(in: container.bounds, to: rep)
            XCTAssertGreaterThan(rep.pixelsWide, 0)
            if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"],
               let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("popover-\(name).png"))
            }
        }
    }

    func testSpeedMapsToBand() {
        let defaults = UserDefaults(suiteName: "PopoverSpeed-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let registry = TransitionRegistry(transitions: TransitionCatalog.make(), currentID: "fold")
        let sensor = LidSensorMonitor(defaults: nil)
        let preview = try! PreviewModel(registry: registry, settings: settings, sensor: sensor)
        let model = PopoverModel(settings: settings, registry: registry, preview: preview, sensor: sensor, thumbnails: nil)
        model.speed = 1
        XCTAssertEqual(settings.bandDegrees, 20, accuracy: 0.001, "fast = last 20°")
        model.speed = 0
        XCTAssertEqual(settings.bandDegrees, 100, accuracy: 0.001, "slow = 100° of travel")
        XCTAssertEqual(settings.timedCloseDuration, 1.6, accuracy: 0.001)
    }
}

@MainActor
final class AssetTests: XCTestCase {
    func testLogoAndMenuBarIconLoad() throws {
        let logo = try XCTUnwrap(AppAssets.logo, "logo.png must ship in the ShutApp resource bundle")
        XCTAssertGreaterThan(logo.size.width, 100)
        let icon = try XCTUnwrap(AppAssets.menuBarIcon)
        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.size, NSSize(width: 18, height: 18))
        if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"], let cg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("menubar-icon.png"))
        }
    }
}
