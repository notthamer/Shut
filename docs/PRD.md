# PRD: Sinkhole — Lid Transitions for MacBook

| | |
|---|---|
| **Working title** | Sinkhole (placeholder; check for name conflicts before launch) |
| **Platform** | macOS 14 Sonoma or later, MacBooks with a readable lid angle sensor |
| **Status** | Draft v0.3 |
| **Date** | September 11, 2026 |
| **License** | MIT |
| **Model** | Open source on GitHub, built in public on X |

---

## 1. Summary

Sinkhole is an open-source menu bar app that plays a transition on your MacBook's screen as you close the lid, driven live by the lid angle sensor. It ships with two transitions.

**Notch Drain** (the headline): as the lid closes, the whole screen swirls and gets pulled into the notch, like water going down a drain. When you unlock the Mac again, the desktop pours back out of the notch with a little springy overshoot.

**Frost** (the classic): the iPhone Duo style transition. The image stays fixed in space, frosts over from the top edge toward the hinge, and fades to black.

Every parameter of both transitions can be tuned live in **Tuner**, a floating control panel inspired by Josh Puckett's DialKit, rebuilt natively in SwiftUI. Users can scrub the transition without touching the lid, save presets as JSON, and share them.

## 2. What changed from v0.2

Five or more open-source clones of the Duo frost effect, plus a paid app, already exist. v0.3 repositions the project around three things nobody has shipped together: an original transition (Notch Drain), a pour-out animation on unlock, and a native DialKit-style tuning panel that doubles as a reusable open-source SwiftUI package. Frost stays in as the familiar baseline.

## 3. Goals and Non-Goals

### Goals

1. Notch Drain looks like something Apple could have shipped, and reads clearly in a 5-second video.
2. Both transitions track the physical lid with no perceptible lag.
3. Tuner makes every visual and motion parameter adjustable live, with presets and JSON export.
4. Tuner is built as a standalone Swift package with no dependency on the app, so other macOS and iOS developers can reuse it.
5. Zero side effects during normal use: invisible, click-through, near-zero idle cost, never stuck on screen.
6. Open source and build in public: each milestone produces merged code and a post.

### Non-Goals for v1

1. Drawing over the macOS lock screen (not possible for normal apps).
2. Effects on external displays.
3. Mac App Store distribution.
4. Support for Macs without a readable lid sensor, beyond the preview window.
5. Porting Tuner to iOS (design the API so it's possible later).

## 4. User Experience

### 4.1 Notch Drain (close)

As the lid passes the start angle, the screen appears to freeze. Content nearest the notch starts moving first, then the whole desktop spirals inward and funnels up into the notch, stretching into a tail as it goes. Pixels darken as they approach the sink, with a faint glow around the notch rim at the peak of the effect. By the end angle, the screen is black.

On Macs without a notch, the sink is placed at the top center of the menu bar, and a small pill-shaped "virtual notch" fades in so the effect still has a destination.

**Commit behavior.** By default, the drain follows the lid exactly. An optional commit threshold lets the drain finish on its own with a spring once the lid passes a set point, which feels like the Mac "gulping" the screen. If the lid reopens before the display sleeps, the drain reverses with the lid.

### 4.2 Pour-out (open)

When the Mac wakes and the user unlocks it, the desktop pours out of the notch: it unspirals from the sink, overshoots slightly past its normal size, and settles with a spring. If no password is required, pour-out plays right after wake.

### 4.3 Frost (close)

Same design as v0.2: the image is locked in space, frosts from the top edge toward the hinge with progressive blur, and fades to black. It never scales or moves.

### 4.4 Tuner panel

Tuner is a floating, collapsible panel opened from the menu bar or with ⌃⌥T. Parameters are grouped into folders. It includes a preview area where transitions play on a snapshot of your desktop, so you can tune without closing the lid.

| Control type | Used for |
|---|---|
| Slider with range | Most numeric parameters |
| Toggle | Feature switches |
| Color picker | Glow color |
| Spring editor | Response and damping, with a live curve preview |
| Bézier easing editor | Drag handles to shape a progress curve |
| Segmented picker | Transition choice, sink mode |
| Action button | Replay, reset group, copy JSON, save preset |

Preview controls: a progress scrub slider, "Play close," "Play pour-out," a "Follow lid" toggle that drives the preview from the real sensor, and a transition picker.

### 4.5 Default parameters

**Notch Drain**

| Group | Parameter | Range | Default |
|---|---|---|---|
| Motion | Progress curve | Bézier | ease-in (0.45, 0, 0.85, 0.55) |
| Motion | Falloff (how much near-notch content leads) | 0 to 3 | 1.2 |
| Motion | Twist (turns at full progress) | −2 to 2 | 0.6 |
| Motion | Funnel stretch | 0 to 2 | 0.8 |
| Motion | Commit threshold | 0 to 100% (100% = follow lid) | 100% |
| Look | Motion blur samples | 0 to 16 | 8 |
| Look | Motion blur strength | 0 to 1 | 0.5 |
| Look | Darken toward sink | 0 to 1 | 0.6 |
| Look | Chromatic aberration | 0 to 10 px | 2 |
| Look | Rim glow | 0 to 1 | 0.35 |
| Look | Glow color | Color | White |
| Sink | Auto-detect notch | Toggle | On |
| Sink | Offset X / Y | ±200 pt | 0 |
| Sink | Sink radius | 0 to 60 pt | 16 |
| Pour-out | Spring response | 0.1 to 1.5 s | 0.55 |
| Pour-out | Spring damping | 0.3 to 1.0 | 0.72 |
| Pour-out | Overshoot | 0 to 0.15 | 0.06 |
| Pour-out | Delay after unlock | 0 to 500 ms | 0 |

**Frost**

| Parameter | Range | Default |
|---|---|---|
| Max blur radius | 0 to 120 | 64 |
| Frost spread | 0 to 1.5 | 0.6 |
| Darkness start | 0 to 1 | 0.30 |
| Progress curve | Bézier | linear |

**Trigger (shared)**

| Parameter | Range | Default |
|---|---|---|
| Start angle | 40° to 110° | 80° |
| Fully complete angle | 0° to 35° | Calibrated in M0, fallback 12° |
| Smoothing | Low / Medium / High | Medium |

### 4.6 Presets

Presets are JSON files containing the transition name and every parameter value. Users can save, load, duplicate, and delete presets, copy the current values to the clipboard, and import by pasting or dropping a JSON file. The repo includes a `presets/` folder where the community can submit presets by pull request. The app ships with three built-in presets per transition, for example "Gentle," "Default," and "Black Hole" for Notch Drain.

### 4.7 Menu bar

The menu bar menu has an enable toggle, a transition picker (Notch Drain or Frost), a preset picker, "Open Tuner," an optional live angle readout, launch at login, and quit.

## 5. Technical Approach

### 5.1 Architecture

| Module | Type | Responsibility |
|---|---|---|
| `LidSensor` | Library | HID access, smoothing, velocity, publishes angle |
| `Tuner` | Library, no app dependency | Declarative parameter schema, SwiftUI panel, presets, JSON |
| `TransitionKit` | Library | `Transition` protocol, Metal renderer, shaders |
| `Sinkhole` | App | Menu bar, state machine, capture, overlay window, unlock flow |
| `lidangle-cli` | Tool | Sensor probe from M0 |

### 5.2 Transition protocol

Each transition declares its parameter struct (conforming to Tuner's schema protocol), its Metal fragment function, and a function that packs parameters plus progress into a uniform buffer. The renderer is shared: it owns the snapshot texture, draws a full-screen quad, and calls the active transition's shader every frame. Adding a third transition later should require one Swift file and one shader function.

### 5.3 Notch detection

Use `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` (macOS 12+) on the built-in screen. When both exist, the notch spans the gap between them, and the sink point is the horizontal center of that gap at the bottom edge of the notch. When they're absent, use the virtual notch fallback from section 4.1.

### 5.4 Notch Drain shader sketch

For each output pixel at position `x`, with sink point `s`, progress `p`, and `D` the distance from the sink to the farthest screen corner:

```
v  = x − s
d  = length(v) / D                          // 0 at sink, 1 at farthest corner
q  = clamp(p · (1 + f) − f · d, qMin, 1)    // local progress; near-sink leads
                                            // f = falloff, qMin = −overshoot
k  = 1 / max(ε, (1 − q)^γ)                  // contraction: content shrinks toward sink
θ  = twist · 2π · q²                        // swirl angle
vf = (v.x · (1 + stretch · q), v.y)         // funnel: squeeze horizontally
src = s + rotate(vf · k, θ)                 // inverse-map to snapshot UV
```

Pixels whose `src` falls outside the snapshot render black. Darkening multiplies by `1 − darken · q`. Motion blur averages N samples of `src` computed at slightly smaller values of `q`, and chromatic aberration offsets R and B samples along `v`. A negative `q` (allowed down to −overshoot during pour-out) makes `k < 1`, which briefly pushes content past its normal size, giving the splash. This mapping is an approximation to be tuned visually in Tuner, not a physical simulation.

### 5.5 Driving progress

During close, `p` comes from the lid angle mapped between start and end angles, then through the progress curve. If the commit threshold is below 100% and `p` crosses it, a critically damped spring takes over and animates to 1. If the lid rises above the start angle plus 5° hysteresis at any point before sleep, a spring animates back to 0 and the overlay is removed.

During pour-out, `p` is driven only by the pour-out spring from 1 to 0, including overshoot.

### 5.6 Close flow

The flow is the same as v0.2: arm near the start angle, capture the built-in display with `SCScreenshotManager` while excluding the app's own windows, show a borderless click-through overlay at `.screenSaver` level on all Spaces, and render each frame with a display link.

### 5.7 Pour-out flow

1. On `NSWorkspace.willSleepNotification` or `screensDidSleepNotification`, release the close snapshot and switch the overlay to a solid black "drained" state.
2. On wake, keep the black overlay ordered in. If the lock screen is up, the overlay sits beneath it and stays invisible.
3. When the session unlocks (`com.apple.screenIsUnlocked` distributed notification, or no lock detected via `CGSessionCopyCurrentDictionary`), capture a fresh snapshot of the desktop, excluding the overlay.
4. Swap the black overlay for the snapshot at `p = 1` and run the pour-out spring to 0, then order the overlay out.

**Safety rule:** if the overlay has been in the black drained state for more than 1.5 seconds while the session is unlocked and screens are awake, force-hide it immediately. The user must never be left looking at a black screen. The lock notification names are undocumented and must be verified in M5.

### 5.8 Tuner implementation

Parameter structs declare their controls through a schema built from key paths, for example a slider bound to `\.twist` with a range and default, grouped into folders. The panel is a SwiftUI view hosted in a floating `NSPanel`. Values persist in `UserDefaults` per transition, and presets are stored as JSON in `~/Library/Application Support/Sinkhole/Presets`. Tuner must not import anything from the app or TransitionKit. The panel hides automatically while a real lid transition is playing.

## 6. Functional Requirements

| ID | Requirement | Priority |
|---|---|---|
| FR-1 | Detect the lid sensor; show a clear unsupported state if absent, while keeping Tuner and preview usable | P0 |
| FR-2 | Adaptive polling and smoothing of lid angle | P0 |
| FR-3 | Snapshot capture of the built-in display, excluding own windows | P0 |
| FR-4 | Click-through overlay on the built-in display only, all Spaces, above full-screen apps | P0 |
| FR-5 | Shared Metal renderer with the `Transition` protocol | P0 |
| FR-6 | Notch Drain transition per sections 4.1 and 5.4 | P0 |
| FR-7 | Notch detection with virtual notch fallback | P0 |
| FR-8 | Reverse with lid before sleep; tear down overlay on reopen | P0 |
| FR-9 | Never leave a frozen image or black screen after wake (safety rule in 5.7) | P0 |
| FR-10 | Tuner panel with all control types in 4.4 | P0 |
| FR-11 | Preview area with scrub, play close, play pour-out, follow lid | P0 |
| FR-12 | Presets: save, load, copy JSON, import JSON, three built-ins per transition | P1 |
| FR-13 | Frost transition per section 4.3 | P1 |
| FR-14 | Pour-out on unlock per section 5.7 | P1 |
| FR-15 | Commit threshold behavior | P1 |
| FR-16 | Respect Reduce Motion (simple fade) and Reduce Transparency (no blur) | P1 |
| FR-17 | Launch at login | P2 |

## 7. Non-Functional Requirements

**Performance.** Idle CPU under 0.2%, zero GPU when idle, frame time under 8.3 ms at 120 Hz on M3 or newer with 8 motion blur samples, snapshot latency p95 under 100 ms.

**Privacy.** Snapshots stay in memory only, are never written to disk or logged, and are released as soon as a transition ends. The only permission required is Screen Recording.

**Reliability.** Stuck overlay after 100 close/open/unlock cycles: zero. A watchdog hides the overlay if no sensor sample arrives for 500 ms during a close.

## 8. Open Source and X Plan

**Repository.** MIT license. SwiftPM targets match section 5.1. The README opens with the Notch Drain video and credits LidAngleSensor for sensor research, DialKit as the inspiration for Tuner, and the existing Duo clones. Community contributions focus on presets (`presets/*.json`) and new transitions.

**Tuner as its own project.** Once stable, Tuner can be extracted into its own repository and announced separately as a DialKit-style tuning panel for SwiftUI, with credit to the original. Do not use the DialKit name.

**Posts.**

| Post | Milestone | Asset | Idea |
|---|---|---|---|
| P1 | M0 | Phone video of the terminal printing lid angle | My MacBook knows exactly how open its lid is |
| P2 | M2 | Phone video: lid closes, screen swirls into the notch | Everyone copied the Duo blur. I made my Mac swallow its screen |
| P3 | M3 | Screen recording of Tuner changing twist, glow, and springs live | Built a DialKit-style tuner in SwiftUI to find the right feel |
| P4 | M4 | Side-by-side: Frost vs Notch Drain | Two ways to close a laptop |
| P5 | M5 | Phone video: unlock, desktop pours out of the notch | And now it pours back out |
| P6 | M6 | Launch thread plus preset showcase | v1.0 is open source; send me your presets |

## 9. Milestones

| Milestone | Target | Scope | Exit criteria |
|---|---|---|---|
| M0: Sensor | Sep 13 | `lidangle-cli` with live, report, and log modes; calibrate end angle | Reliable readings on your Mac |
| M1: Pipeline | Sep 17 | Menu bar app, capture, overlay, Metal renderer, `Transition` protocol, simple fade transition, preview window with scrub, sleep safety | Fade follows the lid; no stuck overlay after 50 cycles |
| M2: Notch Drain | Sep 21 | Shader per 5.4, notch detection, fallback | Looks right in preview and on real lid close; P2 filmed |
| M3: Tuner | Sep 26 | Tuner package, all control types, persistence, presets, JSON | Every Notch Drain parameter tunable live |
| M4: Frost | Sep 29 | Frost transition on the shared renderer, transition picker | Both transitions switchable from menu bar |
| M5: Pour-out | Oct 3 | Unlock flow, spring with overshoot, safety rule | 100 sleep/wake/unlock cycles with no black screen |
| M6: v1.0 | October, timed to Duo retail | README, built-in presets, presets folder, build script, release | Tagged v1.0 |

## 10. Risks and Open Questions

| Risk or question | Mitigation or next step |
|---|---|
| Black screen left after wake | Safety rule in 5.7; test heavily in M5 |
| Lock and unlock notifications are undocumented | Verify in M5; fall back to wake-only pour-out if needed |
| Your Mac's sensor doesn't work | Confirmed or ruled out in M0; Tuner and preview still work without it |
| Notch Drain looks cheap instead of magical | Tune in preview first; show early clips to a few designers before posting |
| Panel turns off before the drain finishes | Calibrate end angle in M0; commit threshold can finish the drain early |
| Motion blur too expensive at 120 Hz | Reduce samples dynamically; render at 0.75 scale during motion |
| Name conflicts with existing apps | Search App Store, GitHub, and Homebrew before M6 |
