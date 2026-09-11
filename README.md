# Sinkhole

> **Demo video coming.** Placeholder: _lid closes, desktop swirls into the notch._

Lid transitions for MacBook. Close the lid and the screen drains into the notch;
unlock and it pours back out. Open source, MIT, built in public.

## Two transitions

- **Notch Drain** — as the lid closes, the desktop spirals inward and funnels up
  into the notch, darkening as it goes, with a faint glow around the rim. On unlock
  it pours back out with a springy overshoot. Original to this project.
- **Frost** — the classic iPhone Duo look. The image stays put, frosts over from the
  top edge toward the hinge, and fades to black.

Both follow the physical lid angle live, and every parameter is tunable in **Tuner**,
a floating control panel with a preview that plays on a snapshot of your desktop.

## Supported hardware

- Apple silicon MacBooks whose lid angle sensor is readable (most 2021+ MacBook Pro
  and MacBook Air models). Verified on a 14" MacBook Pro (M2 Pro).
- macOS 14 Sonoma or later.
- On Macs without a notch, a small pill-shaped "virtual notch" fades in so the drain
  has somewhere to go. Without a readable sensor, Tuner and the preview still work.

Check your sensor: `swift run lidangle-cli` prints the live angle.

## Install from source

```bash
git clone https://github.com/notthamer/sinkhole
cd sinkhole
scripts/build.sh            # → build/Sinkhole.app
open build/Sinkhole.app
```

Or open **`Sinkhole.xcodeproj`** (not the folder or `Package.swift`) in Xcode, make sure
the scheme next to the Run button says **Sinkhole**, and press Run. The `lidangle-cli`
and `sinkhole` schemes are the command-line tools, not the app.

Sinkhole needs **Screen Recording** permission (System Settings → Privacy & Security)
to snapshot the desktop. Snapshots live in GPU memory only and are released the
moment a transition ends; nothing is ever written to disk.

**Keeping the permission across rebuilds.** macOS ties the grant to the app's code
signature. With plain "Sign to Run Locally" every build is a new identity and the
switch resets. Either add your Apple ID in Xcode (Settings → Accounts) and pick
your Personal Team under Signing & Capabilities, or create `App/Local.xcconfig`
with `CODE_SIGN_IDENTITY = Sinkhole Dev` after adding a self-signed code-signing
certificate of that name in Keychain Access. See `App/Signing.xcconfig`.

## How Notch Drain works

The shader answers one question for every pixel: *which pixel of the frozen
snapshot should be here right now?* Everything else is that mapping, tuned.

With `s` the sink (bottom centre of the notch), `x` a screen pixel, `v = x − s`,
`d` the distance to the sink as a fraction of the farthest corner, and `p` the
overall progress:

```
q   = clamp(p·(1 + falloff) − falloff·d, 0, 1)   // near the notch leads, corners lag
k   = 1 / (1 − q)^pull                           // contraction: blows up as q → 1
θ   = twist · 2π · q²                            // swirl winds up as content drains
vf  = (v.x · (1 + stretch·q), v.y)               // funnel: squeeze toward the notch
src = s + rotate(vf · k, θ)                      // inverse map; outside = black
```

Motion blur averages a few samples at slightly smaller `q` (where this pixel's
content just was), sweeping them along an arc that tightens toward the notch: that
arc is the whirlpool (`vortex`). It is done as a smear rather than a rotation on
purpose, because the notch sits on the top edge of the screen and any real spin
there would pull in the void above the display. Content that leaves the screen
dissolves over `edge softness` points instead of being cut off, red and blue read
from slightly different radii for a little chromatic fringe, and a glow ring
around the notch peaks mid-transition. During pour-out, `p` runs from 1 back to 0
and briefly below, which makes `k < 1` and pushes the desktop past its normal
size: the splash.

The lid sensor itself only updates ten times a second in whole degrees, so
`LidSensor` reconstructs a smooth angle by dead-reckoning from the lid's velocity
between readings. Without that, the drain pulses.

The full walk-through is in `Sources/TransitionKit/Shaders/NotchDrain.metal`.

## Tuner

Menu bar → **Open Tuner**, or **⌃⌥T** from anywhere.

- The preview at the top plays on a snapshot of your desktop. Scrub, **Play close**,
  **Play pour-out**, or flip **Follow lid** to drive it from the real sensor.
- Parameters are grouped into folders with a **Reset** per folder. Controls include
  sliders, toggles, a colour picker, a spring editor with a live curve, and a Bézier
  easing editor with draggable handles.
- **Presets**: save, duplicate, delete, **Copy JSON**, **Paste JSON**, or drop a
  `.json` file on the panel. Presets live in
  `~/Library/Application Support/Sinkhole/Presets/`.
- The panel hides itself while a real lid transition plays.

### Using Tuner in your own app

`Tuner` is a standalone Swift package target with no dependency on the rest of
Sinkhole. Describe your parameters with key paths and the panel builds itself:

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
            .slider(\.radius, "Radius", 0...40, unit: "pt"),
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

let panel = TunerPanelController(title: "Tuner",
                                 content: AnyView(TunerPanelView(store: store) { MyPreview() }))
panel.registerHotKey()   // ⌃⌥T
panel.show()
```

Values persist in `UserDefaults` under `tuner.<tunerID>`. Presets are plain JSON.

## Presets

Built-in presets ship in the app and as JSON in [`presets/`](presets/). To share
yours, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Command line

```bash
swift run lidangle-cli                  # live angle
swift run lidangle-cli --report         # compatibility report for an issue
swift run lidangle-cli --log angles.csv # timestamp,angle per sample
swift run lidangle-cli --debug          # raw HID report bytes
```

## Testing

Automated: `swift test` (sensor decoding, easing, springs, presets, and offscreen
renders of every transition; set `SINKHOLE_FRAME_DUMP=dir` to get PNGs).

Manual, before a release:

- 50 lid close/open cycles with each transition: no stuck overlay.
- Reopen the lid before sleep: the transition reverses and clears.
- Sleep from the lid and from the Apple menu, with and without a password on wake:
  the desktop pours out after unlock, and there is never a black screen for more
  than 1.5 s while unlocked.
- Console.app, subsystem `com.sinkhole.app`, shows every lock/unlock event.

## Credits

- [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) for
  the research into the lid angle HID sensor. Sinkhole's sensor code is written from
  scratch.
- Josh Puckett's DialKit, the inspiration for Tuner.
- The many open-source recreations of the iPhone Duo frost transition, which set
  the baseline Frost aims to match.

MIT License.
