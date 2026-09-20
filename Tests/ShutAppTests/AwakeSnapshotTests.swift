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
        let plugged = PowerSourceMonitor(reader: { PowerConditions(onCharger: true, batteryPercent: 90) })
        let arbiter = HoldArbiter(hold: FakeHold(), marker: marker, monitor: plugged, mirror: AssertionMirror(defaults: nil, read: { asking ?? [] }),
                                  displays: DisplayConnected(read: { [] }))
        let awake = StayAwakeController(settings: awakeSettings, arbiter: arbiter, hasLid: true)
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

    // MARK: The receipt slip

    /// A held close that ended while the lid was shut, left unread in the journal.
    private func leaveAReceipt(in awake: StayAwakeController, end: HoldState = .ready) {
        let shut = Date().addingTimeInterval(-2 * 3600 - 14 * 60)
        let cursor = HoldReason(id: "working:cursor", kind: .working, title: "Claude Code", since: shut)
        awake.journal.lidShut(holding: true, reasons: [cursor], battery: 82, now: shut)
        awake.journal.holdChanged(to: end, now: Date().addingTimeInterval(-40 * 60))
        awake.journal.lidOpened(battery: 64)
    }

    func testTheSlipWaitsForTheUnlockAndSpeaksOnce() throws {
        let (_, awake) = try makeModel(on: true, reasons: [])
        leaveAReceipt(in: awake)
        let receipt = try XCTUnwrap(awake.journal.last)

        var locked = true
        var shown: [HoldReceipt] = []
        let slip = ReceiptSlip(stayAwake: awake, isLocked: { locked })
        slip.settleDelay = 0
        slip.present = { shown.append($0) }

        slip.lidOpened(receipt)
        XCTAssertTrue(shown.isEmpty, "nothing over a lock screen")
        locked = false
        slip.sessionUnlocked()
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(awake.journal.last?.read, true, "handed over counts as read, so the bar does not repeat it")

        slip.sessionUnlocked()
        XCTAssertEqual(shown.count, 1, "once per return")
        awake.shutDown()
    }

    /// What swallowed the first real slip: the Awake page was open, drew "Last time", and
    /// marked the receipt read before the slip's moment came. The slip holds the receipt it
    /// was handed, so that no longer matters; nor does a main window, which may be minimized.
    func testAnOpenAwakePageDoesNotSwallowTheSlip() throws {
        let (_, awake) = try makeModel(on: true, reasons: [])
        leaveAReceipt(in: awake)
        let receipt = try XCTUnwrap(awake.journal.last)
        var shown = 0
        let slip = ReceiptSlip(stayAwake: awake, isLocked: { false })
        slip.settleDelay = 0
        slip.present = { _ in shown += 1 }
        awake.perform(.ok)   // the page marking it read
        slip.lidOpened(receipt)
        XCTAssertEqual(shown, 1)
        awake.shutDown()
    }

    func testNoSlipWhenSwitchedOffOrUnderTheOpenPopover() throws {
        let (_, awake) = try makeModel(on: true, reasons: [])
        leaveAReceipt(in: awake)
        let receipt = try XCTUnwrap(awake.journal.last)
        var shown = 0
        let underThePopover = ReceiptSlip(stayAwake: awake, isLocked: { false }, anotherSurfaceIsOpen: { true })
        underThePopover.settleDelay = 0
        underThePopover.present = { _ in shown += 1 }
        underThePopover.lidOpened(receipt)
        XCTAssertEqual(shown, 0)
        XCTAssertEqual(awake.journal.last?.read, false, "the popover's bar says it instead")

        awake.settings.showReceipt = false
        let quiet = ReceiptSlip(stayAwake: awake, isLocked: { false })
        quiet.settleDelay = 0
        quiet.present = { _ in shown += 1 }
        quiet.lidOpened(receipt)
        XCTAssertEqual(shown, 0)
        awake.shutDown()
    }

    /// The "What's new" card, with this version's real changelog section.
    func testTheWhatsNewCardRenders() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        var section = "", on = false
        for line in changelog.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { if on { break }; on = true; continue }
            if on { section += line + "\n" }
        }
        let news = try XCTUnwrap(WhatsNew.parse(section))
        let hosting = NSHostingView(rootView: WhatsNewView(news: news, version: "0.3.0"))
        hosting.appearance = TunerTheme.appearance
        let size = hosting.fittingSize
        XCTAssertEqual(size.width, WhatsNewView.width)
        XCTAssertLessThan(size.height, 520, "a card, not a page")
        hosting.frame = NSRect(origin: NSPoint(x: 24, y: 24), size: size)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size.width + 48, height: size.height + 48))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).cgColor
        container.addSubview(hosting)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let rep = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: container.bounds))
        container.cacheDisplay(in: container.bounds, to: rep)
        if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("whats-new.png"))
        }
    }

    func testTheSlipRenders() throws {
        let (_, awake) = try makeModel(on: true, reasons: [])
        for (name, end) in [("finished", HoldState.ready), ("battery", .stopped(.batteryFloor))] {
            leaveAReceipt(in: awake, end: end)
            let receipt = try XCTUnwrap(awake.journal.last)
            XCTAssertFalse(AwakeText.receipt(receipt).isEmpty)
            let hosting = NSHostingView(rootView: ReceiptSlipView(receipt: receipt).environment(\.tunerTheme, TunerTheme()))
            hosting.appearance = TunerTheme.appearance
            let size = hosting.fittingSize
            XCTAssertEqual(size.width, ReceiptSlipView.width)
            hosting.frame = NSRect(origin: .zero, size: size)
            let container = NSView(frame: hosting.frame.insetBy(dx: -24, dy: -24).offsetBy(dx: 24, dy: 24))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).cgColor
            hosting.setFrameOrigin(NSPoint(x: 24, y: 24))
            container.addSubview(hosting)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let rep = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: container.bounds))
            container.cacheDisplay(in: container.bounds, to: rep)
            if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"], let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("slip-\(name).png"))
            }
        }
        awake.shutDown()
    }

    /// The dial starts, changes and ends the manual hold.
    func testTheDialHoldsForWhatItSays() throws {
        let (model, awake) = try makeModel(on: true, reasons: [], asking: [])
        XCTAssertEqual(awake.manualStop(), 0)
        let ninety = AwakeText.manualStop(remaining: 90 * 60)
        awake.setManualHold(stop: ninety)
        XCTAssertEqual(awake.arbiter.state, .holding)
        let hold = try XCTUnwrap(awake.manualHold)
        XCTAssertEqual(try XCTUnwrap(hold.until).timeIntervalSince(hold.since), 90 * 60, accuracy: 1)
        XCTAssertEqual(awake.manualStop(), ninety)
        XCTAssertEqual(awake.manualStop(now: Date().addingTimeInterval(50 * 60)), AwakeText.manualStop(remaining: 45 * 60), "40 min left: the thumb has drifted to 45 min")
        model.page = .awake
        try render(model, name: "page-manual")

        awake.setManualHold(stop: AwakeText.manualLastStop)
        XCTAssertNil(try XCTUnwrap(awake.manualHold).until, "until stopped")
        awake.setManualHold(stop: 0)
        XCTAssertEqual(awake.arbiter.state, .ready)
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
        let (one, oneAwake) = try makeModel(on: true, reasons: [cursor], asking: [])
        oneAwake.settings.whenDisplayConnected = false
        one.page = .awake
        try render(one, name: "page-holding")
        oneAwake.shutDown()

        let (holding, awake) = try makeModel(on: true, reasons: [
            cursor, HoldReason(id: "display:studio", kind: .display, title: "Studio Display", since: started)], asking: [])
        holding.page = .awake
        try render(holding, name: "page-two")
        awake.shutDown()

        let (ready, readyAwake) = try makeModel(on: true, reasons: [], asking: [])
        ready.page = .awake
        XCTAssertEqual(readyAwake.arbiter.state, .ready)
        try render(ready, name: "page-ready")
        // The folded Settings, by themselves: inside the panel they sit below the fold.
        let settingsView = NSHostingView(rootView: AwakeLimits(model: ready).padding(16)
            .frame(width: PopoverView.width - PopoverView.previewWidth - 1).tunerThemed())
        settingsView.appearance = TunerTheme.appearance
        settingsView.frame = NSRect(origin: .zero, size: settingsView.fittingSize)
        settingsView.wantsLayer = true
        settingsView.layer?.backgroundColor = NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).cgColor
        settingsView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let settingsRep = try XCTUnwrap(settingsView.bitmapImageRepForCachingDisplay(in: settingsView.bounds))
        settingsView.cacheDisplay(in: settingsView.bounds, to: settingsRep)
        if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"], let png = settingsRep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("awake-settings.png"))
        }
        readyAwake.shutDown()

        let (off, offAwake) = try makeModel(on: false, reasons: [])
        off.page = .awake
        try render(off, name: "page-off")
        off.showingAwakeConsent = true
        try render(off, name: "page-consent")
        offAwake.shutDown()
    }
}
