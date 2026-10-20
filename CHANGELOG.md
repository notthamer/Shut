# Changelog

## 0.4.0

**Lid sound.** Close the lid and a sound plays: it starts as the lid comes down and ends as it lands. Three sounds come with the app; add your own, and with several Shut picks one each time. Off until you turn it on.

- It ends with the lid. The sound starts the moment the closing effect does and fades out in the last few degrees, so it lands with the lid whatever its length. Speed, on Lid effects, sets how early it starts. Lift the lid back up and it fades out.
- Your sounds. Add a sound… or drop files on the list: mp3, m4a, wav or aiff, copied into Shut so the original can move. Each has its own switch, a ▶ to hear it, and an × to remove it. Cut parts out of any sound, as many as you like, each with its own name; double-click a name to rename it. A long file plays from where you choose, up to 30 seconds.
- Random, or in order. Random never plays the same sound twice running; in order goes down the list, and the list reorders by hold and drag.
- Starts at: the angle where the sound begins, always shown as a number. The same as the screen effect's Speed, so the two begin together, or an angle of its own.
- Its own volume: Shut sets your Mac's volume to the dial for the sound and puts it back when it ends, so the dial is the level you hear whatever the Mac is set to. Or, under Settings, a share of the Mac's volume as it is. Let go of the slider to hear it.
- Muted Mac: your call. Stay quiet (the page and the tab say "Muted"), or Unmute for it, and mute comes back when the sound ends.
- Also on open: a sound as the desktop pours back in after you unlock. The close's pick again, or one in particular.
- A third tab, Lid sound, beside Lid effects and Stay awake, with the three bars that move while a sound plays, and "Play a Sound on Close" in the menu.

**Also**

- Stay awake is on for one close at a time: switch it on before you close the lid; when you open the lid again it switches itself off, and a launch never finds it on. A switch left on by mistake had kept a Mac awake through every close for days. The way you chose and the time on the dial are remembered. "Until I stop" on the dial now means until the lid opens.

## 0.3.1

**Stay awake is on for one close at a time.** Switch it on before you close the lid; when you open the lid again it switches itself off, and a launch never finds it on. A switch left on by mistake had kept a Mac awake through every close for days. The way you chose and the time on the dial are remembered, so arming it again is one flick. "Until I stop" on the dial now means until the lid opens.

## 0.3.0

**Stay awake.** Close the lid while something is working and your Mac stays awake, then goes to sleep by itself when the work is done. Off until you turn it on. No password, no helper to install.

- Reasons, not timers. Your Mac stays awake while an app is busy (a coding agent, a build, a render, a download), while an external display is connected, while apps you pick are open, or for a set time: one click, from five minutes to twelve hours or until you stop it, and the time starts each time you close the lid, so "two hours" means two hours after you shut it. One click back to automatic.
- You always know what the lid will do. Shut has two sections now, Lid effects and Stay awake, named in the header, and a pair of eyes beside the second: open, your Mac will stay awake; shut, the lid will sleep it. The page says it in words too: "Closing the lid keeps your Mac awake." The menu bar icon carries a dot while holding, a ring while winding down, and Saffron when a limit is near.
- The closing screen says what will happen. "Staying awake · Claude Code is working", readable on any wallpaper. Hold Option at any point of the close to do the opposite, just that once.
- When you come back, Shut tells you what happened. A slip under the menu bar icon: how long, from when to when, for what, and the battery it used.
- An app that asks to stay awake and is not allowed yet (a call, a recording) is asked about once: Allow, or Not this app.
- Limits that always win: a battery level you choose, heat, eight hours on battery, Low Power Mode. When the battery is under your level, Shut says so with both numbers. It locks the screen as the lid shuts.
- Safe to leave: if Shut quits, updates, crashes or is force-killed while keeping your Mac awake, lid sleep is given back to macOS.
- Only on Macs with a lid.
- A new first run: pick how your Mac closes and watch it, turn Stay awake on or leave it, and you are set.

**Also**

- The main page is rearranged: Speed and Animate opening sit under the preview they change, the master switch is labelled "Lid effects", and a style waiting for Screen Recording says so in a calm card with one next step.
- App settings (open at login, Dock icon, updates) moved behind a gear in the footer.
- The version is in the panel's footer, beside Quit. Click it to copy what a bug report needs: app version, macOS, Mac model.
- The welcome says where Shut goes afterwards: your menu bar.

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
