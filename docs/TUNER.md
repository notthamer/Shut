# Tuner

The Tuner is a native SwiftUI live-tuning panel. Rows are fill sliders: drag anywhere, click to snap to tenths,
hover a number to type it, arrow keys nudge (⇧ ×10), scroll wheel nudges, double
click a label to reset. Springs have a Time or Physics description with a live
curve; easing curves have draggable handles. Versions save, switch and delete;
**Copy** (⇧⌘C) puts the JSON on the clipboard; **Paste JSON** and file drop import;
**Reset all** returns to the defaults. The **Trigger** folder holds the raw
starts-at angle, smoothing, glide and Animate opening. The panel hides itself while
a real lid transition plays.

Motion across the panel and the Tuner follows one set of rules: critically
damped springs, a strong ease-out for anything entering or leaving, everything
under 300 ms, feedback on mouse-down for every pressable, nothing animated on a
keyboard shortcut, and Reduce Motion keeping short fades while dropping movement.
Run Shut with `SHUT_MOTION_SCALE=4` in the environment to watch every animation
four times slower.

`Tuner` is a standalone Swift package target with no dependency on the rest of
Shut. Describe your parameters with key paths and the panel builds itself:

```swift
import Tuner

struct GlowParams: TunableParameters {
    var radius = 12.0
    var color = TunerColor.white
    var curve = TunerBezier.easeOut
    var response = 0.4, damping = 0.8

    static let tunerID = "glow"
    static let tunerDisplayName = "Glow"
    static let defaults = GlowParams()
    static let schema = TunerSchema<GlowParams>([
        TunerFolder("Look", [
            .slider(\.radius, "Radius", 0...40, unit: "pt", featured: true, help: "How far the glow spreads."),
            .color(\.color, "Color"),
        ]),
        TunerFolder("Motion", [
            .bezier(\.curve, "Easing"),
            .spring(response: \.response, damping: \.damping, "Spring"),
        ]),
    ])
}

let store = TunerStore<GlowParams>(presets: PresetStore(appName: "MyApp"))
store.onChange = { params in myView.apply(params) }
let panel = TunerPanelController(title: "Glow", content: AnyView(TunerPanelView(store: store)))
panel.registerHotKey()   // ⌃⌥T
panel.show()
```
