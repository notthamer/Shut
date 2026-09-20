import AppKit
import LidSensor
import Metal
@testable import StayAwake
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

    private func makeModel(on: Bool, reasons: [HoldReason], asking: [AssertionAttribution.Owner]? = nil) throws -> (PopoverModel, StayAwakeController) {
        let suite = UserDefaults(suiteName: "AwakeSnapshot-\(UUID().uuidString)")!
        let awakeSettings = StayAwakeSettings(defaults: suite)
        awakeSettings.hasConsented = on
        awakeSettings.isOn = on
        awakeSettings.whenWorking = asking != nil  // on only with a stand-in for the system read
        awakeSettings.whenDisplayConnected = false
        let marker = ArmedMarker(directory: FileManager.default.temporaryDirectory.appendingPathComponent("AwakeSnapshot-\(UUID().uuidString)"))
        let arbiter = HoldArbiter(hold: FakeHold(), marker: marker, mirror: AssertionMirror(defaults: nil, read: { asking ?? [] }))
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
            HoldReason(id: "working:cursor", kind: .working, title: "Cursor", tool: "Claude Code",
                       bundleID: "com.todesktop.230313mzl4w4u92", since: started)])
        XCTAssertEqual(awake.arbiter.state, .holding)
        XCTAssertEqual(awake.status.sentence, "Claude Code is working · 47 min")
        try render(holding, name: "bar-holding")
        awake.shutDown()
    }

    /// Option flips the decision for one close, and a second press takes it back.
    func testOptionFlipsAndFlipsBack() throws {
        let cursor = HoldReason(id: "working:cursor", kind: .working, title: "Cursor", since: Date())
        let (_, working) = try makeModel(on: true, reasons: [cursor])
        XCTAssertEqual(working.closingCaption(beginning: false)?.text, "Staying awake · Cursor is working")
        XCTAssertTrue(working.flipDecision())
        XCTAssertEqual(working.arbiter.state, .stopped(.userLetItSleep))
        XCTAssertEqual(working.closingCaption(beginning: false)?.text, "Sleeping this time")
        XCTAssertTrue(working.flipDecision())
        XCTAssertEqual(working.arbiter.state, .holding)
        working.shutDown()

        let (_, idle) = try makeModel(on: true, reasons: [])
        XCTAssertNil(idle.closingCaption(beginning: false))
        idle.flipDecision()
        XCTAssertEqual(idle.arbiter.state, .holding, "nothing was working: Option keeps it awake for an hour")
        idle.flipDecision()
        XCTAssertEqual(idle.arbiter.state, .ready)
        idle.shutDown()

        let (_, off) = try makeModel(on: false, reasons: [cursor])
        XCTAssertFalse(off.flipDecision(), "off is off")
        off.shutDown()
    }

    /// The hint teaches for five closes, or until Option is used once.
    func testTheOptionHintGetsOutOfTheWay() throws {
        let cursor = HoldReason(id: "working:cursor", kind: .working, title: "Cursor", since: Date())
        let (_, awake) = try makeModel(on: true, reasons: [cursor])
        for _ in 0..<StayAwakeSettings.optionHintLimit { XCTAssertNotNil(awake.closingCaption(beginning: true)?.hint) }
        XCTAssertNil(awake.closingCaption(beginning: true)?.hint)
        awake.shutDown()

        let (_, learner) = try makeModel(on: true, reasons: [cursor])
        XCTAssertNotNil(learner.closingCaption(beginning: true)?.hint)
        learner.flipDecision(); learner.flipDecision()
        XCTAssertNil(learner.closingCaption(beginning: true)?.hint, "used once is learned")
        learner.shutDown()
    }

    /// Nothing holds the lid and Zoom is asking: the bar and the page ask once, and
    /// either answer puts the ordinary status back.
    func testAnAppAskingToStayAwake() throws {
        let zoom = AssertionAttribution.Owner(app: .init(bundleID: "us.zoom.xos", name: "Zoom", isDeveloperTool: false),
                                              viaCommandLine: false, assertionName: "call", tool: nil)
        let (model, awake) = try makeModel(on: true, reasons: [], asking: [zoom])
        XCTAssertEqual(awake.pendingApp?.name, "Zoom")
        XCTAssertEqual(awake.status.sentence, "Zoom is asking to stay awake")
        XCTAssertEqual(awake.status.action, .allow)
        try render(model, name: "bar-pending")
        model.page = .awake
        try render(model, name: "page-pending")

        awake.perform(.notThisApp)
        XCTAssertNil(awake.pendingApp)
        XCTAssertNotEqual(awake.status.action, .allow)
        awake.shutDown()
    }

    func testPageInItsStates() throws {
        let started = Date().addingTimeInterval(-47 * 60)
        let cursor = HoldReason(id: "working:cursor", kind: .working, title: "Cursor", tool: "Claude Code",
                                bundleID: "com.todesktop.230313mzl4w4u92", since: started)
        let (one, oneAwake) = try makeModel(on: true, reasons: [cursor])
        one.page = .awake
        try render(one, name: "page-holding")
        oneAwake.shutDown()

        let (holding, awake) = try makeModel(on: true, reasons: [
            cursor, HoldReason(id: "display:studio", kind: .display, title: "Studio Display", since: started)])
        holding.page = .awake
        try render(holding, name: "page-two")
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
