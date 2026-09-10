# Contributing to Sinkhole

Thanks for stopping by. Two kinds of contribution are especially welcome.

## Submitting a preset

1. Open Tuner (menu bar → Open Tuner, or ⌃⌥T), dial in your look, and click the
   save icon to name it.
2. Choose **Copy JSON** from the ⋯ menu, or find the file in
   `~/Library/Application Support/Sinkhole/Presets/<transition>/`.
3. Add it to `presets/<transition>/<your-preset-name>.json` in this repo. The file
   looks like:

   ```json
   {
     "name" : "Black Hole",
     "transition" : "notchDrain",
     "values" : { "twist" : 1.4, "falloff" : 1.8, ... }
   }
   ```

4. Open a pull request with a one-line description and, ideally, a short clip.

Presets are loaded by Tuner's **Paste JSON** or by dropping the file onto the panel.

## Adding a transition

A transition is one Swift file and one Metal fragment function.

1. **Params.** Add a `struct MyParams: TunableParameters` in `Sources/TransitionKit/`
   with defaults and a `schema` describing its controls (see `NotchDrainParams`).
2. **Transition.** Add `final class MyTransition: Transition` with `id`,
   `displayName`, `fragmentFunctionName`, and `uniforms(progress:context:)` that
   packs your params into `TransitionUniforms`. If you need per-snapshot work
   (a blur pyramid, a lookup texture), override `prepare(snapshot:device:commandQueue:)`.
3. **Shader.** Add `Sources/TransitionKit/Shaders/MyTransition.metal` with a fragment
   named as above. `Common.metal` is concatenated first, so `TransitionUniforms` and
   `VertexOut` are already in scope. Comment it as if explaining it to a designer.
4. **Register.** Add it to `TransitionCatalog.make()` and give it a store in
   `TunerHost` (three lines). Optionally add built-ins to `BuiltInPresets`.
5. **Test.** Add a case to `RenderTests` asserting the broad shape (starts intact,
   ends black). Run `swift test` and, if you like, dump frames with
   `SINKHOLE_FRAME_DUMP`.

## Conventions

See `CLAUDE.md`: readable over clever, comments explain reasoning, no third-party
dependencies, never write screen content to disk, Tuner never imports app code.
