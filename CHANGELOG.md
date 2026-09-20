# Changelog

## 0.2.1

- Fixed: Shut quit the moment it opened on every Mac except the one it was built on. It looked for its fonts in a folder that only exists there. 0.1.0 and 0.2.0 are both affected, and because they quit before they can check for updates, this version has to be downloaded by hand.
- A missing font now falls back to the system font instead of stopping the app.
- Every build is now tested away from the machine that made it before it is released.

## 0.2.0

- Speed runs from 20° to 130°, so an effect can begin the moment the lid starts to move. The number is where it really starts on your Mac.
- Above the start angle nothing happens any more: the desktop stays live until the lid reaches it.
- Fold goes out of focus from the first degrees, the way a folding phone does. A new Blur onset dial sets how soon; heavy blur is smoother.
- Picking a style plays it in the preview. Moving a dial shows the change straight away. Letting go of Speed replays a close at that speed.
- Fixed: the Speed slider in the main window did not change the real close, only the Tuner's dial did.
- Fixed: Fold presets from an earlier version load, with any new dial at its default.

## 0.1.0

First release.

- Eight ways to close your Mac: Fold, Sinkhole, Frost, Crease, Recede, Slide, Shutter, Fade.
- Follows the hinge on Macs with a lid angle sensor; plays on lid events on the rest.
- Sinkhole pours the desktop back out of the notch when you unlock.
- Every dial for every style in the panel, with named presets you can copy, paste, import and export.
- Menu bar and Dock. Open at login. Nothing runs until the lid moves.
- In-app updates.

Requires macOS 14 or later on an Apple silicon MacBook.
