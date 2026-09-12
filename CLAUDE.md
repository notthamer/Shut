# Shut — conventions for contributors (human or AI)

Shut is an open-source, MIT-licensed macOS menu bar app built in public: ways to
close your Mac. The original v1 spec (when the app was called Sinkhole) is in
`docs/PRD.md`; the v2 direction is in this file and the README.

## Rules

1. **Readable over clever.** This code is a public portfolio piece. Prefer the obvious
   version. If a trick is needed for performance, isolate it and explain it.
2. **Comments explain design reasoning**, not what the code literally does. The shader
   files especially should read like a walkthrough.
3. **No third-party dependencies.** SwiftPM targets depend only on Apple frameworks.
   Argument parsing, JSON, HID, Metal: all hand-rolled or from the SDK.
4. **Never write screen content to disk.** Snapshots exist only as `MTLTexture`s in
   memory and are released the moment a transition ends. Logs never contain pixels.
   Never use `print` on image data, never save debug PNGs.
5. **`Tuner` must never import app code or `TransitionKit`.** It is a standalone
   SwiftUI package (a DialKit-style tuning panel) that other apps can reuse. It only
   imports SwiftUI, AppKit, Foundation, Combine, UniformTypeIdentifiers, and Carbon
   (for the permission-free global hot key). Do not use the DialKit name in code.
6. **Don't copy code from other lid-angle projects.** samhenrigold/LidAngleSensor is
   Apache-2.0; we credit its research and write our own implementation. Bendable is
   MIT: ported files say so in their header and `THIRD_PARTY_LICENSES.md` carries
   the license. Never use the DialKit name in code or UI.
7. **Match the visual system.** Every surface uses `TunerTheme`: 36-pt rows, 6-pt
   gaps, 8/14-pt radii, neutral alphas, no accent colour, springs on state changes,
   plain-English `help` on every control.
8. **Progress is 0 = open, 1 = shut** everywhere above the sensor.

## Layout

- `Package.swift` is the source of truth for all library and executable targets.
- `Shut.xcodeproj` contains a single app target that is a 3-line shim over the
  `ShutApp` library product, so Xcode builds a real `.app` bundle for testing.
- `scripts/build.sh` produces the same `.app` from SwiftPM without Xcode.
- `App/` holds files owned by the Xcode target (Info.plist, entitlements, assets).

## Swift settings

- Deployment target: macOS 14.0.
- Swift language mode 5 (tools 6.0). IOKit callbacks, AppKit notifications, Metal
  objects, and distributed-notification observers are all non-Sendable; strict
  concurrency checking would cost a lot of ceremony for no user-facing benefit.
  Main-thread ownership is enforced with `@MainActor` on the app controller instead.

## Testing

- `swift build` and `swift test` must pass before every commit.
- Render tests draw each transition offscreen on a synthetic image. Set
  `SHUT_FRAME_DUMP=/some/dir` to get PNGs of the frames (and of the Tuner panel).
- After changing `BuiltInPresets.swift`, run `swift run shut --export-presets presets`.
- Popover and Tuner snapshots are tests; look at the PNGs before changing a layout.
- Never publish an `@Published` property from inside a SwiftUI view update (for
  example from `updateNSView`); it loops forever.
- `xcodebuild -project Shut.xcodeproj -scheme Shut build` must pass too.
- Manual lid tests are listed in `README.md` under "Testing".
