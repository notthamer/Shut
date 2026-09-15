import Foundation

/// Fits a straight line through recent readings, giving both where the lid is and
/// how fast it is turning. Ported code (MIT, © 2026 Anti Ltd).
///
/// Differencing consecutive readings is the obvious way to get a rate and it is
/// close to useless here: the sensor reports whole degrees, so every estimate is
/// either zero or one-over-the-interval. A least-squares line uses every reading at
/// once: quantisation averages out, dither cancels, and the slope is steady enough
/// to advance an animation frame by frame. The same fit gives the position at the
/// newest reading's own timestamp, so unlike a low-pass filter it costs no delay.
///
/// The weighting is exponential rather than a sliding window, because a window has
/// an edge and every reading that falls off it shifts the fit a little.
struct AngularFit {
    struct Estimate {
        var angle: Double
        var degreesPerSecond: Double
    }

    /// Effective memory follows the speed of the lid: scaled to hold roughly this
    /// much travel, so it always spans a couple of degree boundaries.
    static let degreesOfMemory = 2.2
    static let shortestMemory: TimeInterval = 0.05
    static let longestMemory: TimeInterval = 0.4

    static func memory(forRate rate: Double) -> TimeInterval {
        guard abs(rate) > 0.001 else { return longestMemory }
        return clamp(degreesOfMemory / abs(rate), shortestMemory, longestMemory)
    }

    /// The true angle is always within a degree of the last reading; holding the
    /// fit to that stops it running on after the lid stops.
    static let maximumDeviation = 1.0
    /// A gap longer than this means the lid may have moved unobserved; start again.
    static let maximumGap: TimeInterval = 1.0

    private var weight = 0.0
    private var sumTime = 0.0
    private var sumTimeSquared = 0.0
    private var sumAngle = 0.0
    private var sumTimeAngle = 0.0
    private var lastTimestamp: TimeInterval?
    private var lastRate = 0.0

    mutating func reset() {
        weight = 0; sumTime = 0; sumTimeSquared = 0; sumAngle = 0; sumTimeAngle = 0
        lastTimestamp = nil; lastRate = 0
    }

    mutating func update(angle: Double, at timestamp: TimeInterval) -> Estimate {
        guard let previous = lastTimestamp else {
            start(angle: angle, at: timestamp)
            return Estimate(angle: angle, degreesPerSecond: 0)
        }
        let elapsed = timestamp - previous
        guard elapsed > 0 else {
            return Estimate(angle: currentAngle(fallback: angle), degreesPerSecond: lastRate)
        }
        guard elapsed < Self.maximumGap else {
            start(angle: angle, at: timestamp)
            return Estimate(angle: angle, degreesPerSecond: 0)
        }
        // Age the accumulated fit, then move its origin to the new reading so the
        // arithmetic stays in small numbers however long the app has run.
        let decay = exp(-elapsed / Self.memory(forRate: lastRate))
        weight *= decay
        sumTime *= decay
        sumTimeSquared *= decay
        sumAngle *= decay
        sumTimeAngle *= decay
        sumTimeSquared += -2 * elapsed * sumTime + elapsed * elapsed * weight
        sumTime -= elapsed * weight
        sumTimeAngle -= elapsed * sumAngle
        weight += 1
        sumAngle += angle
        lastTimestamp = timestamp

        let determinant = weight * sumTimeSquared - sumTime * sumTime
        guard determinant > 1e-9 else {
            return Estimate(angle: currentAngle(fallback: angle), degreesPerSecond: lastRate)
        }
        lastRate = (weight * sumTimeAngle - sumTime * sumAngle) / determinant
        let fitted = clamp(currentAngle(fallback: angle), angle - Self.maximumDeviation, angle + Self.maximumDeviation)
        return Estimate(angle: fitted, degreesPerSecond: lastRate)
    }

    private func currentAngle(fallback: Double) -> Double {
        guard weight > 0 else { return fallback }
        return (sumAngle - lastRate * sumTime) / weight
    }

    private mutating func start(angle: Double, at timestamp: TimeInterval) {
        weight = 1; sumTime = 0; sumTimeSquared = 0; sumAngle = angle; sumTimeAngle = 0
        lastTimestamp = timestamp; lastRate = 0
    }
}
