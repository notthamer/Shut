import Combine
import Foundation
import LidSensor

/// App-level settings that aren't transition parameters. Backed by UserDefaults.
@MainActor
public final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published public var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "isEnabled") } }
    @Published public var transitionID: String { didSet { defaults.set(transitionID, forKey: "transitionID") } }
    @Published public var startAngle: Double { didSet { defaults.set(startAngle, forKey: "startAngle") } }
    @Published public var endAngle: Double { didSet { defaults.set(endAngle, forKey: "endAngle") } }
    @Published public var smoothing: Smoothing { didSet { defaults.set(smoothing.rawValue, forKey: "smoothing") } }
    @Published public var showAngleInMenu: Bool { didSet { defaults.set(showAngleInMenu, forKey: "showAngleInMenu") } }

    /// PRD 4.5 defaults. End angle 12° is the fallback until calibrated with lidangle-cli.
    public static let defaultStartAngle = 95.0
    public static let defaultEndAngle = 10.0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: "isEnabled") as? Bool ?? true
        transitionID = defaults.string(forKey: "transitionID") ?? "notchDrain"
        startAngle = defaults.object(forKey: "startAngle") as? Double ?? Self.defaultStartAngle
        endAngle = defaults.object(forKey: "endAngle") as? Double ?? Self.defaultEndAngle
        smoothing = Smoothing(rawValue: defaults.string(forKey: "smoothing") ?? "") ?? .medium
        showAngleInMenu = defaults.object(forKey: "showAngleInMenu") as? Bool ?? true
    }
}
