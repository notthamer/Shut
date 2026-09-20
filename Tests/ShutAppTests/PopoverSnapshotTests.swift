import AppKit
import LidSensor
import SwiftUI
import TransitionKit
import Tuner
import Metal
import XCTest
@testable import ShutApp

/// Lays the popover out offscreen with real model objects (no running app) and
/// rasterises it, so the whole primary UI is checked as an image.
@MainActor
final class PopoverSnapshotTests: XCTestCase {
    /// GitHub-hosted macOS runners have no GPU. Skip, do not fail.
    override func setUpWithError() throws { try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "No Metal device on this machine") }
    func testPopoverRendersOffscreen() throws {
        let defaults = UserDefaults(suiteName: "PopoverSnapshot-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let registry = TransitionRegistry(transitions: TransitionCatalog.make(), currentID: "fold")
        let sensor = LidSensorMonitor(defaults: nil)
        let preview = try PreviewModel(registry: registry, settings: settings, sensor: sensor)
        let thumbnails = try TransitionThumbnailRenderer()
        let model = PopoverModel(settings: settings, registry: registry, preview: preview, sensor: sensor, thumbnails: thumbnails)
        registry.captureAvailable = false   // exercise the permission card
        preview.capturePlaceholder()         // the drawn desktop, whatever this machine's permission
        XCTAssertTrue(preview.hasSnapshot)
        XCTAssertTrue(preview.usesPlaceholder)

        XCTAssertEqual(model.statusLine, "Fold needs Screen Recording")
        XCTAssertTrue(model.needsPermissionCard)

        // Light glass over a coloured backdrop, the same hosted in a window, and
        // the solid look Reduce Transparency and Increase Contrast ask for.
        let variants: [(String, Bool, Bool)] = [("light", false, false), ("window", true, false), ("solid", false, true)]
        for (name, inWindow, solid) in variants {
            var root = AnyView(PopoverView(model: model, hostedInWindow: inWindow))
            if solid {
                root = AnyView(root.environment(\.tunerTheme, TunerTheme(reduceTransparency: true, increaseContrast: true)))
            }
            let frame = NSRect(x: 0, y: 0, width: PopoverView.width, height: 660)
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

    /// The welcome is the one dark surface; rasterise it so the stage is checked
    /// as an image.
    func testWelcomeRendersOffscreen() throws {
        let frame = NSRect(x: 0, y: 0, width: 480, height: 380)
        let stage = VoidBackdrop(frame: frame)
        let hosting = NSHostingView(rootView: WelcomeView(capability: .continuousAngle, enable: {}))
        hosting.frame = frame
        stage.addSubview(hosting)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = stage
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let rep = try XCTUnwrap(stage.bitmapImageRepForCachingDisplay(in: stage.bounds))
        stage.cacheDisplay(in: stage.bounds, to: rep)
        XCTAssertGreaterThan(rep.pixelsWide, 0)
        if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("welcome.png"))
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
        XCTAssertEqual(settings.bandDegrees, 130, accuracy: 0.001, "slow = the whole close (clamped to the lid later)")
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

    /// Dot and ring are tinted by the menu bar; only Saffron brings its own colour.
    func testMenuBarBadges() throws {
        let mark = try XCTUnwrap(AppAssets.menuBarIcon)
        XCTAssertTrue(MenuBarController.image(mark: mark, dot: .idle) === mark, "idle is the plain mark")
        for dot in [AwakeText.Dot.holding, .winding, .warning] {
            let image = MenuBarController.image(mark: mark, dot: dot)
            XCTAssertEqual(image.size, mark.size)
            XCTAssertEqual(image.isTemplate, dot != .warning)
            XCTAssertNotNil(image.accessibilityDescription)
            guard let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"] else { continue }
            // Eight times the size, on a light and a dark bar, so the badge can be judged by eye.
            let sheet = NSImage(size: NSSize(width: 288, height: 144), flipped: false) { _ in
                for (index, appearance) in [NSAppearance.Name.aqua, .darkAqua].enumerated() {
                    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                        let cell = NSRect(x: CGFloat(index) * 144, y: 0, width: 144, height: 144)
                        (index == 0 ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.16, alpha: 1)).setFill()
                        cell.fill()
                        if image.isTemplate {
                            let tinted = NSImage(size: image.size, flipped: false) { rect in
                                image.draw(in: rect); NSColor.labelColor.setFill(); rect.fill(using: .sourceIn); return true
                            }
                            tinted.draw(in: cell)
                        } else {
                            image.draw(in: cell)
                        }
                    }
                }
                return true
            }
            if let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("menubar-badge-\(dot).png"))
            }
        }
    }
}
