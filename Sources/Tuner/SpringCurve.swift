import Foundation

/// Samples a damped spring for the editor's curve preview. Same equations as a
/// runtime spring (stiffness from response, damping from the fraction), kept here
/// so Tuner has no dependency on any animation package.
enum SpringCurve {
    static func trajectory(response: Double, damping: Double, duration: Double = 1.5, samples: Int = 120) -> [Double] {
        let stiffness = pow(2 * Double.pi / max(response, 0.01), 2)
        let c = 2 * damping * sqrt(stiffness)
        var position = 1.0, velocity = 0.0
        let dt = duration / Double(samples - 1)
        var out: [Double] = [position]
        for _ in 1..<samples {
            let sub = 4
            let h = dt / Double(sub)
            for _ in 0..<sub {
                velocity += (-stiffness * position - c * velocity) * h
                position += velocity * h
            }
            out.append(position)
        }
        return out
    }
}
