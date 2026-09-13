# Shut — conventions for contributors (human or AI)

Shut is an open-source, MIT-licensed macOS app built in public: ways to close your
Mac. It lives in the menu bar and the Dock, plays a lid-driven transition on the
built-in display, and ships a reusable tuning panel. The original v1 spec (when the
app was called Sinkhole) is kept in `docs/PRD.md` for history; the current design
is described in `README.md` and `docs/ARCHITECTURE.md`.

## Rules

1. **Readable over clever.** This code is a public portfolio piece. Prefer the obvious
   version. If a trick is needed for performance, isolate it and explain it.
2. **Comments explain design reasoning**, not what the code literally does. The shader
   files especially should read like a walkthrough.
3. **No third-party dependencies.** SwiftPM targets depend only on Apple frameworks.
   Argument parsing, JSON, HID, Metal: all hand-rolled or from the SDK.
4. **Never write screen content to disk.** Snapshots exist only as `MTLTexture`s in
   memory and are released the moment a transition ends. Logs never contain pixels.
   Never use `print` on image data, never save debug PNGs outside the test dump.
5. **`Tuner` must never import app code or `TransitionKit`.** It is a standalone
   SwiftUI package (a DialKit-style tuning panel) that other apps can reuse. It only
   imports SwiftUI, AppKit, Foundation, Combine, UniformTypeIdentifiers, and Carbon
   (for the permission-free global hot key). Do not use the DialKit name in code.
6. **Don't copy code from other lid-angle projects.** samhenrigold/LidAngleSensor is
   Apache-2.0; we credit its research and write our own implementation. Bendable is
   MIT: ported files say so in their header and `THIRD_PARTY_LICENSES.md` carries
   the license. Never use the DialKit name in code or UI.
7. **Match the visual system: light liquid glass.** One appearance; every window
   sets `TunerTheme.appearance` (Aqua) and the app sets it on `NSApp`, so the
   glass reads the same over any wallpaper and in dark mode. `PanelChrome` is the
   window material (blur, white tint, sheen, light catch, edges, animatable
   corner radius). Everything on it is `glassSurface(.raised | .inset |
   .tinted(_))`; knobs are `GlassBead`; the one strong action is the ink
   `PrimaryButton`. The panel is cream (`TunerTheme.cream`, 95 % over the
   blur); rows are raised pills (radius = half the 36-pt row height) in soft
   clay (a dark shadow bottom-right, a light one top-left); wells are inset
   into a deeper cream. Sliders: warm red-to-yellow fill (`TunerTheme.warm`)
   revealed by the knob's travel, thin ticks, a `ChromeKnob`. Radii 22 (panel)
   / 16 (card) / 12 (wells); text is ink (`ink`, `inkLabel`, `inkTertiary`);
   the only tints are amber (selection, permission) and the warm slider
   gradient. Plain-English `help` on every
   control. Reduce Transparency makes the glass solid, Increase Contrast darkens
   ink and edges: both go through the theme, never hard-coded colours. Text is
   Apfel Grotezk via `TunerTheme.font(_:weight:)` (bundled in
   `Sources/Tuner/Fonts/`, OFL, registered by `TunerFonts` at first use);
   numbers use `TunerTheme.value` (system monospaced). SF Symbols keep
   `.system` fonts, which set their weight.
   **Motion rules** (from Emil Kowalski's design-engineering skills, credited in
   the README): keyboard-initiated actions never animate (⌃⌥T, Escape, arrow
   nudges); everything else is critically damped (`TunerTheme.quick`/`spring`),
   entrances and exits use `TunerTheme.easeOut(_:)`, on-screen moves
   `easeInOut(_:)`, UI stays under 300 ms, exits are faster than entrances, nothing
   enters from scale 0, popovers grow from their trigger. Every pressable gets
   `PressScaleStyle` (0.97 rows and cards, 0.96 small buttons) so feedback lands on
   mouse-down. Use `tunerMotion` for anything that moves or scales and
   `tunerAnimation` for opacity, colour and fills: Reduce Motion drops the first
   and shortens the second to a 120 ms fade. `PanelChrome` and `panelGlass` go
   solid under Reduce Transparency. Review timing in slow motion with
   `SHUT_MOTION_SCALE=4` in the scheme's environment.
8. **Progress is 0 = open, 1 = shut** everywhere above the sensor.
9. **The overlay belongs to the built-in display and to the Space the lid is
   closing on.** Build it fresh per close, show it with `OverlayWindow.show(on:)`
   (which verifies `isOnActiveSpace` and falls back to `moveToActiveSpace`), and
   tear it down the moment the built-in display leaves the screen list. Never
   fall back to `NSScreen.main`; a black overlay on an external monitor is the one
   thing this app must never do. The overlay stays a **non-activating `NSPanel`**:
   a plain `NSWindow` from a Dock app is refused on other Spaces and full-screen
   apps (measured; see `docs/ARCHITECTURE.md`, "Spaces").
10. **Never block the main thread on the GPU or the sensor.** At most two frames
    in flight; `nextDrawable()` is skipped, not awaited; the sensor clock is read
    through a lock, not the main-thread state.
11. **Idle must stay idle.** The sensor parks at 1 Hz; only a real hinge movement
    (≥ 2°) wakes it; nothing draws unless progress changed. Any change that adds a
    timer, a poll, or a per-frame publish needs a reason in the commit message.

## Layout

- `Package.swift` is the source of truth for all library and executable targets:
  `LidSensor`, `TransitionKit`, `Tuner`, `ShutApp`, and the executables `shut` and
  `lidangle-cli`.
- `Shut.xcodeproj` contains a single app target that is a 3-line shim over the
  `ShutApp` library product, so Xcode builds a real signed `.app` for testing.
  Scheme autocreation is off so the package schemes don't appear.
- `scripts/build.sh` produces the same `.app` from SwiftPM without Xcode.
- `App/` holds files owned by the Xcode target (Info.plist, entitlements, icon,
  signing xcconfigs). `App/Info.plist` is the single source of the version.
- `Sources/ShutApp/Popover/` is the panel UI. `PopoverView` + `PopoverModel` are
  shown by both `PopoverController` (under the status item) and
  `MainWindowController` (a titled, miniaturizable window). One `PreviewModel`
  feeds both; `PreviewHostView` claims it for whichever window is key.
- Shaders are `.metal` source files copied as resources and compiled at launch
  (`Common.metal` first). `swift build` does not compile Metal, so a shader error
  only shows up when the app or the render tests run.

## Swift settings

- Deployment target: macOS 14.0.
- Swift language mode 5 (tools 6.0). IOKit callbacks, AppKit notifications, Metal
  objects, and distributed-notification observers are all non-Sendable; strict
  concurrency checking would cost a lot of ceremony for no user-facing benefit.
  Main-thread ownership is enforced with `@MainActor` on the app controller instead.

## Testing

- `swift build`, `swift test`, and `xcodebuild -project Shut.xcodeproj -scheme
  Shut build` must pass before every commit.
- Render tests draw each transition offscreen on a synthetic image. Set
  `SHUT_FRAME_DUMP=/some/dir` to get PNGs of the frames, the Tuner panel, and the
  panel UI (light, window, solid). Look at them before changing a layout. Metal
  layers do not rasterise into these snapshots, so the preview area is black there.
- `TransitionUniforms` is mirrored by hand in `Common.metal`; the GPU probe test
  (`uniformsLayoutProbe`) is the only guard against layout drift. Run it after
  touching either.
- After changing `BuiltInPresets.swift`, run `swift run shut --export-presets presets`.
- Never publish an `@Published` property from inside a SwiftUI view update (for
  example from `updateNSView`); it loops forever.
- Manual lid tests are listed in `README.md` under "Testing". Spaces, full-screen
  apps, and external displays can't be simulated in `swift test`; check them on
  hardware and read Console (subsystem `app.shut`) for the placement lines.
