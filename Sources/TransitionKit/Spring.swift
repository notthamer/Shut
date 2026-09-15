import Foundation

/// A damped spring in SwiftUI's vocabulary: `response` is the period in seconds
/// and `dampingFraction` is 1 for critically damped, below 1 for overshoot.
///
/// Integrated with semi-implicit Euler in fixed substeps so it stays stable when
/// the display link hiccups. Used for the commit "gulp", the reverse-on-reopen,
/// and the pour-out splash.
public struct Spring {
    public var response: Double
    public var dampingFraction: Double
    public var position: Double
    public var velocity: Double = 0
    public var target: Double

    public init(response: Double, dampingFraction: Double, from position: Double, to target: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.position = position
        self.target = target
    }

    /// True once the spring has settled within a small tolerance.
    public var isSettled: Bool {
        abs(position - target) < 0.0005 && abs(velocity) < 0.005
    }

    @discardableResult
    public mutating func step(dt: Double) -> Double {
        let stiffness = pow(2 * Double.pi / max(response, 0.01), 2)
        let damping = 2 * dampingFraction * sqrt(stiffness)
        let substeps = max(1, Int(ceil(dt / 0.004)))
        let h = dt / Double(substeps)
        for _ in 0..<substeps {
            let force = -stiffness * (position - target) - damping * velocity
            velocity += force * h
            position += velocity * h
        }
        if isSettled { position = target; velocity = 0 }
        return position
    }

    /// Samples the spring's trajectory for a curve preview, without mutating.
    public func trajectory(duration: Double, samples: Int) -> [Double] {
        var copy = self
        let dt = duration / Double(max(samples - 1, 1))
        return (0..<samples).map { i in
            if i > 0 { copy.step(dt: dt) }
            return copy.position
        }
    }
}
