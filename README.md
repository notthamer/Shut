# Shut.

> **Demo video coming.** Placeholder: _lid closes, the desktop swirls into the notch; lid opens, it pours back out._

Ways to close your Mac. Shut lives in the menu bar and plays a transition on the
built-in display as you close the lid, driven live by the hinge. Pick a style, set
the speed, and tune every dial until it feels exactly right. Open source, MIT,
built in public.

## Styles

| Style | Needs Screen Recording | What it does |
| --- | --- | --- |
| **Sinkhole** | Yes | The desktop swirls and drains into the notch, then pours back out when you unlock. Original to Shut. |
| **Frost** | Yes | The iPhone Duo look: the screen frosts over from the top edge and fades to black. |
| **Fold** | Yes | The desktop turns against the lid, degree for degree, so it stands still while the machine folds away under it. |
| **Curl** | Yes | The top edge rolls over and away, the way a sheet of paper lifts. |
| **Crease** | Yes | A book fold: creases across the middle and the upper half tips away. |
| **Recede** | Yes | Drops straight back into the dark, square to you the whole way. |
| **Slide** | Yes | Slides down out of sight behind the hinge. |
| **Aperture** | No | Iris blades close over the screen. |
| **Shutter** | No | Bars close in from the top and bottom. |
| **Blinds** | No | Slats close down the screen, each shutting from its edges in. |
| **Fade** | No | A plain dim to black. |

Fold, Curl, Crease, Recede, Slide, Aperture, Shutter, Blinds and Fade are ported
from [Bendable](https://github.com/opensourcevillain/Bendable) (MIT, Anti Ltd) and
credited in every file. Every style plays backwards when you open the lid.

## Supported hardware

- Any Apple-silicon MacBook, M1 to current, all sizes, on macOS 14 or later.
- Macs with a lid angle sensor (M2 and later, most M1s) track the hinge live. Macs
  that only report open/closed play the style on a short timeline instead. Shut
  checks what your Mac can do and says so at the top of the popover.
- 13" models without a notch use a small virtual notch for Sinkhole.

Check your sensor: `swift run lidangle-cli` prints the live angle.

## Install from source

```bash
git clone https://github.com/notthamer/shut
cd shut
scripts/build.sh            # → build/Shut.app
open build/Shut.app
```

Or open **`Shut.xcodeproj`** (not the folder or `Package.swift`) in Xcode, make sure
the scheme next to the Run button says **Shut**, and press Run. Releases come as a
DMG from `scripts/package-dmg.sh`.

**Permissions.** Shut asks for nothing at launch. Styles that redraw your desktop
need **Screen Recording** for one still captured as the lid starts to move, never a
stream; the popover explains this only when you pick one of those styles, with an
Allow and a Restart button (macOS checks the permission at launch). Snapshots live
in GPU memory and are released as the transition ends. Nothing is written to disk.

**Keeping the permission across rebuilds.** macOS ties the grant to the app's
signature. With plain "Sign to Run Locally" every build is a new identity. Add your
Apple ID in Xcode (Settings → Accounts) and pick your Personal Team under Signing &
Capabilities, or create `App/Local.xcconfig` with a stable identity. See
`App/Signing.xcconfig`.

## Interface

Everything is in one menu bar popover. Left click the icon.

- **Preview** on the left plays the chosen style on a snapshot of your desktop (a
  drawn stand-in until Screen Recording is granted). Drag under it to move the lid by
  hand, or **Play on screen** to run it full screen.
- **Gallery** of live thumbnails, rendered by the real shaders.
- **Speed**: how much of the lid's travel the effect uses. Fast plays in the last
  twenty degrees; slow spreads it over the whole close.
- **Adjust**: the style's most important dials, and **Animate opening**.
- **Tune everything…** opens the full panel: every dial, versions, Copy and Paste
  JSON, and the Trigger folder (starts-at angle, smoothing, glide).

Right click the icon for a plain menu.

## How the hinge is read

The lid angle sensor reports whole degrees and only changes about ten times a
second, so reading it directly makes any effect pulse. Shut fits a line through
recent readings (position and rate, no lag), passes the result through a 1€ filter
whose cutoff follows the measured rate, and learns your hinge: the closed angle is
the lowest reading ever seen, the open angle follows wherever the lid rests. The
effect then runs in a band above shut, with a small share tracking the whole travel
so something always answers. Nobody types angles. This design comes from Bendable
and is credited in `Sources/LidSensor/`.

## How Sinkhole works

For every pixel the shader asks: *which pixel of the frozen snapshot should be here
right now?* With `s` the sink (bottom centre of the notch), `x` a screen pixel,
`v = x − s`, `d` the distance to the sink as a fraction of the farthest corner, and
`p` the overall progress:

```
q   = clamp(p·(1 + falloff) − falloff·d, 0, 1)   // near the notch leads, corners lag
k   = 1 / (1 − q)^pull                           // contraction: blows up as q → 1
θ   = twist · 2π · q²                            // gentle global swirl
vf  = (v.x · (1 + stretch·q), v.y)               // funnel: squeeze toward the notch
src = s + rotate(vf · k, θ)                      // inverse map; outside = black
```

Motion blur averages samples at slightly smaller `q`, sweeping them along an arc that
tightens toward the notch (`vortex`), done as a smear rather than a rotation because
the notch sits on the top edge and real spin there would pull in the void above the
screen. Content that leaves the screen dissolves over `edge softness`; a hole shaped
to the notch outline opens and widens; a rim glow traces it. On unlock `p` runs from 1
back to 0 and briefly below, which makes `k < 1`: the splash. The full walk-through is
in `Sources/TransitionKit/Shaders/Sinkhole.metal`.

## Tuner

The panel behind **Tune everything…** is a native SwiftUI rebuild of the kind of
live-tuning panel Josh Puckett's [DialKit](https://github.com/joshpuckett/dialkit)
brought to the web. Rows are fill sliders: drag anywhere, click to snap to tenths,
hover a number to type it, arrow keys nudge (⇧ ×10), scroll wheel nudges, double
click a label to reset. Springs have a Time or Physics description with a live
curve; easing curves have draggable handles. Versions save, switch and delete;
Copy puts the JSON on the clipboard; Paste and file drop import.

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

## Presets

Built-in presets ship in the app and as JSON in [`presets/`](presets/). To share
yours, or to add a style, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Command line

```bash
swift run lidangle-cli                  # live angle, rate and progress
swift run lidangle-cli --report         # compatibility report for an issue
swift run lidangle-cli --calibration    # learned closed/open angles after 5 s
swift run lidangle-cli --log angles.csv # timestamp,angle per sample
```

## Testing

`swift test` runs 60+ tests: sensor decoding, the hinge fit, filter, calibration and
band; offscreen renders of every style (identity, darkening, see-through masks); a
GPU probe of the uniform layout; the Tuner panel and the popover rasterised as
images. Set `SHUT_FRAME_DUMP=dir` to get the PNGs. `swift test -c release --filter
BenchmarkTests` prints per-style frame times at full resolution.

## Credits

- [Bendable](https://github.com/opensourcevillain/Bendable), MIT © 2026 Anti Ltd: nine
  of the styles, the hinge fit/filter/calibration design, and much of the popover's
  shape. License in `THIRD_PARTY_LICENSES.md`.
- [DialKit](https://github.com/joshpuckett/dialkit), MIT © 2026 Josh Puckett: the
  design of the tuning panel. No code was copied; the name is not used in code.
- [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) and
  [DuoBook](https://github.com/askmaddyy/DuoBook) for the sensor research. Shut's
  sensor code is written from scratch.
- The many open-source recreations of the iPhone Duo frost, which Frost aims to match.

MIT License.
