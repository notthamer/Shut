# Shut.

> **Demo video coming.** _Lid closes, the desktop swirls into the notch; lid opens, it pours back out._

Ways to close your Mac. Shut plays a transition on the built-in display as you
close the lid, driven live by the hinge, on whatever Space or full-screen app you
happen to be in. Pick a style, set the speed, and tune every dial until it feels
exactly right. Open source, MIT, built in public.

- **Eight styles**: Fold, the iPhone Duo close and the default; Sinkhole, original
  to Shut; Frost; and five more ported from Bendable with credit.
- **Follows the hinge**, not a timer. Close slowly and the effect crawls; open the
  lid halfway through and it reverses.
- **A tuning panel** for every parameter, in the spirit of DialKit, native SwiftUI.
- **Menu bar and Dock.** A quick popover under the menu bar icon, or the same panel
  as a window you can move and minimize.
- **Every Apple-silicon MacBook.** Sensor machines track the hinge; the rest play
  the style on lid events.

## Styles

| Style | Needs Screen Recording | What it does |
| --- | --- | --- |
| **Fold** (iPhone Duo) | Yes | The default. The desktop turns against the lid, degree for degree, so it stands still while the machine folds away under it. |
| **Sinkhole** | Yes | The desktop swirls and drains into the notch, then pours back out when you unlock. Original to Shut. |
| **Frost** | Yes | The screen frosts over from the top edge and fades to black. |
| **Crease** | Yes | A book fold: creases across the middle and the upper half tips away. |
| **Recede** | Yes | Drops straight back into the dark, square to you the whole way. |
| **Slide** | Yes | Slides down out of sight behind the hinge. |
| **Shutter** | No | Bars close in from the top and bottom. |
| **Fade** | No | A plain dim to black. |

Fold, Crease, Recede, Slide, Shutter and Fade are ported
from [Bendable](https://github.com/opensourcevillain/Bendable) (MIT, Anti Ltd) and
credited in every file. Every style plays backwards when you open the lid, and
after you unlock from sleep it pours back out of black.

## Supported hardware

- Any Apple-silicon MacBook, M1 to current, all sizes, on macOS 14 or later.
- Macs with a lid angle sensor (M2 and later, most M1s) track the hinge live. Macs
  that only report open/closed play the style on a short timeline instead. Shut
  checks what your Mac can do and says so at the top of the panel.
- 13" models without a notch use a small virtual notch for Sinkhole.
- Intel Macs are untested.

Check your sensor: `swift run lidangle-cli` prints the live angle.

**External displays.** The effect plays on the MacBook's own screen and never on
another one. With a monitor attached, closing the lid still plays the style on the
built-in panel as it goes down; if the Mac then stays awake in clamshell mode, the
overlay is cleared the instant the built-in display leaves, so nothing ever covers
the external screen. Waking or unlocking in clamshell mode plays nothing. The status
line says "on the built-in display" while a monitor is connected.

## Install

```bash
git clone https://github.com/notthamer/shut
cd shut
scripts/build.sh            # → build/Shut.app
open build/Shut.app
```

Or open **`Shut.xcodeproj`** (not the folder or `Package.swift`) in Xcode, check
that the scheme next to the Run button says **Shut**, and press Run. Releases come
as a DMG from `scripts/package-dmg.sh`; see [Releases](#releases).

**First launch.** One welcome screen, one **Enable** button, then the panel opens.
Shut asks for nothing at launch.

**Permissions.** Styles that redraw your desktop need **Screen Recording** for a
single still captured as the lid starts to move, never a stream. The panel
explains this only when you pick one of those styles, with an Allow and a Restart
button (macOS checks the permission when the app starts). Until it is granted,
those styles play as a plain fade and the status line says so. Snapshots live in
GPU memory and are released as the transition ends. Nothing is written to disk.

**Keeping the permission across rebuilds.** macOS ties the grant to the app's
signature. With plain "Sign to Run Locally" every build is a new identity. Add your
Apple ID in Xcode (Settings → Accounts) and pick your Personal Team under Signing &
Capabilities, or create `App/Local.xcconfig` with a stable identity. See
`App/Signing.xcconfig`. If a stale grant sticks, `tccutil reset ScreenCapture
app.shut.mac` clears it.

## Interface

One panel, two ways in. The whole interface is a sheet of bone-white glass over
your desktop with a soft sheen; controls sit on it as white pills of soft clay or
wells cut into it, sliders fill with the spectrum gradient under a chrome knob,
selection is a lime wash, and everything that moves settles with a little give.
It stays light in dark mode on purpose, and goes solid when Reduce Transparency
is on. Labels are set in
Apfel Grotezk; numbers stay monospaced so they hold still while they change.

- **Menu bar.** Left click the icon for the panel as a popover. It closes when you
  click away or press Escape. Right click for a plain menu (pause, style, presets,
  Tuner, permission, launch at login, quit).
- **Dock.** Click the Dock icon, the Dock menu's **Open Shut**, or the window button
  in the popover's header for the same panel as a window: traffic lights, drag it by
  its background, ⌘M minimizes it to the Dock, ⌘W closes it, and it remembers where
  it was. **In Dock** in the footer hides the Dock icon if you want Shut in the menu
  bar only (it still appears while a window is open).

Inside the panel:

- **Preview** on the left plays the chosen style on a snapshot of your desktop (a
  drawn stand-in until Screen Recording is granted). Drag the Lid scrubber to move
  the lid by hand, or **Play on screen** to run it full screen, close then open.
- **Style** gallery of live thumbnails, rendered by the real shaders on your desktop.
- **Speed**: how much of the lid's travel the effect uses. Fast plays in the last
  twenty degrees; slow spreads it over the whole close.
- **Adjust**: the style's most important dials, and **Animate opening**.
- **Open at login**, **In Dock**, **Tune everything…** (⌃⌥T) and **Quit** (⌘Q) in
  the footer.

The status line under the wordmark reads *Following the lid*, *Plays when the lid
closes* (event-only Macs), *Preview only* (no lid), *Paused*, or *Fold needs Screen
Recording* when a style is substituting.

## How the hinge is read

The lid angle sensor reports whole degrees and only changes about ten times a
second, so reading it directly makes any effect pulse. Shut fits a line through
recent readings (position and rate, no lag), passes the result through a 1€ filter
whose cutoff follows the measured rate, and learns your hinge: the closed angle is
the lowest reading ever seen, the open angle follows wherever the lid rests. The
effect then runs in a band above shut, with a small share tracking the whole travel
so something always answers. Nobody types angles. This design comes from Bendable
and is credited in `Sources/LidSensor/`.

## What it costs to leave running

Shut is meant to be forgotten about. At rest the sensor is read once a second,
ten times a second for a little while after the lid last moved, and 120 times a
second only while it is moving. The sensor's own input reports act as a doorbell
that wakes the poller when the hinge is touched. No frame is drawn unless the
overlay is on screen and progress changed; the display link pauses after half a
second of stillness. The GPU is never waited on from the main thread. App Nap is
declined so a close is never missed while you are in another app.

## Safety

The overlay is click-through, sits above everything, joins every Space and
full-screen app, and is torn down when the lid reopens, when the sensor goes quiet
for half a second, when the built-in display disappears, on sleep, and on quit.
After unlock the fresh snapshot springs back out; if a black overlay is ever on
screen for more than 1.5 s while the Mac is awake and unlocked, it is force-hidden
and the event is logged.

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

## Presets

Built-in presets ship in the app and as JSON in [`presets/`](presets/). Your own
live in `~/Library/Application Support/Shut/Presets/<style>/`. To share one, or to
add a style, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Command line

```bash
swift run lidangle-cli                  # live angle, rate and progress
swift run lidangle-cli --report         # compatibility report for an issue
swift run lidangle-cli --calibration    # learned closed/open angles after 5 s
swift run lidangle-cli --log angles.csv # timestamp,angle per sample
swift run lidangle-cli --debug          # raw HID report bytes
swift run shut --export-presets presets # regenerate presets/ from the built-ins
```

## Project layout

| Target | What it is |
| --- | --- |
| `LidSensor` | IOKit HID reader for the hinge, the fit/filter/calibration pipeline, capability probing, lid-event fallback. |
| `TransitionKit` | The Metal renderer, the `Transition` protocol, all eight styles and their shaders, thumbnails, screen capture. |
| `Tuner` | The reusable tuning panel: schema, store, presets, rows, editors, theme. Imports nothing from the app. |
| `ShutApp` | The app: lid state machine, overlay window, popover and main window, welcome, menu bar, Dock, settings. |
| `shut`, `lidangle-cli` | Executables. `Shut.xcodeproj` wraps `shut` in a signed `.app` for Xcode. |

The full walk-through, from a sensor reading to a pixel, is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Testing

`swift test` runs 69 tests: sensor decoding, the hinge fit, filter, calibration and
band, the adaptive poll rate; offscreen renders of every style (identity at open,
monotonic darkening, see-through masks that need no snapshot); a GPU probe of the
uniform layout; the overlay window and the clamshell rule; the Tuner panel and the
panel UI rasterised as images in light, window and solid form. Set
`SHUT_FRAME_DUMP=dir` to get the PNGs. `swift test -c release --filter
BenchmarkTests` prints per-style frame times at full resolution (about 0.5–2.5 ms
on an M2 Pro).

Before a release, by hand on a real MacBook:

1. Close the lid slowly from the Desktop, from a full-screen app, and from a second
   desktop Space. The effect plays on all three.
2. Reopen before the screen sleeps: it reverses. Let it sleep, unlock: it pours out.
3. Pick Shutter with Screen Recording denied: it plays anyway.
4. Pick Fold with it denied: the orange card appears and the status line explains.
5. Drag Speed to Fast: the effect happens in the last twenty degrees.
6. With an external display, power and a keyboard attached, close the lid: the
   style plays on the built-in panel, the external screen is never touched, and
   the Mac keeps running. Open the lid: nothing plays, the panel simply returns.
7. Fifty quick close/open cycles: nothing stuck, nothing black.

Console.app, subsystem `app.shut`, shows every decision: capture, overlay placement
(and the fallback if macOS put it on the wrong Space), poll rate changes, teardown
reasons, and the safety rule. No pixels are ever logged.

## Releases

`App/Info.plist` holds the version. Bump `CFBundleShortVersionString`, push to
`main`, and the Release workflow tests, builds, packages a DMG with a SHA-256, tags
`v<version>`, and publishes a GitHub release. Pushes to other branches and pull
requests run the Build workflow and attach the DMG as an artifact. Locally:
`scripts/build.sh --zip` or `scripts/package-dmg.sh`; `scripts/version.sh` prints
the version.

## Credits

- [Bendable](https://github.com/opensourcevillain/Bendable), MIT © 2026 Anti Ltd: six
  of the styles, the hinge fit/filter/calibration design, and much of the panel's
  shape. License in `THIRD_PARTY_LICENSES.md`.
- [DialKit](https://github.com/joshpuckett/dialkit), MIT © 2026 Josh Puckett: the
  design of the tuning panel. No code was copied; the name is not used in code.
- [Apfel Grotezk](https://github.com/collletttivo/apfel-grotezk) by Collletttivo, SIL
  Open Font License 1.1: the typeface every label is set in. Bundled with its
  license in `Sources/Tuner/Fonts/`.
- [Emil Kowalski's skills](https://github.com/emilkowalski/skills), MIT: the motion
  rules the interface follows (easing, durations, springs, press feedback, reduced
  motion), translated from the web to SwiftUI and AppKit. Guidance only, no code.
- [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) and
  [DuoBook](https://github.com/askmaddyy/DuoBook) for the sensor research. Shut's
  sensor code is written from scratch.
- The many open-source recreations of the iPhone Duo close, which Fold and Frost draw on.

MIT License.
