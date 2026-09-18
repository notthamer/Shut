import Combine
import Foundation
import StayAwake

/// The Stay awake switches, backed by UserDefaults like `AppSettings`. Kept apart
/// so the feature can be read, tested and removed as one piece.
@MainActor
public final class StayAwakeSettings: ObservableObject {
    private let defaults: UserDefaults

    /// The master switch. Off until the user has read what it does (`hasConsented`).
    @Published public var isOn: Bool { didSet { defaults.set(isOn, forKey: "stayAwake.isOn") } }
    @Published public var hasConsented: Bool { didSet { defaults.set(hasConsented, forKey: "stayAwake.hasConsented") } }

    // Reasons
    @Published public var whenWorking: Bool { didSet { defaults.set(whenWorking, forKey: "stayAwake.whenWorking") } }
    @Published public var whenDisplayConnected: Bool { didSet { defaults.set(whenDisplayConnected, forKey: "stayAwake.whenDisplay") } }
    @Published public var whenAppsOpen: Bool { didSet { defaults.set(whenAppsOpen, forKey: "stayAwake.whenAppsOpen") } }
    @Published public var pickedApps: [String] { didSet { defaults.set(pickedApps, forKey: "stayAwake.pickedApps") } }

    // Limits
    @Published public var chargerOnly: Bool { didSet { defaults.set(chargerOnly, forKey: "stayAwake.chargerOnly") } }
    @Published public var batteryFloor: Int { didSet { defaults.set(batteryFloor, forKey: "stayAwake.batteryFloor") } }
    @Published public var grace: TimeInterval { didSet { defaults.set(grace, forKey: "stayAwake.grace") } }
    @Published public var respectLowPowerMode: Bool { didSet { defaults.set(respectLowPowerMode, forKey: "stayAwake.lowPower") } }
    @Published public var lockWhenShut: Bool { didSet { defaults.set(lockWhenShut, forKey: "stayAwake.lockWhenShut") } }
    /// Holding Option as the lid comes down flips the decision for that one close.
    @Published public var optionFlips: Bool { didSet { defaults.set(optionFlips, forKey: "stayAwake.optionFlips") } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        isOn = bool("stayAwake.isOn", false)
        hasConsented = bool("stayAwake.hasConsented", false)
        whenWorking = bool("stayAwake.whenWorking", true)
        whenDisplayConnected = bool("stayAwake.whenDisplay", true)
        whenAppsOpen = bool("stayAwake.whenAppsOpen", false)
        pickedApps = defaults.stringArray(forKey: "stayAwake.pickedApps") ?? []
        chargerOnly = bool("stayAwake.chargerOnly", false)
        batteryFloor = defaults.object(forKey: "stayAwake.batteryFloor") as? Int ?? 20
        grace = defaults.object(forKey: "stayAwake.grace") as? TimeInterval ?? 300
        respectLowPowerMode = bool("stayAwake.lowPower", true)
        lockWhenShut = bool("stayAwake.lockWhenShut", true)
        optionFlips = bool("stayAwake.optionFlips", true)
    }

    var limits: HoldLimits {
        HoldLimits(isOn: isOn && hasConsented, chargerOnly: chargerOnly,
                   batteryFloor: min(max(batteryFloor, HoldLimits.batteryFloorRange.lowerBound), HoldLimits.batteryFloorRange.upperBound),
                   grace: grace, respectLowPowerMode: respectLowPowerMode)
    }
}
