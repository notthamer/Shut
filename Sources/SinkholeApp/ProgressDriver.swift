import Foundation
import TransitionKit
import Tuner

/// Turns lid angle (or a spring) into transition progress `p` in 0...1.
///
/// Three modes, per PRD 5.5:
/// - follow: p tracks the lid between start and end angle, through the easing curve.
/// - spring: a spring animates p toward a target (commit "gulp", reverse on reopen,
///   or pour-out from 1 back to 0 with overshoot below 0).
struct ProgressDriver {
    enum Mode: Equatable {
        case follow
        case spring
    }

    var startAngle: Double
    var endAngle: Double
    var curve: TunerBezier = .linear
    /// Below 1.0, crossing this raw progress hands control to a spring that
    /// finishes the close on its own. 1.0 means "follow the lid all the way".
    var commitThreshold: Double = 1.0
    var commitSpring = (response: 0.35, damping: 1.0)

    private(set) var mode: Mode = .follow
    private(set) var spring: Spring?
    private(set) var progress: Double = 0
    private(set) var committed = false

    init(startAngle: Double, endAngle: Double) {
        self.startAngle = startAngle
        self.endAngle = endAngle
    }

    /// Raw 0...1 progress from the lid, before easing.
    func rawProgress(angle: Double) -> Double {
        let span = max(startAngle - endAngle, 1)
        return min(max((startAngle - angle) / span, 0), 1)
    }

    mutating func reset() {
        mode = .follow
        spring = nil
        progress = 0
        committed = false
    }

    mutating func follow() {
        mode = .follow
        spring = nil
        committed = false
    }

    /// Start a spring from the current progress to `target`.
    mutating func animate(to target: Double, response: Double, damping: Double) {
        spring = Spring(response: response, dampingFraction: damping, from: progress, to: target)
        mode = .spring
    }

    /// Jump straight to a value (used to start pour-out from p = 1).
    mutating func set(progress value: Double) {
        progress = value
    }

    var isSpringSettled: Bool { spring?.isSettled ?? true }

    /// Advance one frame. `angle` is only consulted in follow mode.
    @discardableResult
    mutating func step(dt: Double, angle: Double?) -> Double {
        switch mode {
        case .follow:
            guard let angle else { return progress }
            let raw = rawProgress(angle: angle)
            if commitThreshold < 1, raw >= commitThreshold, !committed {
                committed = true
                progress = curve.value(at: raw)
                animate(to: 1, response: commitSpring.response, damping: commitSpring.damping)
                return step(dt: dt, angle: angle)
            }
            progress = curve.value(at: raw)
        case .spring:
            guard var s = spring else { return progress }
            progress = s.step(dt: dt)
            spring = s
        }
        return progress
    }
}
