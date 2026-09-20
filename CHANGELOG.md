# Changelog

## Unreleased

- Stay awake: close the lid while something is working and your Mac stays awake, then sleeps by itself when the work is done. Reasons, not timers: an allowed app asking macOS to stay awake, an external display, apps you pick, "I say so", or `shut hold` in a terminal. No password and no helper.
- The closing screen says what will happen ("Staying awake · Cursor is working"), and a short receipt says what happened when you come back. Hold Option while closing to flip the decision once.
- The main page is rearranged: Speed and Animate opening sit under the preview they change, the master switch is labelled "Lid effects", and a style waiting for Screen Recording says so in a calm card with one next step.
- The version is in the panel's footer, small, beside Quit. Click it to copy the details a bug report needs: app version and build, macOS, Mac model.
- The welcome says where Shut goes afterwards: your menu bar.
- The Awake page shows what keeps your Mac awake without a click: an app is busy, a display is connected, an app you pick is open, or you say so. The one at work right now says so.
- "You say so" is one dial: from five minutes to twelve hours, or until you stop it. The line under it says when it ends, and the thumb counts down.
- A pair of eyes in the Awake bar and on the Awake page: open when your Mac will stay awake, shut when the lid will sleep it.
- When you come back, a slip under the menu bar icon says what happened while the lid was shut, once the screen is unlocked. It fades by itself.
- An app that is asking to stay awake and is not allowed yet (a call, a render) is asked about once, in the bar and on the Awake page: Allow, or Not this app.
- The menu bar icon shows a dot while holding, a ring while winding down and Saffron when a limit is near or has spoken. Its tooltip says what is working.
- The closing caption is readable on any wallpaper, bad news is set in Saffron, and Option works at any point of the close (press again to take it back). The first few closes show how.
- Limits that always win: a battery floor, heat, eight hours on battery, Low Power Mode. Locks when the lid shuts. Off until you turn it on.

## 0.2.1

- Fixed: Shut quit the moment it opened on every Mac except the one it was built on. It looked for its fonts in a folder that only exists there. 0.1.0 and 0.2.0 are both affected, and because they quit before they can check for updates, this version has to be downloaded by hand.
- The fonts now reach the app two separate ways (macOS loads them at launch, and Shut loads them itself as a backup), and a build where any of them is missing cannot be released.
- If a font ever did go missing, that text is set in the system font at the same size and weight, and the app keeps running.
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
