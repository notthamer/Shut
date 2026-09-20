# Contributing to Shut

Three kinds of contribution are especially welcome: presets, styles, and reports
from MacBooks we haven't tested on.

## Reporting a problem

- **The effect didn't play, or played on the wrong screen.** Open Console.app,
  filter on subsystem `app.shut`, close the lid again, and paste the lines from
  `snapshot ready` through `teardown:` into an issue (there is a template). The
  `overlay placement` line says which Space and display macOS put the overlay on.
  Say whether you were on the Desktop, in a full-screen app, on another Space, or
  on an external display.
- **Your Mac says "Lid open/close events only" or the angle looks wrong.** Use the
  sensor report issue template; it asks for `lidangle-cli --report` and
  `--calibration` output.
- The logs contain no pixels and are enough; don't attach screenshots of your
  desktop mid-close.

## Submitting a preset

1. Open the panel, dial in your look, then under **Presets** choose **Save as…** and name it.
2. Press **Copy** (the JSON lands on the clipboard) or find the file in
   `~/Library/Application Support/Shut/Presets/<style>/`.
3. Add it as `presets/<style>/<your-preset-name>.json`. The file looks like:

   ```json
   {
     "name" : "Black Hole",
     "transition" : "sinkhole",
     "values" : { "twist" : 0.8, "falloff" : 1.2, ... }
   }
   ```

4. Open a pull request with a one-line description and, ideally, a short clip.

Presets load via **Paste JSON** or by dropping the file onto the panel.

## Adding a style

A style is one Swift file and, for anything the panel pipeline can't express, one
Metal fragment function.

**Panel styles** (bend, mask, slide, fade): conform to `PanelTransition` and return
a `PanelFrame` from `frame(progress:context:)`. See `Sources/TransitionKit/Panel/`.
Progress is 0 = open, 1 = shut; `context.velocity` is progress per second, positive
while closing; `context.hingeTravelDegrees` is the band the effect spans.

**Full-screen styles** (anything that remaps pixels): conform to `Transition` with
your own `fragmentFunctionName` in a new `Shaders/<Name>.metal`. `Common.metal` is
concatenated first, so `TransitionUniforms` and `VertexOut` are in scope. See
`SinkholeTransition.swift` and `Frost.metal`. Shaders compile at launch, not in
`swift build`, so run the app or the render tests to see errors.

Either way:

1. Add a `struct <Name>Params: TunableParameters` with defaults, a `schema` of
   folders and controls, plain-English `help` on every dial, and `featured: true` on
   the two to five that belong in the panel's Adjust section.
2. Give the transition an `id`, `displayName`, one-line `summary`, and a
   `thumbnailProgress` where the style is recognisable. Declare `needsSnapshot =
   false` and `isTransparent = true` if it composites over the live desktop.
3. Register it in `TransitionCatalog.make()` and with one `register(...)` line in
   `TunerHost`. Built-in presets go in `BuiltInPresets`; then run
   `swift run shut --export-presets presets`.
4. Add it to the sweeps in `RenderTests` (image styles or mask styles). Run
   `swift test`, and dump frames with `SHUT_FRAME_DUMP` to look at them.
5. Add a row to the styles table in `README.md`.

## Before you open a pull request

```bash
swift build
swift test
xcodebuild -project Shut.xcodeproj -scheme Shut build
```

If you touched a layout, dump the snapshots (`SHUT_FRAME_DUMP=/tmp/shut swift test`)
and look at `popover-dark.png`, `popover-light.png`, `popover-window.png` and
`tuner-panel.png`. If you touched the overlay, the sensor, or sleep handling, run
the manual checklist in `README.md` on a real MacBook and say which steps you ran.

## Conventions

See `CLAUDE.md`: readable over clever, comments explain reasoning, no third-party
dependencies (Sparkle, for updates, is the one exception), never write screen content to disk, Tuner never imports app code,
the overlay only ever touches the built-in display. Match the panel's visual system
(`TunerTheme`): 36-pt rows, neutral alphas, no accent colour, help text on every
control.

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
8. Install the final DMG on a Mac, or a macOS user account, that has never built
   Shut, and open it. `scripts/smoke.sh` imitates this; do the real thing as well.

Console.app, subsystem `app.shut`, shows every decision: capture, overlay placement
(and the fallback if macOS put it on the wrong Space), poll rate changes, teardown
reasons, and the safety rule. No pixels are ever logged.

## Releases

`App/Info.plist` holds the version. Bump `CFBundleShortVersionString` and
`CFBundleVersion` (Sparkle compares the latter), add a section to `CHANGELOG.md`
(it is also the GitHub release notes, the notes in Sparkle's update window and the
"What's new" card in the app, via `scripts/release-notes.sh`: open it with a
**bold title.** and its sentence, then points that each start with a short claim),
and push to `main`. The Release workflow tests, builds, packages a DMG with a
SHA-256 and opens a *draft* release named `v<version>`. Its DMG is ad-hoc signed
and cannot be notarized, so the rest happens on a Mac with the Developer ID:

1. `SHUT_SIGN_IDENTITY="Developer ID Application: …" scripts/notarize.sh` builds,
   notarizes and staples the app and the DMG into `build/releases/`. It runs
   `scripts/smoke.sh` first: the app is copied away from the build directory and
   `Shut --self-check` has to find its fonts, shaders and images from there.
2. On the draft release, replace the CI DMG and `.sha256` with those two files.
   Do this after the Release workflow has finished, and do not push to `main`
   again before publishing: every push re-runs it and overwrites the assets.
3. Run the Appcast workflow (Actions → Appcast → Run workflow). It signs the DMG
   now on the release with the Sparkle private key, which exists only as the
   `SPARKLE_PRIVATE_KEY` secret, and replaces `appcast.xml`. An appcast made
   locally with a different key is rejected by every installed copy.
4. Publish the release. Installed copies see the update within a day; the site
   pins the download URL in its `src/site.ts`, so bump that too.

Pushes to other branches and pull requests run the Build workflow and attach the
DMG as an artifact. Locally: `scripts/build.sh --zip` or `scripts/package-dmg.sh`;
`scripts/version.sh` prints the version.
