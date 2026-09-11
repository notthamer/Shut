import XCTest
@testable import LidSensor

final class LidSensorTests: XCTestCase {
    func testDecodeAngleLittleEndian() {
        XCTAssertEqual(LidAngleDevice.decodeAngle([0x01, 0x5A, 0x00]), 90)
        XCTAssertEqual(LidAngleDevice.decodeAngle([0x01, 0x00, 0x01, 0xFF, 0xFF]), 256)
    }

    func testDecodeRejectsShortReport() {
        XCTAssertNil(LidAngleDevice.decodeAngle([0x01, 0x5A]))
        XCTAssertNil(LidAngleDevice.decodeAngle([]))
    }
}

/// The sensor reports whole degrees; everything here is about getting a usable
/// position and rate out of a signal that coarse. Cases ported from Bendable.
final class AngularFitTests: XCTestCase {
    private func sweep(_ fit: inout AngularFit, from start: Double, rate: Double, duration: TimeInterval,
                       interval: TimeInterval = 1.0 / 120, dither: Double = 0) -> [AngularFit.Estimate] {
        var estimates: [AngularFit.Estimate] = []
        var time = 0.0, lastReported: Double?, step = 0
        while time < duration {
            time += interval; step += 1
            let reported = (start + rate * time + sin(Double(step) * 1.7) * dither).rounded()
            guard reported != lastReported else { continue }
            lastReported = reported
            estimates.append(fit.update(angle: reported, at: time))
        }
        return estimates
    }

    func testRecoversAConstantRateThroughQuantisation() {
        var fit = AngularFit()
        for rate in sweep(&fit, from: 90, rate: -12, duration: 2).suffix(20).map(\.degreesPerSecond) {
            XCTAssertEqual(rate, -12, accuracy: 1.5)
        }
    }

    func testRecoversASlowRateWhereDifferencingWouldNot() {
        var fit = AngularFit()
        for rate in sweep(&fit, from: 60, rate: -3, duration: 6).suffix(8).map(\.degreesPerSecond) {
            XCTAssertEqual(rate, -3, accuracy: 1.0)
        }
    }

    func testDitherDoesNotReverseTheRate() {
        var fit = AngularFit()
        for rate in sweep(&fit, from: 70, rate: -8, duration: 4, dither: 0.4).suffix(30).map(\.degreesPerSecond) {
            XCTAssertLessThan(rate, 0)
            XCTAssertEqual(rate, -8, accuracy: 3)
        }
    }

    func testAStationaryLidReportsNoMovement() {
        var fit = AngularFit()
        var estimate = AngularFit.Estimate(angle: 0, degreesPerSecond: 0)
        for i in 1...8 { estimate = fit.update(angle: 95, at: Double(i)) }
        XCTAssertEqual(estimate.degreesPerSecond, 0, accuracy: 0.2)
        XCTAssertEqual(estimate.angle, 95, accuracy: 0.2)
    }

    func testALongGapRestartsTheFit() {
        var fit = AngularFit()
        _ = sweep(&fit, from: 90, rate: -30, duration: 1)
        let afterGap = fit.update(angle: 20, at: 600)
        XCTAssertEqual(afterGap.degreesPerSecond, 0, accuracy: 0.0001)
        XCTAssertEqual(afterGap.angle, 20, accuracy: 0.0001)
    }
}

final class OneEuroFilterTests: XCTestCase {
    private let interval = 1.0 / 120

    func testDitherIsSuppressedWhileParked() {
        var filter = OneEuroFilter(minCutoff: 3.2, beta: 2.0)
        var time = 0.0, outputs: [Double] = []
        for index in 0..<400 {
            time += interval
            outputs.append(filter.apply(90 + (index % 2 == 0 ? 1 : -1), at: time, speed: 0))
        }
        let tail = outputs.suffix(100)
        XCTAssertLessThan((tail.max() ?? 0) - (tail.min() ?? 0), 0.35)
    }

    func testMovementPassesStraightThrough() {
        var filter = OneEuroFilter(minCutoff: 3.2, beta: 2.0)
        var time = 0.0, value = 90.0, truth = 90.0
        for _ in 0..<200 {
            time += interval; truth -= 40 * interval
            value = filter.apply(truth, at: time, speed: -40)
        }
        XCTAssertEqual(value, truth, accuracy: 0.35)
    }
}

final class OpenReferenceTests: XCTestCase {
    private let step = 1.0 / 60
    private func park(_ reference: inout OpenReference, at angle: Double, for duration: TimeInterval) {
        var elapsed = 0.0
        while elapsed < duration { reference.update(angle: angle, degreesPerSecond: 0, dt: step, closedAngle: 0); elapsed += step }
    }

    func testOpeningWiderIsAdoptedQuickly() {
        var reference = OpenReference(angle: 95)
        park(&reference, at: 125, for: 3)
        XCTAssertEqual(reference.angle, 125, accuracy: 1)
    }

    func testASmallerWorkingAngleIsEventuallyAdopted() {
        var reference = OpenReference(angle: 130)
        park(&reference, at: 100, for: 5)
        XCTAssertEqual(reference.angle, 130, accuracy: 0.5, "five seconds is not a new posture")
        park(&reference, at: 100, for: 20)
        XCTAssertEqual(reference.angle, 100, accuracy: 1.5)
    }

    func testAShutLidNeverBecomesTheDefinitionOfOpen() {
        var reference = OpenReference(angle: 100)
        park(&reference, at: 0, for: 60)
        XCTAssertEqual(reference.angle, 100, accuracy: 0.0001)
    }
}

/// The effect lives in a band just above shut, not across the whole travel.
final class BandTests: XCTestCase {
    private let calibration = HingeCalibration(closedAngle: 0, openAngle: 105)
    private func progress(at angle: Double, band: Double = 45) -> Double {
        1 - calibration.openness(for: angle, bandDegrees: band)
    }

    func testTheEndsAreExact() {
        XCTAssertEqual(progress(at: 105), 0, accuracy: 0.001)
        XCTAssertEqual(progress(at: 0), 1, accuracy: 0.001)
    }

    func testOrdinaryLidAdjustmentsBarelyMoveItButEveryMovementAnswers() {
        var previous = progress(at: 105)
        for angle in stride(from: 104.0, through: 60.0, by: -1.0) {
            let current = progress(at: angle)
            XCTAssertLessThan(current, 0.13, "\(angle)° moved too much")
            XCTAssertGreaterThan(current, previous, "nothing happened at \(angle)°")
            previous = current
        }
    }

    func testTheBulkOfTheEffectIsInsideTheBand() {
        XCTAssertLessThan(progress(at: 45), 0.2)
        XCTAssertGreaterThan(progress(at: 22.5), 0.45)
        XCTAssertGreaterThan(progress(at: 8), 0.8)
    }

    func testAShallowRestingAngleNarrowsTheBandRatherThanSwallowingIt() {
        let shallow = HingeCalibration(closedAngle: 0, openAngle: 50)
        XCTAssertEqual(shallow.animationRange(bandDegrees: 45).upperBound, 37.5, accuracy: 0.001)
        XCTAssertEqual(shallow.openness(for: 50, bandDegrees: 45), 1, accuracy: 0.001)
    }

    func testAWiderBandStartsTheEffectSooner() {
        XCTAssertLessThan(progress(at: 50, band: 30), 0.15)
        XCTAssertGreaterThan(progress(at: 50, band: 80), 0.3)
    }
}

final class HingeNormalizerTests: XCTestCase {
    /// The real sensor: a new whole degree only every ~100 ms, polled at 120 Hz.
    /// Per-tick motion must be small and even, with no bursts when a reading lands.
    func testSlowCloseHasNoBursts() {
        var normalizer = HingeNormalizer(calibration: HingeCalibration(closedAngle: 0, openAngle: 105), smoothing: 0.25, autoCalibrates: false)
        var jumps: [Double] = []
        var previous: Double?
        for i in 0..<720 {
            let t = Double(i) / 120
            let truth = 60 - 8 * t                       // 8°/s, a slow deliberate close
            let reported = (truth + 0.5).rounded(.down)  // whole degrees
            guard let state = normalizer.normalize(HingeSample(angle: reported, lidIsOpen: true, timestamp: t)) else { continue }
            if let p = previous, t > 1 { jumps.append(abs(state.progress - p)) }
            previous = state.progress
        }
        let maxJump = jumps.max()!, mean = jumps.reduce(0, +) / Double(jumps.count)
        XCTAssertLessThan(maxJump, 0.012, "a per-tick burst")
        XCTAssertLessThan(maxJump / max(mean, 1e-6), 8, "motion bunches at readings")
    }

    func testFullCloseIsMonotonicAndEndsShut() {
        var normalizer = HingeNormalizer(calibration: HingeCalibration(closedAngle: 0, openAngle: 105), smoothing: 0.25, autoCalibrates: false)
        var time = 0.0, progresses: [Double] = [], midVelocity = 0.0
        for angle in stride(from: 105.0, through: 0.0, by: -1.5) {
            time += 1.0 / 60
            if let state = normalizer.normalize(HingeSample(angle: angle, lidIsOpen: angle > 1, timestamp: time)) {
                progresses.append(state.progress)
                if abs(angle - 30) < 1 { midVelocity = state.velocity }
            }
        }
        XCTAssertEqual(progresses.first ?? 1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(progresses.last ?? 0, 0.97)
        XCTAssertEqual(progresses, progresses.sorted(), "progress must rise monotonically while closing")
        XCTAssertGreaterThan(midVelocity, 0, "velocity is positive while closing")
    }

    func testLidStateOnlyEdges() {
        var normalizer = HingeNormalizer()
        let open = normalizer.normalize(HingeSample(angle: nil, lidIsOpen: true, timestamp: 1))!
        XCTAssertEqual(open.progress, 0); XCTAssertFalse(open.isClosed)
        let shut = normalizer.normalize(HingeSample(angle: nil, lidIsOpen: false, timestamp: 2))!
        XCTAssertEqual(shut.progress, 1); XCTAssertTrue(shut.isClosed); XCTAssertEqual(shut.direction, .closing)
    }

    func testWorkingAngleIsLearnedAndReachesFullyOpen() {
        var normalizer = HingeNormalizer(calibration: HingeCalibration(closedAngle: 0, openAngle: 135), smoothing: 0.25, autoCalibrates: true)
        var time = 0.0, state: HingeState?
        while time < 30 {
            time += 1.0 / 60
            state = normalizer.normalize(HingeSample(angle: 100, lidIsOpen: true, timestamp: time))
        }
        XCTAssertEqual(state?.progress ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(normalizer.calibration.openAngle, 100, accuracy: 2)
    }
}
