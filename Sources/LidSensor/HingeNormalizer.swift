import Foundation

/// Turns raw samples into the smoothed, calibrated `HingeState` the app sees.
/// Ported code (MIT, © 2026 Anti Ltd), with progress inverted to Shut's
/// 0 = open, 1 = shut. A plain struct with no I/O so the whole sensor → animation
/// contract can be tested deterministically.
public struct HingeNormalizer {
    /// Above this progress the lid counts as shut.
    public static let closedProgressThreshold = 0.98
    /// Progress-per-second below which motion is reported as `.still`.
    public static let stillVelocityThreshold = 0.02
    private static let directionTimeConstant = 0.09

    public var calibration: HingeCalibration {
        get { HingeCalibration(closedAngle: closedAngle, openAngle: reference.angle) }
        set {
            closedAngle = newValue.closedAngle
            reference.reset(to: newValue.openAngle)
        }
    }
    public var autoCalibrates: Bool
    /// Degrees above closed the effect spans (the Speed control).
    public var bandDegrees: Double = HingeCalibration.defaultBandDegrees
    public var animationRange: ClosedRange<Double> { calibration.animationRange(bandDegrees: bandDegrees) }
    /// 0 = follow the hinge hard, 1 = steadiest.
    public var smoothing: Double { didSet { applySmoothing() } }

    private var filter = OneEuroFilter()
    private var fit = AngularFit()
    private var closedAngle: Double
    private var reference: OpenReference
    private var lastState: HingeState?
    private var lastDirection: HingeDirection = .still
    private var directionVelocity = 0.0
    private var lastTimestamp: TimeInterval?

    public init(calibration: HingeCalibration = .default, smoothing: Double = 0.25, autoCalibrates: Bool = true) {
        closedAngle = calibration.closedAngle
        reference = OpenReference(angle: calibration.openAngle)
        self.smoothing = smoothing
        self.autoCalibrates = autoCalibrates
        applySmoothing()
    }

    private mutating func applySmoothing() {
        let s = clamp(smoothing, 0, 1)
        // Firm while parked so dither across a degree boundary never reaches the
        // screen; wide open the moment it moves so nothing is delayed.
        filter.minCutoff = lerp(4.0, 0.8, s)
        filter.beta = lerp(2.4, 0.9, s)
    }

    public mutating func reset() {
        filter.reset()
        fit.reset()
        reference.reset(to: reference.angle)
        lastState = nil
        lastDirection = .still
        directionVelocity = 0
        lastTimestamp = nil
    }

    /// Returns nil when the sample carries nothing usable.
    public mutating func normalize(_ sample: HingeSample) -> HingeState? {
        guard let rawAngle = sample.angle else { return normalizeLidStateOnly(sample) }
        guard rawAngle.isFinite, HingeCalibration.plausibleRange.contains(rawAngle) else { return lastState }
        if autoCalibrates { closedAngle = min(closedAngle, rawAngle) }

        let estimate = fit.update(angle: rawAngle, at: sample.timestamp)
        let degreesPerSecond = estimate.degreesPerSecond
        let angle = filter.apply(estimate.angle, at: sample.timestamp, speed: degreesPerSecond)
        if autoCalibrates {
            reference.update(angle: angle, degreesPerSecond: degreesPerSecond,
                             dt: lastTimestamp.map { sample.timestamp - $0 } ?? 0, closedAngle: closedAngle)
        }

        let range = animationRange
        let openness = calibration.openness(for: angle, bandDegrees: bandDegrees)
        // Rate in progress units over the band, positive while closing, and not
        // clamped the way progress is, so a lid moving above the band still reports
        // that it is moving (that is what lets the desktop be captured early).
        let span = max(range.upperBound - range.lowerBound, 1)
        let velocity = -degreesPerSecond / span

        var reportInterval: TimeInterval = 0
        if let previous = lastTimestamp, sample.timestamp > previous {
            let dt = sample.timestamp - previous
            reportInterval = dt
            directionVelocity = lerp(directionVelocity, velocity, dt / (Self.directionTimeConstant + dt))
        } else if lastTimestamp == nil {
            directionVelocity = velocity
        }
        lastTimestamp = sample.timestamp
        let direction = Self.direction(velocity: directionVelocity, previous: lastDirection)
        lastDirection = direction

        let progress = 1 - openness
        let state = HingeState(angle: angle, progress: progress, velocity: velocity, direction: direction,
                               isClosed: progress >= Self.closedProgressThreshold || !sample.lidIsOpen,
                               timestamp: sample.timestamp, reportInterval: reportInterval)
        lastState = state
        return state
    }

    private mutating func normalizeLidStateOnly(_ sample: HingeSample) -> HingeState? {
        let progress: Double = sample.lidIsOpen ? 0 : 1
        let previous = lastState?.progress ?? progress
        let direction: HingeDirection = progress > previous ? .closing : (progress < previous ? .opening : .still)
        lastDirection = direction
        lastTimestamp = sample.timestamp
        let state = HingeState(angle: nil, progress: progress, velocity: 0, direction: direction,
                               isClosed: !sample.lidIsOpen, timestamp: sample.timestamp)
        lastState = state
        return state
    }

    private static func direction(velocity: Double, previous: HingeDirection) -> HingeDirection {
        if velocity > stillVelocityThreshold { return .closing }
        if velocity < -stillVelocityThreshold { return .opening }
        // Hysteresis: hold the previous direction through the dead band.
        return abs(velocity) > stillVelocityThreshold / 2 ? previous : .still
    }
}
