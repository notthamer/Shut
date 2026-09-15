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
}
