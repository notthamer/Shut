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

    func testSmootherConvergesAndReportsVelocity() {
        var smoother = AngleSmoother(smoothing: .medium)
        var t = 0.0
        smoother.add(rawAngle: 90, at: t)
        // Close the lid at 100°/s for half a second, sampled at 120 Hz.
        for _ in 0..<60 {
            t += 1.0 / 120
            smoother.add(rawAngle: 90 - 100 * t, at: t)
        }
        XCTAssertLessThan(smoother.velocity, -80, "velocity should track closing direction")
        XCTAssertEqual(smoother.angle!, 40, accuracy: 6, "smoothed angle lags only a few degrees")
    }

    func testSmootherFirstSampleIsExact() {
        var smoother = AngleSmoother()
        XCTAssertEqual(smoother.add(rawAngle: 72, at: 1), 72)
        XCTAssertEqual(smoother.velocity, 0)
    }
}
