# Architecture

From a hinge reading to a pixel, and back again on the way up. Read this before
changing anything below the UI. Progress is **0 = open, 1 = shut** everywhere
above the sensor.

## The pipeline

```
lid angle sensor ──► LidSensor ──► AppController ──► OverlayWindow ──► TransitionRenderer ──► screen
   (IOKit HID)        HingeState     state machine     click-through     Metal, one draw
                      progress 0…1   arm/show/tear     every Space       per frame
```

1. **`LidSensor`** owns the hinge. `LidAngleDevice` opens the HID sensor
   (vendor 0x05AC, product 0x8104, usage page 0x20, usage 0x8A) and reads feature
   report 1, bytes 1–2, little-endian degrees. `LidSensorMonitor` polls it on a
   background queue, runs the readings through `HingeNormalizer` (`AngularFit`
   least-squares line → `OneEuroFilter` → `HingeCalibration` with a learned closed
   floor and `OpenReference`), and publishes a `HingeState` (angle, velocity,
   progress, direction) on the main thread. On Macs without the sensor,
   `LidStateProvider` watches `IOPMrootDomain` for clamshell edges instead.
2. **`AppController`** is the lid state machine: `idle → armed → closing → drained
   → pouring → idle`. Arming captures one still of the built-in display
   (`ScreenCapturer`, ScreenCaptureKit, our own windows excluded) into an
   `MTLTexture`. `closing` shows the overlay and, each display-link frame, feeds
   the hinge through `ProgressDriver` (per-frame glide, commit spring past the
   threshold, timed mode for event-only Macs) into the renderer. `drained` is the
   black hold across sleep. `pouring` is the reverse after unlock, on a fresh
   snapshot, with a small overshoot.
3. **`OverlayWindow`** is a borderless, click-through, non-activating `NSPanel`
   at screen-saver level with `canJoinAllSpaces` and `fullScreenAuxiliary`. It is
   built fresh for every close and its `show(on:)` checks `isOnActiveSpace`; if the
   window server still refuses, it re-orders the window with `moveToActiveSpace`
   and logs the fallback. See "Spaces" below for why it is a panel.
4. **`TransitionRenderer`** draws one frame: the snapshot, a `TransitionUniforms`
   buffer (stride 240, mirrored in `Common.metal` and checked by a GPU probe test),
   and either a full-screen triangle (Sinkhole, Frost) or a 48×48 mesh with
   premultiplied blending (the panel styles). Everything is `bgra8Unorm_srgb` so
   dimming and blur happen in linear light. Shaders are `.metal` source files
   shipped as resources and compiled at launch, concatenated with `Common.metal`
   first, because `swift build` does not compile Metal. At most two frames are in
   flight; the main thread never waits on the GPU.

## Styles

A style is a `Transition`: an `id`, names, a `TunableParameters` struct with a
Tuner schema, `needsSnapshot`, `isTransparent`, and a fragment function. Panel
styles (`Sources/TransitionKit/Panel/`) conform to `PanelTransition` and return a
`PanelFrame` (fold angle and position, perspective, curvature, scale, translate,
blur, wash, brightness, mask) from `frame(progress:context:)`;
`Panel.metal` does the rest. Mask styles set `needsSnapshot = false` and
`isTransparent = true`, composite over the live desktop, and work without Screen
Recording. `TransitionCatalog` lists them; `TransitionRegistry` holds the current
one and substitutes Fade when a snapshot style lacks permission or Reduce Motion is
on. `TunerHost` registers each style's parameters with the Tuner in one line.

## Timing and energy

- Sensor at rest: 1 Hz. After the lid last moved: 10 Hz for a short settle, then
  parked. Moving: 120 Hz. An IOHID input-report callback is the doorbell that wakes
  a parked poller; it needs a change of at least two degrees so the sensor's
  heartbeat does not count. `keepAwake` holds 10 Hz or better while an overlay is
  up so the 500 ms watchdog is never tripped by parking.
- Hinge → screen latency is the fit's lead plus one frame. Whole-degree steps are
  hidden by the fit, the 1€ filter, and the driver's per-frame glide.
- No frame is drawn unless progress changed; the display link pauses after 0.5 s
  of stillness and resumes on the next hinge sample.
- The snapshot is taken when the lid first moves and refreshed once a second for
  six seconds while it rests near open; after that it is dropped. The close only
  starts with a snapshot under 1.5 s old, re-capturing first otherwise, so the
  picture always matches the Space the user is on. Console reports the age on
  every `overlay shown` line.
- The app opts out of App Nap (`LSAppNapIsDisabled` plus a `beginActivity`) so a
  close is never missed while the app is in the background on another Space.

## UI

- **`PopoverView`** is the whole panel: header, `PreviewColumn`, `ControlsColumn`,
  footer. `PopoverModel` is its state (status line, speed ↔ band degrees,
  thumbnails via `TransitionThumbnailRenderer`, hooks into the app).
- **`PopoverController`** shows it under the status item in a `KeyablePanel`
  (borderless, non-activating, but able to become key so buttons work), with
  click-outside and Escape to close.
- **`MainWindowController`** shows the same view in a titled, miniaturizable window
  with a transparent title bar; `hostedInWindow` insets the header for the traffic
  lights. Both hosts share one `PreviewModel`; `PreviewHostView` claims the model's
  Metal view whenever its window becomes key, so the visible preview is the live one.
- **`DockPresence`** switches the activation policy: a Dock icon always when "In
  Dock" is on, otherwise only while a window (popover, main window, Tuner, welcome)
  is open. `MainMenu` gives the window the standard shortcuts.
- **`Tuner`** is a separate package (see its README section). `TunerPanelController`
  hosts `TunerPanelView` in a `KeyablePanel` with `PanelChrome` (glass, hairline,
  top highlight); the app injects the preview column and hides the panel while a
  real transition plays. `TunerTheme` is derived from the SwiftUI color scheme so
  light and dark both work.

## Spaces and full-screen apps

The lid can close on any desktop Space or over any full-screen app, and the effect
has to appear there. Two facts, measured on macOS 26 with a two-process experiment
(one process holds a full-screen Space, the other tries to show an overlay):

| Overlay is a… | App is menu-bar-only (`.accessory`) | App is in the Dock (`.regular`) |
| --- | --- | --- |
| plain `NSWindow` | on the active Space | **refused**: `isOnActiveSpace` false, never visible |
| non-activating `NSPanel` | on the active Space | on the active Space |

Collection behavior (`canJoinAllSpaces`, `fullScreenAuxiliary`, `moveToActiveSpace`)
makes no difference in the refused cell. Shut is a Dock app whenever "In Dock" is
on or a window is open, so the overlay is a non-activating panel. `show(on:)`
still verifies `isOnActiveSpace` and logs `overlay placement fallback` if macOS
ever changes the rules again; that line in Console is the first thing to look for
when "nothing showed".

## External displays

The effect belongs to the lid's own panel. `BuiltInDisplay.screen` returns the
built-in `NSScreen` or nil, never another screen. Capture, overlay and notch
geometry all go through it. When a monitor is attached:

- Closing the lid plays the style on the built-in panel as usual; the external
  screen is untouched.
- In clamshell mode (external display, power and keyboard, so the Mac stays awake
  with the lid shut) the built-in display leaves `NSScreen.screens`. AppKit would
  move our full-screen window onto the remaining display, so
  `didChangeScreenParametersNotification` tears everything down first
  (`shouldTearDownForScreens`, unit tested). Opening the lid again plays nothing:
  the desktop is being re-laid-out and there is no snapshot worth reversing.
- Waking or unlocking while the built-in display is absent tears down instead of
  entering the pour-out, so the black hold never lands on the external screen.
- The panel's status line adds "on the built-in display" while a monitor is
  connected, and says so when the lid is shut on an external display.

## Sleep, lock and safety

- `NSWorkspace.screensDidSleep` → `drained` (opaque black overlay, snapshot
  released). `didWake` reconnects the sensor (the HID endpoint dies across sleep).
- `com.apple.screenIsUnlocked` (undocumented distributed notification, stable since
  10.x) → fresh capture → `pouring`. Macs with no password pour out right after wake.
- Non-negotiable rule: a black overlay visible for more than 1.5 s while awake and
  unlocked is force-hidden and logged as `SAFETY`.
- The overlay is also torn down on lid reopen below the hysteresis point, on a
  sensor gap over 500 ms, and on quit. Two instances never run: the newer one
  terminates the older.

## Logging

`os.Logger`, subsystem `app.shut`, categories `app`, `lid`, `overlay`, `capture`,
`unlock`. Log lines
carry decisions and timings, never pixels. Useful greps: `snapshot ready`,
`overlay shown`, `overlay placement`, `poll rate`, `teardown:`, `SAFETY`.
