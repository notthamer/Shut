import Combine
import Foundation

/// App-level settings that aren't style parameters. Backed by UserDefaults.
@MainActor
public final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published public var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "isEnabled") } }
    @Published public var transitionID: String { didSet { defaults.set(transitionID, forKey: "transitionID") } }
    /// Degrees above shut the effect spans: the Speed control. Small = fast.
    @Published public var bandDegrees: Double { didSet { defaults.set(bandDegrees, forKey: "bandDegrees") } }
    /// 0 = follow the hinge hard, 1 = steadiest.
    @Published public var smoothing: Double { didSet { defaults.set(smoothing, forKey: "smoothing") } }
    @Published public var animateOpening: Bool { didSet { defaults.set(animateOpening, forKey: "animateOpening") } }
    @Published public var showAngleInMenu: Bool { didSet { defaults.set(showAngleInMenu, forKey: "showAngleInMenu") } }
    /// True: a Dock icon at all times. False: menu bar only, with the Dock icon
    /// appearing just while a window is open.
    @Published public var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock") } }
    @Published public var hasCompletedFirstRun: Bool { didSet { defaults.set(hasCompletedFirstRun, forKey: "hasCompletedFirstRun") } }

    public static let defaultBandDegrees = 60.0
    /// The top end is beyond any lid's travel on purpose: the calibration clamps it
    /// to the user's own rest angle, so "slow" means the whole close on every Mac.
    public static let bandRange: ClosedRange<Double> = 20...130

    /// Seconds a timed close takes on Macs without a sensor, from the Speed band.
    public var timedCloseDuration: Double {
        let t = (bandDegrees - Self.bandRange.lowerBound) / (Self.bandRange.upperBound - Self.bandRange.lowerBound)
        return 0.5 + 1.1 * min(max(t, 0), 1)
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: "isEnabled") as? Bool ?? true
        transitionID = defaults.string(forKey: "transitionID") ?? "fold"
        bandDegrees = defaults.object(forKey: "bandDegrees") as? Double ?? Self.defaultBandDegrees
        smoothing = defaults.object(forKey: "smoothing") as? Double ?? 0.25
        animateOpening = defaults.object(forKey: "animateOpening") as? Bool ?? true
        showAngleInMenu = defaults.object(forKey: "showAngleInMenu") as? Bool ?? true
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        hasCompletedFirstRun = defaults.object(forKey: "hasCompletedFirstRun") as? Bool ?? false
    }
}
