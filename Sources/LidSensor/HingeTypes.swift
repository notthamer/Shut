import Foundation

/// What the current machine can actually tell us about its lid.
public enum HingeCapability: String, Sendable, Equatable, CaseIterable, Codable {
    /// A lid angle sensor is present and streaming degrees.
    case continuousAngle
    /// Only open/closed transitions are observable (some M1s, Intel).
    case lidStateOnly
    /// Not a laptop, or nothing usable was found.
    case unsupported

    public var title: String {
        switch self {
        case .continuousAngle: return "Continuous hinge angle"
        case .lidStateOnly: return "Lid open/close events only"
        case .unsupported: return "No lid detected"
        }
    }

    public var explanation: String {
        switch self {
        case .continuousAngle:
            return "The effect follows the physical hinge angle in real time."
        case .lidStateOnly:
            return "This Mac only reports that the lid opened or closed, so the effect plays on a short timeline instead of tracking the hinge."
        case .unsupported:
            return "No built-in lid was found. Use the preview to try the effects."
        }
    }
}

public enum HingeDirection: String, Sendable, Equatable {
    case opening, closing, still
}

/// A raw provider reading, before validation, calibration or filtering.
public struct HingeSample: Sendable, Equatable {
    /// Degrees between base and lid, or nil when the provider only knows open/closed.
    public var angle: Double?
    public var lidIsOpen: Bool
    public var timestamp: TimeInterval

    public init(angle: Double?, lidIsOpen: Bool, timestamp: TimeInterval) {
        self.angle = angle
        self.lidIsOpen = lidIsOpen
        self.timestamp = timestamp
    }
}

/// The application-facing hinge state. Everything above the hinge layer
/// consumes only this.
///
/// Note the convention: **progress 0 = open, 1 = shut** and velocity is positive
/// while closing. That is the direction every Shut transition animates in, and
/// the opposite of Bendable's "openness".
public struct HingeState: Sendable, Equatable {
    /// Filtered angle in degrees when a real sensor is present.
    public var angle: Double?
    /// 0 = open (above the band), 1 = shut.
    public var progress: Double
    /// Change in `progress` per second, positive while closing.
    public var velocity: Double
    public var direction: HingeDirection
    public var isClosed: Bool
    public var timestamp: TimeInterval
    /// Seconds since the previous reading.
    public var reportInterval: TimeInterval = 0

    public init(angle: Double?, progress: Double, velocity: Double, direction: HingeDirection,
                isClosed: Bool, timestamp: TimeInterval, reportInterval: TimeInterval = 0) {
        self.angle = angle
        self.progress = progress
        self.velocity = velocity
        self.direction = direction
        self.isClosed = isClosed
        self.timestamp = timestamp
        self.reportInterval = reportInterval
    }

    public static let open = HingeState(angle: nil, progress: 0, velocity: 0, direction: .still, isClosed: false, timestamp: 0)
}
