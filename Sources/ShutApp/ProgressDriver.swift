import Foundation
import TransitionKit
import Tuner

/// Turns hinge progress (or a spring, or a timeline) into the progress a style
/// renders, 0 = open, 1 = shut.
///
/// - follow: tracks `HingeState.progress` through the style's easing curve, with a
///   short per-frame glide. Works in both directions, so reopening the lid simply
///   plays the style backwards.
/// - spring: animates toward a target (commit "gulp", pour-out from 1 back to 0).
/// - timed: a fixed-duration ease, for Macs that only report open/closed.
struct ProgressDriver {
    enum Mode: Equatable { case follow, spring, timed }

    var curve: TunerBezier = .linear
    /// Below 1.0, crossing this hinge progress hands control to a spring that
    /// finishes the close on its own. 1.0 means "follow the lid all the way".
    var commitThreshold: Double = 1.0
    var commitSpring = (response: 0.35, damping: 1.0)
    /// Per-frame glide time constant in follow mode.
    var followLag: Double = 0.03

    private(set) var mode: Mode = .follow
    private(set) var spring: Spring?
    private(set) var progress: Double = 0
    private(set) var committed = false
    private var tween: (from: Double, to: Double, duration: Double, elapsed: Double)?

    init() {}

    mutating func reset() {
        mode = .follow
        spring = nil
        tween = nil
        progress = 0
        committed = false
    }

    mutating func follow() {
        mode = .follow
        spring = nil
        tween = nil
        committed = false
    }

    mutating func animate(to target: Double, response: Double, damping: Double) {
        spring = Spring(response: response, dampingFraction: damping, from: progress, to: target)
        tween = nil
        mode = .spring
    }

    /// Fixed-duration ease-in-out from the current progress to `target`.
    mutating func timed(to target: Double, duration: Double) {
        tween = (progress, target, max(duration, 0.05), 0)
        spring = nil
        mode = .timed
    }

    mutating func set(progress value: Double) {
        progress = value
    }

    var isSettled: Bool {
        switch mode {
        case .follow: return true
        case .spring: return spring?.isSettled ?? true
        case .timed: return tween.map { $0.elapsed >= $0.duration - 1e-6 } ?? true
        }
    }

    /// Advance one frame. `hinge` is `HingeState.progress`, consulted in follow mode.
    @discardableResult
    mutating func step(dt: Double, hinge: Double?) -> Double {
        switch mode {
        case .follow:
            guard let raw = hinge else { return progress }
            if commitThreshold < 1, raw >= commitThreshold, !committed {
                committed = true
                progress = curve.value(at: raw)
                animate(to: 1, response: commitSpring.response, damping: commitSpring.damping)
                return step(dt: dt, hinge: hinge)
            }
            let target = curve.value(at: raw)
            let alpha = followLag > 0 ? 1 - exp(-dt / followLag) : 1
            progress += (target - progress) * alpha
            if abs(target - progress) < 0.0005 { progress = target }
        case .spring:
            guard var s = spring else { return progress }
            progress = s.step(dt: dt)
            spring = s
        case .timed:
            guard var t = tween else { return progress }
            t.elapsed = min(t.elapsed + dt, t.duration)
            let x = t.elapsed / t.duration
            let eased = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
            progress = t.from + (t.to - t.from) * eased
            tween = t
        }
        return progress
    }
}
