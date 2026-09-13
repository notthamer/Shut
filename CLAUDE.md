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
7. **Match the visual system: an editorial broadsheet, after Dia.** One
   appearance; every window sets `TunerTheme.appearance` (Aqua) and the app sets
   it on `NSApp`. **Palette** (fixed, in `TunerTheme`): Bone paper, Paper White
   cards and the primary button, Linen pills and wells, Pure Black / Carbon /
   Slate ink, Silver borders, Soft Graphite dark fills, Lime Wash selection,
   Saffron warm highlight, Void Black only on the welcome stage; the Spectrum
   Marquee appears once per panel as a 2-pt `SpectrumLine`, never as a fill.
   **Depth** is a one-point border (`surface(.card/.pill/.well/.wash)`); nothing
   inside a panel casts a shadow, except the preview's product window (the
   three-layer drop shadow) and the windows themselves. **Radii**: 12 (cards,
   wells), 20 (pills), 24 (panels), full (buttons); no others. **Type**: Playfair
   Display via `TunerTheme.display(_:)` for the wordmark, headings and the welcome
   (weight 400, negative tracking, never bold); Apfel Grotezk via
   `TunerTheme.font(_:weight:)` for labels and body (500 only for emphasis);
   system mono for eyebrows (`Eyebrow`, uppercase, wide tracking, numbered
   chapters "01 02 03") and values. **Motion**: `TunerTheme.ease` (0.2 s,
   cubic-bezier 0.4 0 0.2 1) on colour, border and opacity only; `tunerMotion`
   resolves to nil, `PressStyle` dims, panels fade, folders crossfade; sliders
   follow the pointer 1:1 with no rubber band. Plain-English `help` on every
   control. Reduce Transparency makes the paper solid, Increase Contrast darkens
   secondary ink and borders: both go through the theme, never hard-coded.
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
