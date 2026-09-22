import Foundation

/// Why the Mac should stay awake with the lid shut. Shut never asks "how long?":
/// it holds while at least one reason is true and lets the Mac sleep when none is.
public struct HoldReason: Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// An app the user allowed is asking macOS to stay awake (an agent, a render, a download).
        case working
        /// An external display is connected.
        case display
        /// An app the user picked is open.
        case appOpen
        /// The user said so, for a while or until they stop it.
        case manual
        /// `shut hold` on the command line.
        case command
    }

    /// Stable while the reason lasts: a bundle identifier, a display name, "manual".
    public let id: String
    public let kind: Kind
    /// What the card, the bar and the closing caption call it: "Cursor", "Studio Display".
    public let title: String
    /// One short clause for the card's second line: "Playing audio".
    public let detail: String?
    /// The command-line tool behind the request, when there is one: "Claude Code"
    /// for a `claude` running in Cursor's terminal. Cosmetic; nil is always fine.
    public let tool: String?
    /// The app's bundle identifier, so the interface can show its icon.
    public let bundleID: String?
    public let since: Date
    /// Manual and command holds can end by themselves.
    public let until: Date?

    public init(id: String, kind: Kind, title: String, detail: String? = nil, tool: String? = nil,
                bundleID: String? = nil, since: Date, until: Date? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.tool = tool
        self.bundleID = bundleID
        self.since = since
        self.until = until
    }
}

/// Why a hold ended, or never started, while reasons were still true. Every one of
/// these is shown to the user in words; none is ever silent.
public enum StopReason: String, Codable, Equatable, Sendable {
    case batteryFloor
    case tooHot
    case timeCap
    case lowPowerMode
    case chargerOnly
    case userLetItSleep
}

public enum ThermalLevel: Int, Comparable, Sendable {
    case nominal, fair, serious, critical
    public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
}

/// The machine's condition, read from the system by `PowerSourceMonitor`.
public struct PowerConditions: Equatable, Sendable {
    public var onCharger: Bool
    /// nil on a Mac with no battery.
    public var batteryPercent: Int?
    public var thermal: ThermalLevel
    public var lowPowerMode: Bool

    public init(onCharger: Bool = true, batteryPercent: Int? = nil, thermal: ThermalLevel = .nominal, lowPowerMode: Bool = false) {
        self.onCharger = onCharger
        self.batteryPercent = batteryPercent
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
    }
}

/// The user's limits. Defaults are the safe ones.
public struct HoldLimits: Equatable, Sendable {
    public var isOn: Bool
    public var chargerOnly: Bool
    /// On battery, at or below this the Mac is allowed to sleep.
    public var batteryFloor: Int
    /// How long to wait after work stops, in case it starts again.
    public var grace: TimeInterval
    public var respectLowPowerMode: Bool
    /// The longest hold on battery. On a charger a desk setup can run all day.
    public var batteryCap: TimeInterval

    public init(isOn: Bool = false, chargerOnly: Bool = false, batteryFloor: Int = 20, grace: TimeInterval = 300,
                respectLowPowerMode: Bool = true, batteryCap: TimeInterval = 8 * 3600) {
        self.isOn = isOn
        self.chargerOnly = chargerOnly
        self.batteryFloor = batteryFloor
        self.grace = grace
        self.respectLowPowerMode = respectLowPowerMode
        self.batteryCap = batteryCap
    }

    public static let batteryFloorRange: ClosedRange<Int> = 5...100
    public static let graceChoices: [TimeInterval] = [60, 300, 900, 1800]
}

public enum HoldState: Equatable, Sendable {
    /// The feature is off.
    case off
    /// On, nothing to hold for: the lid sleeps the Mac as usual.
    case ready
    /// Holding the lid.
    case holding
    /// The work stopped; still holding until the date in case it starts again.
    case grace(until: Date)
    /// Reasons are true but a limit says no.
    case stopped(StopReason)

    /// True when lid-close sleep should be disabled right now.
    public var holdsLid: Bool {
        switch self {
        case .holding, .grace: return true
        case .off, .ready, .stopped: return false
        }
    }
}
