import AppKit
import LidSensor
import Metal
import StayAwake
import SwiftUI
import TransitionKit
import Tuner
import XCTest
@testable import ShutApp

/// The Awake bar and page, rasterised offscreen in each state, against a stand-in
/// for the kernel so no test ever touches the real lid.
@MainActor
final class AwakeSnapshotTests: XCTestCase {
    override func setUpWithError() throws { try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "No Metal device on this machine") }

    final class FakeHold: LidHolding {
        func setLidSleepDisabled(_ disabled: Bool) -> Bool { true }
        func setIdleSleepPrevented(_ prevented: Bool) {}
    }

    final class FixedSource: HoldSource {
        var reasons: [HoldReason]
        var onChange: (() -> Void)?
        init(_ reasons: [HoldReason]) { self.reasons = reasons }
        func start() {}
        func stop() {}
    }

    private func makeModel(on: Bool, reasons: [HoldReason]) throws -> (PopoverModel, StayAwakeController) {
        let suite = UserDefaults(suiteName: "AwakeSnapshot-\(UUID().uuidString)")!
        let awakeSettings = StayAwakeSettings(defaults: suite)
        awakeSettings.hasConsented = on
        awakeSettings.isOn = on
        awakeSettings.whenWorking = false          // no real system reads
        awakeSettings.whenDisplayConnected = false
        let marker = ArmedMarker(directory: FileManager.default.temporaryDirectory.appendingPathComponent("AwakeSnapshot-\(UUID().uuidString)"))
        let arbiter = HoldArbiter(hold: FakeHold(), marker: marker, mirror: AssertionMirror(defaults: nil))
        let awake = StayAwakeController(settings: awakeSettings, arbiter: arbiter)
        awake.start()
        if !reasons.isEmpty { arbiter.add(FixedSource(reasons)) }

        let settings = AppSettings(defaults: suite)
        let registry = TransitionRegistry(transitions: TransitionCatalog.make(), currentID: "fold")
        let sensor = LidSensorMonitor(defaults: nil)
        let preview = try PreviewModel(registry: registry, settings: settings, sensor: sensor)
        preview.capturePlaceholder()
        let model = PopoverModel(settings: settings, registry: registry, preview: preview, sensor: sensor,
                                 thumbnails: try TransitionThumbnailRenderer(), stayAwake: awake)
        return (model, awake)
    }

    private func render(_ model: PopoverModel, name: String) throws {
        let frame = NSRect(x: 0, y: 0, width: PopoverView.width, height: 660)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = TunerTheme.appearance
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.62, green: 0.74, blue: 0.92, alpha: 1).cgColor
        let chrome = PanelChrome(frame: frame)
        let hosting = NSHostingView(rootView: PopoverView(model: model))
        chrome.install(hosting)
        container.addSubview(chrome)
        window.contentView = container
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let rep = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: container.bounds))
        container.cacheDisplay(in: container.bounds, to: rep)
        XCTAssertGreaterThan(rep.pixelsWide, 0)
        if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("awake-\(name).png"))
        }
    }

    func testBarWhenOffAndWhenHolding() throws {
        let (off, offAwake) = try makeModel(on: false, reasons: [])
        XCTAssertEqual(offAwake.status.action, .turnOn)
        try render(off, name: "bar-off")
        offAwake.shutDown()

        let started = Date().addingTimeInterval(-47 * 60)
        let (holding, awake) = try makeModel(on: true, reasons: [
            HoldReason(id: "working:cursor", kind: .working, title: "Cursor", since: started)])
        XCTAssertEqual(awake.arbiter.state, .holding)
        XCTAssertEqual(awake.status.sentence, "Cursor is working · 47 min")
        try render(holding, name: "bar-holding")
        awake.shutDown()
    }

    func testPageInItsStates() throws {
        let started = Date().addingTimeInterval(-47 * 60)
        let (holding, awake) = try makeModel(on: true, reasons: [
            HoldReason(id: "working:cursor", kind: .working, title: "Cursor", since: started),
            HoldReason(id: "display:studio", kind: .display, title: "Studio Display", since: started)])
        holding.page = .awake
        holding.preview.progress = 0.55
        try render(holding, name: "page-holding")
        awake.shutDown()

        let (ready, readyAwake) = try makeModel(on: true, reasons: [])
        ready.page = .awake
        XCTAssertEqual(readyAwake.arbiter.state, .ready)
        try render(ready, name: "page-ready")
        readyAwake.shutDown()

        let (off, offAwake) = try makeModel(on: false, reasons: [])
        off.page = .awake
        try render(off, name: "page-off")
        off.showingAwakeConsent = true
        try render(off, name: "page-consent")
        offAwake.shutDown()
    }
}
