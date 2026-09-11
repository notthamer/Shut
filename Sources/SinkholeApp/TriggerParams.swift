import LidSensor
import Tuner

/// PRD 4.5 "Trigger (shared)": how the lid angle becomes progress. Lives in
/// Tuner like everything else so it can be tuned live and saved in presets.
struct TriggerParams: TunableParameters {
    var startAngle: Double = 80      // degrees; transition begins below this
    var endAngle: Double = 12        // degrees; fully complete (calibrate with lidangle-cli)
    var smoothing: Smoothing = .medium
    var followLag: Double = 0.03     // seconds; glide time constant toward the lid
    var prediction: Double = 0.0     // extra seconds of velocity look-ahead (sensor tracker already predicts)

    static let tunerID = "trigger"
    static let tunerDisplayName = "Trigger"
    static let defaults = TriggerParams()
    static let schema = TunerSchema<TriggerParams>([
        TunerFolder("Trigger", [
            .slider(\.startAngle, "Start angle", 40...110, step: 1, unit: "°", decimals: 0),
            .slider(\.endAngle, "Fully complete angle", 0...35, step: 1, unit: "°", decimals: 0),
            .segmented(\.smoothing, "Smoothing"),
            .slider(\.followLag, "Glide", 0...0.15, step: 0.005, unit: "s", decimals: 3),
            .slider(\.prediction, "Look-ahead", 0...0.1, step: 0.005, unit: "s", decimals: 3),
        ]),
    ])
}
