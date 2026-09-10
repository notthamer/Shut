# Sinkhole: Claude Code Prompts

Use one prompt per milestone. Between milestones, commit your work and type `/clear` in Claude Code to start fresh. Every prompt asks Claude to plan first, so read the plan before approving.

---

## Setup (run in Terminal)

```bash
mkdir -p ~/Developer/sinkhole/docs && cd ~/Developer/sinkhole
git init
mv ~/Downloads/PRD-sinkhole-v0.3.md docs/PRD.md
claude
```

---

## M0: Lid sensor CLI

```text
Read docs/PRD.md fully. This is an open-source, MIT-licensed, build-in-public project. Do milestone M0 only.

Show me your plan before writing code.

1. Create a Swift Package at the repo root. Add a library target `LidSensor` and an executable target `lidangle-cli`. No third-party dependencies.
2. Write the sensor code from scratch with IOKit HID (don't copy code from samhenrigold/LidAngleSensor; it's Apache-2.0). Match VendorID 0x05AC, ProductID 0x8104, UsagePage 0x0020, Usage 0x008A. Read feature report ID 1 and decode bytes 1-2 as a little-endian UInt16 angle in degrees. This layout is unverified, so add a --debug mode that prints raw report bytes.
3. LidSensor should publish the smoothed angle and angular velocity, with adaptive polling (10 Hz when stable, up to 120 Hz when the angle is changing).
4. CLI modes:
   - default: live angle on one updating line
   - --report: model identifier (sysctl hw.model), macOS version, sensor found yes/no, 5 seconds of samples, formatted for a GitHub issue
   - --log <file.csv>: append timestamp,angle per sample and flush immediately
5. If no sensor is found, print a friendly message and exit cleanly.

Also create: MIT LICENSE, Swift .gitignore, README stub with a Credits section, and CLAUDE.md with conventions: readable over clever, comments explain design reasoning, no third-party dependencies, never write screen content to disk, the Tuner target must never import app code.

Run swift build, then give me the exact commands to test each mode.
```

**After M0:** run `swift run lidangle-cli --log angles.csv`, close the lid slowly until the screen turns off, then check `tail -5 angles.csv`. Tell Claude that angle in the next prompt.

---

## M1: App pipeline

```text
Read docs/PRD.md and CLAUDE.md. M0 is done. On my Mac the display turns off at about [YOUR ANGLE]°. Do milestone M1 only.

Plan first.

Build the Sinkhole menu bar app (SwiftPM executable plus a build.sh that bundles it into Sinkhole.app with an Info.plist and ad-hoc signing):
1. Menu bar extra with enable toggle, live angle readout, Open Preview, Quit.
2. TransitionKit library: a `Transition` protocol and a shared Metal renderer (full-screen quad, snapshot texture, uniform buffer) per PRD section 5.2. Implement one simple `FadeTransition` to prove the pipeline.
3. Close flow per section 5.6: arm near start angle, capture the built-in display with SCScreenshotManager excluding our windows, show a borderless click-through overlay at .screenSaver level on all Spaces, render every frame with a display link, drive progress from the lid angle.
4. Reverse with the lid and tear down on reopen with 5° hysteresis.
5. Sleep safety: on willSleep or screensDidSleep, hide the overlay and release the snapshot. Add the 500 ms sensor watchdog.
6. Preview window: shows the current transition on a snapshot of the desktop with a progress scrub slider and a Follow Lid toggle.
7. Screen Recording permission check with a button that opens the right System Settings pane.

Build it, then give me a manual test checklist including 50 close/open cycles.
```

---

## M2: Notch Drain

```text
Read docs/PRD.md and CLAUDE.md. M1 is done. Do milestone M2 only.

Plan first.

1. Implement `NotchDrainTransition` using the shader sketch in PRD section 5.4: falloff, twist, funnel stretch, contraction toward the sink, motion blur samples, darkening, chromatic aberration, and rim glow around the notch.
2. Notch detection per section 5.3 using NSScreen.auxiliaryTopLeftArea and auxiliaryTopRightArea. On Macs without a notch, fade in a pill-shaped virtual notch at the top center.
3. Put all parameters in a `NotchDrainParams` struct with the defaults from section 4.5. For now, expose them as temporary sliders in the Preview window; the real Tuner comes in M3.
4. Add a transition picker (Fade / Notch Drain) to the Preview window and menu bar.
5. Comment the shader thoroughly: explain what each term does visually, since this code will be shown publicly.

Build, then tell me which parameters to try first in the preview to judge whether it looks right.
```

**Tip:** if something looks off, take a screenshot of the preview window (⌘⇧4, then Space, then click the window) and tell Claude: "Look at ~/Desktop/Screenshot.png — the swirl is too strong near the edges."

---

## M3: Tuner panel

```text
Read docs/PRD.md and CLAUDE.md. M2 is done. Do milestone M3 only.

Plan first, and show me the proposed Tuner API with a short usage example before implementing.

1. Create a `Tuner` library target with zero imports from the app or TransitionKit. It's inspired by Josh Puckett's DialKit (web), rebuilt natively in SwiftUI. Don't use the DialKit name anywhere in code.
2. Declarative schema: parameter structs describe their controls with key paths, ranges, defaults, and folders.
3. Controls: slider with range, toggle, color picker, spring editor (response and damping with a live curve preview), Bézier easing editor with draggable handles, segmented picker, action button.
4. Floating collapsible NSPanel, opened from the menu bar or with ⌃⌥T. It hides automatically while a real lid transition plays.
5. Persist values in UserDefaults per transition. Presets per section 4.6: save, load, duplicate, delete, copy JSON to clipboard, import by paste or file drop. Store in ~/Library/Application Support/Sinkhole/Presets.
6. Move the preview controls into Tuner: progress scrub, Play Close, Follow Lid, transition picker, and action buttons for Replay and Reset Group.
7. Replace the temporary M2 sliders with the Tuner schema for NotchDrainParams, and add three built-in presets: Gentle, Default, Black Hole.

Build, then write a short README section explaining how to add Tuner controls to any SwiftUI app.
```

---

## M4: Frost transition

```text
Read docs/PRD.md and CLAUDE.md. M3 is done. Do milestone M4 only.

Plan first.

1. Implement `FrostTransition` on the shared renderer per PRD sections 4.3 and 4.5: image locked in space with no scaling, progressive blur that leads from the top edge toward the hinge, and darkening. Use a blur mip chain built once at capture time so per-frame cost stays constant.
2. Add a Tuner schema for FrostParams and three built-in presets.
3. Add Frost to the menu bar and Tuner transition pickers.
4. Respect Reduce Motion (simple fade) and Reduce Transparency (no blur) for both transitions.

Build and profile: tell me the frame time for both transitions in the preview at full screen.
```

---

## M5: Pour-out on unlock

```text
Read docs/PRD.md and CLAUDE.md. M4 is done. Do milestone M5 only.

Plan first, and list any undocumented APIs you rely on and how you'll verify them.

1. Implement the pour-out flow from PRD section 5.7: black drained overlay on sleep, stays beneath the lock screen on wake, fresh snapshot after unlock excluding the overlay, then spring from p = 1 to 0 with overshoot (negative q) using the Pour-out parameters.
2. Handle Macs with no password on wake: play pour-out right after wake.
3. The safety rule is non-negotiable: if the black overlay is visible for more than 1.5 s while unlocked and awake, force-hide it. Add logging (no screen content) so I can debug failures.
4. Add Play Pour-out to Tuner's preview.
5. Add the commit threshold behavior from section 5.5.

Build, then give me a test plan covering: lid close and open with a password, without a password, reopening before sleep, sleeping from the Apple menu instead of the lid, and 100 rapid cycles.
```

---

## M6: Release

```text
Read docs/PRD.md and CLAUDE.md. M5 is done. Do milestone M6 only.

Plan first.

1. Polish the README: demo video placeholder at the top, one-line description, supported hardware, install from source, how Notch Drain works (with the shader math explained simply), how to use Tuner, how to submit presets, and Credits (LidAngleSensor, DialKit as inspiration for Tuner, existing Duo clones).
2. Create presets/ with the built-in presets as JSON, plus a CONTRIBUTING.md explaining how to submit a preset or a new transition.
3. Add a GitHub issue template for sensor compatibility reports that asks for lidangle-cli --report output.
4. Make build.sh produce a versioned Sinkhole.app and a zip for GitHub Releases.
5. Review the whole codebase for readability, dead code, and missing comments, since it's a public portfolio piece. List anything you'd fix before tagging v1.0.
```
