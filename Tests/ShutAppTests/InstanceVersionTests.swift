import XCTest
@testable import ShutApp

final class InstanceVersionTests: XCTestCase {
    func testNewerComparesNumerically() {
        let v = { (s: String, b: String) in InstanceVersion(short: s, build: b) }
        XCTAssertTrue(v("0.2.0", "1").isNewer(than: v("0.1.0", "9")))
        XCTAssertTrue(v("0.10.0", "1").isNewer(than: v("0.9.1", "1")), "not a string compare")
        XCTAssertTrue(v("0.1.0", "2").isNewer(than: v("0.1.0", "1")), "build number breaks ties")
        XCTAssertFalse(v("0.1.0", "1").isNewer(than: v("0.1.0", "1")), "same version defers to the running copy")
        XCTAssertFalse(v("0.1.0", "1").isNewer(than: v("0.1.1", "1")))
        XCTAssertFalse(v("0.1", "1").isNewer(than: v("0.1.0", "1")), "missing components read as zero")
    }

    /// The footer reads the running bundle's Info.plist; nothing about the version is written
    /// into the code. Bump App/Info.plist and the mark follows.
    func testTheVersionComesFromTheBundleNotFromTheCode() throws {
        let made = InstanceVersion(info: ["CFBundleShortVersionString": "9.8.7", "CFBundleVersion": "654"])
        XCTAssertEqual(made.label, "v9.8.7")
        XCTAssertTrue(made.report().hasPrefix("Shut 9.8.7 (654) · macOS "))
        let running = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(InstanceVersion.current.short, running["CFBundleShortVersionString"] as? String ?? "0")
        XCTAssertEqual(InstanceVersion.current.build, running["CFBundleVersion"] as? String ?? "0")
        // And the repo's one source of truth is the plist the release scripts read.
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Info.plist")
        let info = try XCTUnwrap(NSDictionary(contentsOf: plist) as? [String: Any])
        XCTAssertEqual(InstanceVersion(info: info).label, "v" + (try XCTUnwrap(info["CFBundleShortVersionString"] as? String)))
    }

    /// What the footer shows, and what a click puts on the clipboard.
    func testTheVersionMarkAndItsReport() {
        let version = InstanceVersion(short: "0.2.1", build: "3")
        XCTAssertEqual(version.label, "v0.2.1")
        let os = OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 2)
        XCTAssertEqual(version.report(os: os, osBuild: "25G83", model: "Mac16,5"), "Shut 0.2.1 (3) · macOS 26.6.2 (25G83) · Mac16,5")
        XCTAssertEqual(version.report(os: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0), osBuild: "", model: ""),
                       "Shut 0.2.1 (3) · macOS 15.0")
        XCTAssertFalse(InstanceVersion.systemString("hw.model").isEmpty, "this Mac has a model")
        XCTAssertEqual(InstanceVersion.systemString("no.such.key"), "")
    }

    // MARK: What's new

    /// The card's words are the changelog's: a bold title with its sentence, then the points
    /// up to the next heading.
    func testWhatsNewReadsTheChangelogSection() throws {
        let section = """

        **Stay awake.** Close the lid while `something` is working.

        - Reasons, not **timers**.
        - You always know.

        **Also**

        - The main page is rearranged.
        """
        let news = try XCTUnwrap(WhatsNew.parse(section))
        XCTAssertEqual(news.title, "Stay awake")
        XCTAssertEqual(news.lead, "Close the lid while something is working.")
        XCTAssertEqual(news.points, ["Reasons, not timers.", "You always know."], "the second section is a click away")

        let fixOnly = try XCTUnwrap(WhatsNew.parse("\n- Fixed: a crash on launch.\n- Fonts load two ways.\n"))
        XCTAssertEqual(fixOnly.title, "")
        XCTAssertEqual(fixOnly.lead, "Fixed: a crash on launch.")
        XCTAssertEqual(fixOnly.points, ["Fonts load two ways."])
        XCTAssertNil(WhatsNew.parse("Shut 9.9.9"))
        XCTAssertEqual(WhatsNew.claim(of: "Reasons, not timers. Your Mac stays awake while an app is busy."), "Reasons, not timers.")
        XCTAssertEqual(WhatsNew.claim(of: "Only on Macs with a lid."), "Only on Macs with a lid.")
    }

    /// The real 0.3.0 section parses, so the release cannot ship an empty card.
    func testThisVersionsChangelogMakesACard() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let info = try XCTUnwrap(NSDictionary(contentsOf: root.appendingPathComponent("App/Info.plist")) as? [String: Any])
        let version = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        var section = "", on = false
        for line in changelog.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { on = line == "## \(version)"; continue }
            if on { section += line + "\n" }
        }
        XCTAssertFalse(section.isEmpty, "CHANGELOG.md has no section for \(version)")
        let news = try XCTUnwrap(WhatsNew.parse(section), "the \(version) section must make a card")
        XCTAssertFalse(news.lead.isEmpty)
        XCTAssertGreaterThanOrEqual(news.points.count, 1)
    }

    /// Once per version, to people who already had Shut; a new install gets the welcome instead.
    func testWhenWhatsNewIsDue() {
        XCTAssertFalse(WhatsNew.isDue(current: "0.3.0", lastSeen: nil, hasCompletedFirstRun: false), "a new install")
        XCTAssertTrue(WhatsNew.isDue(current: "0.3.0", lastSeen: nil, hasCompletedFirstRun: true), "updating from a version before the card existed")
        XCTAssertTrue(WhatsNew.isDue(current: "0.3.0", lastSeen: "0.2.1", hasCompletedFirstRun: true))
        XCTAssertFalse(WhatsNew.isDue(current: "0.3.0", lastSeen: "0.3.0", hasCompletedFirstRun: true), "never twice")
    }

    /// The hidden way back to the first run is the letter t by itself, never a shortcut
    /// that is already someone else's (Command-T opens the Tuner).
    @MainActor func testTheReplayKeyIsAPlainT() throws {
        func key(_ characters: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                           context: nil, characters: characters, charactersIgnoringModifiers: characters.lowercased(),
                                           isARepeat: false, keyCode: 17))
        }
        XCTAssertTrue(PopoverController.isReplayKey(try key("t")))
        XCTAssertTrue(PopoverController.isReplayKey(try key("T", .shift)))
        XCTAssertFalse(PopoverController.isReplayKey(try key("t", .command)))
        XCTAssertFalse(PopoverController.isReplayKey(try key("r")))
    }
}
