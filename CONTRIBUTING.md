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

1. Open **Tune everything…**, dial in your look, choose **New version** to save it.
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
dependencies, never write screen content to disk, Tuner never imports app code,
the overlay only ever touches the built-in display. Match the panel's visual system
(`TunerTheme`): 36-pt rows, neutral alphas, no accent colour, help text on every
control.
