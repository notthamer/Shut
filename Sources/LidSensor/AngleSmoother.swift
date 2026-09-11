import Foundation

/// How much to smooth corrections when a new sensor reading disagrees with the
/// running estimate. Expressed as a time constant so it feels the same at any
/// poll rate.
public enum Smoothing: String, CaseIterable, Codable, Sendable {
    case low, medium, high

    /// Seconds to blend away ~63% of a correction.
    public var timeConstant: Double {
        switch self {
        case .low: return 0.03
        case .medium: return 0.06
        case .high: return 0.10
        }
    }
}

/// Reconstructs a smooth lid angle from a coarse sensor.
///
/// Measured on a 14" MacBook Pro, the sensor's value only changes every ~100 ms
/// and is quantised to whole degrees, however fast it's polled. Reading it
/// directly gives ten steps a second, which looks like pulsing when the screen
/// is being pulled into the notch. So instead of trusting each sample, this
/// tracker:
///
/// 1. Notes the time and value whenever the reading *changes*.
/// 2. Estimates velocity from the last two changes.
/// 3. Dead-reckons the angle forward between changes at that velocity, capped so
///    a lid that has stopped doesn't keep drifting.
/// 4. Blends the estimate toward each new reading over `smoothing.timeConstant`
///    rather than snapping, so corrections are invisible.
///
/// The result updates every poll tick, and follows the real lid with no
/// perceptible lag because the prediction runs ahead of the stale reading.
public struct AngleSmoother {
    public var smoothing: Smoothing
    public private(set) var angle: Double?
    /// Degrees per second, positive = opening.
    public private(set) var velocity: Double = 0

    private var lastReading: (value: Double, time: TimeInterval)?
    private var previousReading: (value: Double, time: TimeInterval)?
    private var lastTick: TimeInterval?

    /// Readings arrive ~0.1 s apart; predict at most this far past the last one.
    private let maxPrediction: TimeInterval = 0.14
    /// After this long without a change, treat the lid as stopped.
    private let stillAfter: TimeInterval = 0.25

    public init(smoothing: Smoothing = .medium) {
        self.smoothing = smoothing
    }

    /// Feed one poll. `rawAngle` may repeat the previous value many times.
    @discardableResult
    public mutating func add(rawAngle: Double, at time: TimeInterval) -> Double {
        // Step 1–2: track distinct readings and derive velocity from them.
        if lastReading == nil {
            lastReading = (rawAngle, time)
            angle = rawAngle
            lastTick = time
            return rawAngle
        }
        if rawAngle != lastReading!.value {
            previousReading = lastReading
            lastReading = (rawAngle, time)
            if let prev = previousReading {
                let dt = time - prev.time
                if dt > 0.02, dt < 0.6 {
                    velocity = (rawAngle - prev.value) / dt
                }
            }
        }

        let sinceReading = time - lastReading!.time
        let frameDt = max(time - (lastTick ?? time), 1.0 / 1000)
        lastTick = time

        // Step 3: dead-reckon, but decay the velocity once the readings stop
        // changing, which is how a lid at rest looks to this sensor.
        if sinceReading > stillAfter {
            velocity += (0 - velocity) * (1 - exp(-frameDt / 0.08))
        }
        let predicted = lastReading!.value + velocity * min(sinceReading, maxPrediction)

        // Step 4: ease the published angle toward the prediction.
        let alpha = 1 - exp(-frameDt / smoothing.timeConstant)
        var next = (angle ?? predicted) + (predicted - (angle ?? predicted)) * alpha
        if abs(next - predicted) < 0.01 { next = predicted }
        angle = next
        return next
    }

    public mutating func reset() {
        angle = nil
        velocity = 0
        lastReading = nil
        previousReading = nil
        lastTick = nil
    }
}
