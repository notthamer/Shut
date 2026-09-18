# Shut.

Ways to close your Mac.

Shut plays a little animation on your screen as you close the lid, and it follows
the hinge. Close slowly and it crawls. Open halfway and it reverses. Unlock and
the desktop pours back in.

<!-- video -->

**[Download for Mac](https://github.com/notthamer/shut/releases/latest)** · macOS 14 or later · Apple silicon MacBooks · Free, MIT

## Styles

| | |
| --- | --- |
| **Fold** (iPhone Duo) | The desktop stands still while the machine folds away under it. The default. |
| **Sinkhole** | Swirls into the notch, then pours back out when you unlock. |
| **Frost** | Frosts over from the top edge and fades to black. |
| **Crease** | A book fold across the middle. |
| **Recede** | Drops straight back into the dark. |
| **Slide** | Slides down behind the hinge. |
| **Shutter** | Bars close in from the top and bottom. |
| **Fade** | A plain dim to black. |

Pick one in the panel, set the speed, and adjust its dials if you like. Every
dial for every style is right there, with presets you can name, copy, paste,
import and export.

## Stay awake

Close the lid while something is still working (a coding agent, a render, an
external display) and your Mac stays awake, locks, and goes to sleep by itself
when the work is done. The closing screen tells you which it will be. No timers
to set, no password, off until you turn it on; a battery floor and a heat cut-off
always win. [How it works, and its limits](docs/AWAKE.md).

## How it works

- Click the menu bar icon for the panel, or open Shut from the Dock for the same
  panel as a window.
- Styles that redraw your desktop ask for **Screen Recording** once. Shut takes a
  single still as the lid starts to move, keeps it in memory, and throws it away
  when the animation ends. Nothing is saved, nothing is sent anywhere.
- At rest it does nothing: the hinge is read once a second and no frame is drawn
  until the lid moves. On a MacBook without a lid angle sensor, the style plays
  when the lid closes instead of following it.
- The effect only ever plays on the MacBook's own screen, never on a monitor.

## Build it yourself

```bash
git clone https://github.com/notthamer/shut
cd shut
scripts/build.sh
open build/Shut.app
```

Or open `Shut.xcodeproj` in Xcode and press Run. A build from source works the
same as the download, minus automatic updates.

## More

- [How the hinge is read, what it costs, and the safety rules](docs/HINGE.md)
- [How Sinkhole works](docs/SINKHOLE.md)
- [Stay awake: reasons, limits, and how the lid is held](docs/AWAKE.md)
- [The Tuner, and using it in your own app](docs/TUNER.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Contributing, presets, testing, releases](CONTRIBUTING.md)

Check your lid sensor with `swift run lidangle-cli`, and `--report` formats the
result for an issue.

## Licenses

MIT. Third-party licenses are in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
