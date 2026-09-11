import Foundation

/// How gently corrections are applied when a new reading disagrees with the
/// running estimate. Higher = smoother, slightly laggier.
public enum Smoothing: String, CaseIterable, Codable, Sendable {
    case low, medium, high

    /// Alpha-beta filter gains (position, velocity). Lower gains trust the
    /// prediction more and spread each correction over more readings.
    var gains: (alpha: Double, beta: Double) {
        switch self {
        case .low: return (0.6, 0.35)
        case .medium: return (0.4, 0.2)
        case .high: return (0.25, 0.1)
        }
    }

    /// Output easing after the filter, seconds.
    var outputTimeConstant: Double {
        switch self {
        case .low: return 0.02
        case .medium: return 0.035
        case .high: return 0.05
        }
    }
}

/// Reconstructs a smooth lid angle from a coarse sensor.
///
/// Measured on a 14" MacBook Pro, the sensor's value only changes every ~100 ms
/// and is quantised to whole degrees, however fast it's polled. Reading it
/// directly gives ten steps a second, which looks like pulsing when the screen
/// is being pulled into the notch.
///
/// This is an alpha-beta filter (a fixed-gain Kalman filter for position and
/// velocity), run at the poll rate:
///
/// - Every poll tick *predicts*: angle += velocity · dt.
/// - Every distinct reading *corrects*: the residual between reading and
///   prediction nudges the angle by `alpha` and the velocity by `beta`.
/// - A reading that hasn't changed for a while is also treated as a
///   measurement, so a lid that has stopped is pulled to rest rather than
///   drifting on its last velocity.
///
/// Because velocity is filtered over several readings instead of computed from
/// the last two, the estimate doesn't lurch on every new degree, and the small
/// corrections are further eased on output. Prediction between readings means
/// the result follows the real lid with no perceptible lag.
public struct AngleSmoother {
    public var smoothing: Smoothing
    public private(set) var angle: Double?
    /// Degrees per second, positive = opening.
    public private(set) var velocity: Double = 0

    private var estimate: Double?
    private var lastReadingValue: Double?
    private var lastReadingTime: TimeInterval?
    private var lastTick: TimeInterval?

    /// A reading unchanged for this long counts as a fresh "still here" measurement.
    private let repeatAsMeasurementAfter: TimeInterval = 0.16
    private var lastMeasurementTime: TimeInterval?

    public init(smoothing: Smoothing = .medium) {
        self.smoothing = smoothing
    }

    /// Feed one poll. `rawAngle` may repeat the previous value many times.
    @discardableResult
    public mutating func add(rawAngle: Double, at time: TimeInterval) -> Double {
        guard let previousEstimate = estimate, let previousTick = lastTick else {
            estimate = rawAngle
            angle = rawAngle
            lastTick = time
            lastReadingValue = rawAngle
            lastReadingTime = time
            lastMeasurementTime = time
            return rawAngle
        }
        let dt = min(max(time - previousTick, 1.0 / 1000), 0.1)
        lastTick = time

        // Predict.
        var x = previousEstimate + velocity * dt

        // Correct on a new reading, or on a stale one that has clearly settled.
        let changed = rawAngle != lastReadingValue
        let sinceMeasurement = time - (lastMeasurementTime ?? time)
        if changed || sinceMeasurement > repeatAsMeasurementAfter {
            let (alpha, beta) = smoothing.gains
            let residual = rawAngle - x
            let measurementDt = max(sinceMeasurement, 0.05)
            // Residuals around a degree are just quantisation and get the gentle
            // gains. A big residual means the lid genuinely changed speed (or just
            // started moving), and waiting several readings to believe it would
            // read as lag, so the gains ramp toward 1 as the surprise grows.
            let surprise = min(max((abs(residual) - 1.5) / 6.0, 0), 1)
            let a = alpha + (1 - alpha) * surprise
            let b = beta + (0.7 - beta) * surprise
            x += a * residual
            velocity += b * residual / measurementDt
            if changed {
                lastReadingValue = rawAngle
                lastReadingTime = time
            }
            lastMeasurementTime = time
        }

        // Never predict more than half a degree past what the sensor could have
        // reported without changing; a whole-degree sensor that hasn't moved
        // bounds the truth to ±0.5°.
        if !changed, let last = lastReadingValue, time - (lastReadingTime ?? time) > 0.3 {
            x = min(max(x, last - 0.5), last + 0.5)
            velocity *= 0.9
        }
        estimate = x

        // Ease the published value so the alpha steps are invisible.
        let k = 1 - exp(-dt / smoothing.outputTimeConstant)
        var out = (angle ?? x) + (x - (angle ?? x)) * k
        if abs(out - x) < 0.005 { out = x }
        angle = out
        return out
    }

    public mutating func reset() {
        angle = nil
        velocity = 0
        estimate = nil
        lastReadingValue = nil
        lastReadingTime = nil
        lastTick = nil
        lastMeasurementTime = nil
    }
}
