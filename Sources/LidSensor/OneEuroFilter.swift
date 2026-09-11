import Foundation

/// One Euro filter (Casiez, Roussel & Vogel, 2012), as used in Bendable (MIT,
/// © 2026 Anti Ltd). A fixed low-pass either lags during fast movement or leaves
/// jitter at rest; this one raises its own cutoff with measured speed: rock steady
/// when the lid is parked, transparent when it is being moved by hand.
///
/// The speed is supplied from `AngularFit` rather than differentiated here: on a
/// signal quantised to whole degrees the filter's own derivative is worthless.
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double

    private var lastValue: Double?
    private var lastTimestamp: TimeInterval?

    init(minCutoff: Double = 1.0, beta: Double = 0.35) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    mutating func reset() {
        lastValue = nil
        lastTimestamp = nil
    }

    mutating func apply(_ value: Double, at timestamp: TimeInterval, speed: Double) -> Double {
        guard let previous = lastValue, let previousTime = lastTimestamp else {
            lastValue = value
            lastTimestamp = timestamp
            return value
        }
        let dt = timestamp - previousTime
        guard dt > 0 else { return previous }
        let cutoff = minCutoff + beta * abs(speed)
        let tau = 1 / (2 * .pi * max(cutoff, 0.0001))
        let alpha = 1 / (1 + tau / dt)
        let filtered = alpha * value + (1 - alpha) * previous
        lastValue = filtered
        lastTimestamp = timestamp
        return filtered
    }
}
