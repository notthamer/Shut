import Foundation

/// Per-machine mapping from sensor degrees to progress. Ported code
/// (MIT, © 2026 Anti Ltd).
///
/// Sensors don't agree on where "closed" sits, and the comfortable open angle
/// differs by model, by person and by hour. So the closed end is a hardware floor
/// learned from the lowest reading ever seen, and the open end follows wherever
/// the lid actually rests (`OpenReference`).
public struct HingeCalibration: Sendable, Equatable, Codable {
    /// Angle at which the lid is physically shut.
    public var closedAngle: Double
    /// Where the lid rests when open, learned by `OpenReference`.
    public var openAngle: Double

    public init(closedAngle: Double, openAngle: Double) {
        self.closedAngle = closedAngle
        self.openAngle = openAngle
    }

    /// Degrees above closed at which the effect starts, when the lid rests high
    /// enough to allow it. This is the "Speed" control: a small band is fast.
    public static let defaultBandDegrees = 45.0
    /// The band always stops this many degrees short of where the lid rests, or
    /// someone who works with the lid barely open finds the effect already applied
    /// at rest. Anything up to that is allowed, so "slow" can mean the whole close.
    public static let restHeadroomDegrees = 6.0
    public static let `default` = HingeCalibration(closedAngle: 0, openAngle: 95)
    /// Angles outside this are sensor noise rather than motion.
    public static let plausibleRange: ClosedRange<Double> = 0...180
    /// Share of the effect that tracks the whole travel rather than only the band.
    /// Kept tiny on purpose: it exists so the app can arm and capture as soon as
    /// the lid moves, not so anything shows. What the user sees starts at the
    /// band, which is what the Speed dial promises.
    public static let fullTravelShare = 0.03

    /// The cap lands on a multiple of this, so the dial stops at a round number
    /// rather than at whatever the lid happens to rest at today minus six.
    public static let capStepDegrees = 5.0

    /// The widest band this lid allows: headroom under the rest angle, rounded
    /// down to a round number.
    public var maximumBandDegrees: Double {
        let travel = max(openAngle - closedAngle, 1)
        let ceiling = travel - Self.restHeadroomDegrees
        return max((ceiling / Self.capStepDegrees).rounded(.down) * Self.capStepDegrees, 5)
    }

    /// Where the effect actually runs, given a requested band.
    public func animationRange(bandDegrees: Double) -> ClosedRange<Double> {
        let band = min(max(bandDegrees, 5), maximumBandDegrees)
        return closedAngle...(closedAngle + band)
    }

    public var isUsable: Bool {
        openAngle - closedAngle >= 20 && Self.plausibleRange.contains(closedAngle)
            && Self.plausibleRange.contains(openAngle)
    }

    /// Openness, 1 = at rest open, 0 = shut. Mostly across the band, partly across
    /// the whole travel. (`HingeState.progress` is 1 minus this.)
    public func openness(for angle: Double, bandDegrees: Double = defaultBandDegrees) -> Double {
        guard isUsable else { return normalize(angle, in: 0...bandDegrees) }
        let banded = normalize(angle, in: animationRange(bandDegrees: bandDegrees))
        let full = normalize(angle, in: closedAngle...openAngle)
        return clamp(banded * (1 - Self.fullTravelShare) + full * Self.fullTravelShare, 0, 1)
    }

    /// Lowers the closed end toward the lowest angle the sensor has ever reported.
    public mutating func observe(angle: Double) {
        guard Self.plausibleRange.contains(angle), angle < closedAngle else { return }
        closedAngle = angle
    }
}

/// Tracks where "fully open" currently is: wherever the lid comes to rest. It
/// moves up readily (opening wider is unambiguous) and down only after a long
/// dwell, so pausing halfway through a close doesn't cancel the effect.
struct OpenReference: Sendable, Equatable {
    static let minimumSpan = 25.0
    static let stillThreshold = 1.5
    /// Must clear the sensor's idle cadence (about one report a second when parked).
    static let maximumSampleGap: TimeInterval = 3
    static let dwellToOpen: TimeInterval = 1.5
    static let dwellToClose: TimeInterval = 6
    static let riseTime: TimeInterval = 0.3
    static let fallTime: TimeInterval = 3

    private(set) var angle: Double
    private var stillFor: TimeInterval = 0

    init(angle: Double) { self.angle = angle }

    mutating func reset(to angle: Double) {
        self.angle = angle
        stillFor = 0
    }

    mutating func update(angle current: Double, degreesPerSecond: Double, dt: TimeInterval, closedAngle: Double) {
        guard dt > 0, dt < Self.maximumSampleGap else { stillFor = 0; return }
        guard abs(degreesPerSecond) < Self.stillThreshold else { stillFor = 0; return }
        // A shut lid, or one in clamshell, must never become the definition of open.
        guard current >= closedAngle + Self.minimumSpan else { stillFor = 0; return }
        stillFor += dt
        if current > angle + 0.5 {
            guard stillFor >= Self.dwellToOpen else { return }
            angle = lerp(angle, current, min(dt / Self.riseTime, 1))
        } else if current < angle - 0.5 {
            guard stillFor >= Self.dwellToClose else { return }
            angle = lerp(angle, current, min(dt / Self.fallTime, 1))
        }
    }
}
