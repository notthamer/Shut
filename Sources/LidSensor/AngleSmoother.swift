import Foundation

/// How aggressively to smooth the raw sensor readings.
///
/// Expressed as a time constant rather than a fixed per-sample alpha, so the
/// smoothing feels the same whether we're polling at 10 Hz or 120 Hz.
public enum Smoothing: String, CaseIterable, Codable, Sendable {
    case low, medium, high

    /// Seconds for the smoothed value to cover ~63% of a step change.
    public var timeConstant: Double {
        switch self {
        case .low: return 0.015
        case .medium: return 0.035
        case .high: return 0.08
        }
    }
}

/// Exponential smoothing plus a velocity estimate.
///
/// The raw sensor is quantised to whole degrees and can jitter by ±1° at rest.
/// A short EMA hides that jitter without adding perceptible lag during a close,
/// which takes on the order of half a second.
public struct AngleSmoother {
    public var smoothing: Smoothing
    public private(set) var angle: Double?
    public private(set) var velocity: Double = 0  // degrees per second, positive = opening
    private var lastTimestamp: TimeInterval?

    public init(smoothing: Smoothing = .medium) {
        self.smoothing = smoothing
    }

    /// Feed one raw sample. Returns the smoothed angle.
    @discardableResult
    public mutating func add(rawAngle: Double, at timestamp: TimeInterval) -> Double {
        guard let previous = angle, let previousTime = lastTimestamp else {
            angle = rawAngle
            lastTimestamp = timestamp
            velocity = 0
            return rawAngle
        }
        let dt = max(timestamp - previousTime, 1.0 / 1000)
        let alpha = 1 - exp(-dt / smoothing.timeConstant)
        let next = previous + alpha * (rawAngle - previous)

        // Velocity is smoothed a little more than the angle so it doesn't flip sign
        // on every quantisation step while the lid is nearly still.
        let instantaneous = (next - previous) / dt
        let velocityAlpha = 1 - exp(-dt / (smoothing.timeConstant * 2))
        velocity += velocityAlpha * (instantaneous - velocity)

        angle = next
        lastTimestamp = timestamp
        return next
    }

    public mutating func reset() {
        angle = nil
        velocity = 0
        lastTimestamp = nil
    }
}
