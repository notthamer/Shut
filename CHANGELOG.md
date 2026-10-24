# Changelog

## 0.4.2

**The stage says what to do, and In order shows what comes next.** The Lid sound page's two sections are named for what happens, "On close" and "Add from packs", and the stage shows its queue.

- Where sounds go is said, not guessed. An empty stage is a drop zone with a dashed outline that says so; the moment a drag leaves a pack, the stage says "Drop here"; the plus beside a sound in a pack reads "+ Lid", since a bare plus read as "add to this list", the opposite of what it does; on the first visit a pack is already open, with one line under it saying how, gone after the first sound is put on the lid; and while nothing is on the lid, the packs from Shut stay unfolded.
- In order shows its queue. Each row carries its number, the one the next close plays is tagged NEXT (in Random, the one that just played is tagged LAST), the band has a "Next up · Breath" line of its own, the tab reads "In order · next Breath", and a row's menu has "Play this next".
- Edit's mark is a filled circle, not a check.

## 0.4.1

**The stage and the packs.** The Lid sound page is laid out the way a music app is: "On the lid" is what plays, "Packs" are the playlists, and a sound is dragged from one onto the other.

- On the lid, on the left, is the short list a close picks from. Random never repeats, In order walks down it, hold and drag to reorder; it never leaves the screen, and Timing and Settings fold under it. Edit ticks several sounds and takes them off the lid at once; a sound taken off the lid goes back to its pack, and only your own files can be deleted, which the menu says.
- Packs, on the right, are playlists. Your own first, with "New pack…" at the foot and Rename and Remove pack under each one you made (its sounds go to Mine); the ones that came with Shut folded under them as "From Shut"; one open at a time. Drag a sound onto the lid and it lands where you drop it, or drag the whole pack and every sound in it lands there together, or press + beside one; a sound on the lid carries the three-bar mark, and a click on it takes it off. "Play this pack" makes the lid play that pack and nothing else; "Add all" adds the lot. A pack is a playlist, never a switch: nothing to add or remove, and one sound from each of nine packs is nine drags.
- Add a sound where you want it. "Add a sound…" over the stage puts your file straight on the lid, no pack to choose; every open pack has its own "Add a sound…" and takes dropped files, into that pack.
- Nothing you had is lost. "Plays from", "More from Shut" and the Library are gone; what they did is now one thing, on the lid or in its pack. An existing list comes over whole: whatever played still plays, and a sound that was kept for later, hidden, or in a pack you had put away is in its pack, off the lid.

**Sixty-seven new sounds, computed, not recorded.** Blob, Pop, Boing, Coin and CRT off join Click, Breath and Hum in the Starters pack, on the lid from the first launch. Six more packs: Pops (Plop, Bloop, Bubble, Cork, Drip, Squelch), Toys (Slide whistle, Bonk, Squeak, Sad trombone, Kazoo, Honk, Door stop), Machines (Power down, Vault, Car door, Camera, Typewriter, Cash register, Zipper, Latch, Steam, Ding), Retro (Jump, Game over, Glitch, Warp, Modem, Morse, Laser, Level up), Night (Yawn, Snore, Lullaby, Wind chime, Gong, Owl, Crickets, Candle) and Encore (Applause, Ta-da, Drum roll, Ba-dum-tss, Dun dun dun, Record scratch, Boom, Whistle). Every one is made by `scripts/make-sounds.swift` from a few lines of arithmetic, so there is nothing to license, and all of them together add under a megabyte.

- Close the lid fifteen times and it plays Ode to Joy. One pack is a tune, one note per sound: Play this pack, choose In order, and each close is the next note.
- Updates come sooner: Shut looks for a new version about once an hour instead of once a day, and once a few seconds after it starts. And "Check for updates" sits in the panel's footer, beside the version, for whoever heard of a release first; before, it was only in the menu bar icon's right-click menu.
- Cutting is clearer: the two edges have handles, the pointer says what a drag would do, the handle in hand shows its time, and when a sound has silences in it the editor says how many parts they make and offers to split there, before you ask; the parts it finds are a start, not a verdict: click one, drag the handles to fix it, or × to leave it out, then name and add.
- The apps that hold every sleep for 30 s are named before they do it. Logitech Options+ and G Hub never answer macOS when the lid closes, so a second close inside 30 s does nothing; quitting their windows does not stop their agents, and Login Items does not either. While one is running, both pages say so, with a "Stop" that takes it out of launchd for this session and the next login, no password, and quits it: your mouse keeps working, and opening the app brings it back. And while a sleep is still going, the page names who is holding it, not only after.
- The Lid sound glyph is smoother: its bars sit on the pixel grid, and it breathes at thirty frames a second instead of fifteen.

## 0.4.0

**Lid sound.** Close the lid and a sound plays: it starts as the lid comes down and ends as it lands. Eight sounds come with the app, five adhkar among them; add your own, and with several Shut picks one each time. Off until you turn it on.

- It ends with the lid. The sound starts the moment the closing effect does and fades out in the last few degrees, so it lands with the lid whatever its length. Lift the lid back up and it fades out. Or, under Extras, Play to the end: your Mac waits for the sound, then sleeps at once, so a two-second sound is heard whole however fast the lid comes down.
- Your sounds. Add a sound… or drop files on the list: mp3, m4a, wav or aiff, copied into Shut so the original can move. Each has its own switch, a ▶ to hear it, and an × to remove it. Cut parts out of any sound on its waveform, as many as you like, each with its own name, or let Shut find the parts by the silence between them and name them in one go; double-click a name to rename it. A long file plays from where you choose, up to 30 seconds.
- Random, or in order. Random never plays the same sound twice running; in order goes down the list, and the list reorders by hold and drag.
- Packs. Sounds come in packs (Click, Breath, Hum to begin; the adhkar folded under the list as More from Shut, for whoever wants them) and yours live in Mine; make more, move sounds between them, take any pack out with one click, and choose what the lid plays from: every pack, or one. A library keeps a sound for later, out of the list, one click from coming back.
- Starts at: the angle where the sound begins, always shown as a number. The same as the screen effect's Speed, so the two begin together, or an angle of its own.
- Its own volume: Shut sets your Mac's volume to the dial for the sound and puts it back when it ends, so the dial is the level you hear whatever the Mac is set to. Or, under Settings, a share of the Mac's volume as it is. Let go of the slider to hear it.
- Muted Mac: your call. Stay quiet (the page and the tab say "Muted"), or Unmute for it, and mute comes back when the sound ends.
- Also on open: a sound as the desktop pours back in after you unlock. The close's pick again, or one in particular.
- A third tab, Lid sound, beside Lid effects and Stay awake, with the three bars that move while a sound plays, and "Play a Sound on Close" in the menu. The page scrolls once per column: the list is as long as it is, with Add a sound… in its heading, and Starts at has its own place on the right over Settings.

**Also**

- When a sleep is still finishing from the last close (an app that never answers macOS holds every sleep open for 30 s; Logitech Options+ and G Hub do), the lid does nothing: the tabs, both pages, the closing caption and the menu bar mark now say "Still going to sleep", and after such a sleep a note names who held it up.
- Stay awake is on for one close at a time: switch it on before you close the lid; when you open the lid again it switches itself off, and a launch never finds it on. A switch left on by mistake had kept a Mac awake through every close for days. The way you chose and the time on the dial are remembered. "Until I stop" on the dial now means until the lid opens.

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
