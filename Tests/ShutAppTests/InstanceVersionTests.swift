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
}
