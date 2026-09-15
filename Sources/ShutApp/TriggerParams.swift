import LidSensor
import Tuner

/// How the lid becomes progress. Lives in Tuner like everything else so it can be
/// tuned live and saved in presets. The closed and open angles themselves are
/// learned automatically; nobody types them.
struct TriggerParams: TunableParameters {
    /// Degrees above shut the effect spans. This is the popover's Speed slider.
    var startAngle: Double = 45
    var smoothing: Double = 0.25
    var glide: Double = 0.03
    var animateOpening = true

    static let tunerID = "trigger"
    static let tunerDisplayName = "Trigger"
    static let defaults = TriggerParams()
    static let schema = TunerSchema<TriggerParams>([
        TunerFolder("Trigger", [
            .slider(\.startAngle, "Starts at", 20...100, step: 1, unit: "°", decimals: 0, featured: true,
                    help: "How far above shut the effect begins in earnest. Less is faster."),
            .slider(\.smoothing, "Smoothing", 0...1, help: "More is steadier and slightly slower to answer. Less follows the hinge harder."),
            .slider(\.glide, "Glide", 0...0.12, step: 0.005, unit: "s", decimals: 3, help: "Per-frame easing toward the hinge. Hides the sensor's steps."),
            .toggle(\.animateOpening, "Animate opening"),
        ]),
    ])
}
