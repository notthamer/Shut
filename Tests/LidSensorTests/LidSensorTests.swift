import XCTest
@testable import LidSensor

final class LidSensorTests: XCTestCase {
    func testDecodeAngleLittleEndian() {
        // report ID 1, angle 0x005A = 90°
        XCTAssertEqual(LidAngleDevice.decodeAngle([0x01, 0x5A, 0x00]), 90)
        // 0x0100 = 256, proves byte order
        XCTAssertEqual(LidAngleDevice.decodeAngle([0x01, 0x00, 0x01, 0xFF, 0xFF]), 256)
    }

    func testDecodeRejectsShortReport() {
        XCTAssertNil(LidAngleDevice.decodeAngle([0x01, 0x5A]))
        XCTAssertNil(LidAngleDevice.decodeAngle([]))
    }

    /// Simulates the real sensor: value changes every 100 ms in whole degrees
    /// while we poll at 120 Hz. The output must move every tick, not in steps.
    func testSmootherReconstructsMotionBetweenReadings() {
        var smoother = AngleSmoother(smoothing: .medium)
        let closingSpeed = -100.0  // °/s
        var biggestJump = 0.0
        var previous: Double?
        var maxLagBehindTruth = 0.0
        for i in 0..<120 {
            let t = Double(i) / 120
            let truth = 90 + closingSpeed * t
            let reported = (90 + closingSpeed * (floor(t * 10) / 10)).rounded()  // 10 Hz, whole degrees
            let out = smoother.add(rawAngle: reported, at: t)
            if let p = previous, t > 0.3 {
                biggestJump = max(biggestJump, abs(out - p))
                maxLagBehindTruth = max(maxLagBehindTruth, abs(out - truth))
            }
            previous = out
        }
        // Raw would jump 10° every 12th tick; the tracker should move ~1° per tick.
        XCTAssertLessThan(biggestJump, 1.6)
        XCTAssertLessThan(maxLagBehindTruth, 8.0, "prediction keeps it close to the true lid angle")
        XCTAssertLessThan(smoother.velocity, -70)
    }

    func testSmootherStopsWhenReadingsStop() {
        var smoother = AngleSmoother()
        var t = 0.0
        for i in 0..<60 {  // closing for half a second
            t = Double(i) / 120
            smoother.add(rawAngle: (90 - 100 * floor(t * 10) / 10).rounded(), at: t)
        }
        let stoppedAt = smoother.angle!
        for i in 60..<240 {  // lid holds still for 1.5 s: same reading repeats
            t = Double(i) / 120
            smoother.add(rawAngle: 40, at: t)
        }
        XCTAssertEqual(smoother.angle!, 40, accuracy: 0.6, "settles on the held reading")
        XCTAssertLessThan(abs(smoother.velocity), 2)
        XCTAssertLessThan(abs(stoppedAt - 40), 12, "prediction never runs far past the last reading")
    }

    func testSmootherFirstSampleIsExact() {
        var smoother = AngleSmoother()
        XCTAssertEqual(smoother.add(rawAngle: 72, at: 1), 72)
        XCTAssertEqual(smoother.velocity, 0)
    }
}

extension LidSensorTests {
    /// A slow close: 1° every 250 ms. Per-tick motion must stay tiny and even,
    /// with no bursts when a reading lands.
    func testSlowCloseHasNoBursts() {
        var smoother = AngleSmoother(smoothing: .medium)
        var jumps: [Double] = []
        var previous: Double?
        for i in 0..<600 {
            let t = Double(i) / 120
            let reported = (90 - floor(t * 4)).rounded()   // 4 Hz, 1° steps
            let out = smoother.add(rawAngle: reported, at: t)
            if let p = previous, t > 1 { jumps.append(abs(out - p)) }
            previous = out
        }
        let maxJump = jumps.max()!
        let meanJump = jumps.reduce(0, +) / Double(jumps.count)
        XCTAssertLessThan(maxJump, 0.25, "no per-tick burst bigger than a quarter degree")
        XCTAssertLessThan(maxJump / max(meanJump, 0.0001), 6, "motion is spread evenly, not bunched at readings")
    }
}
