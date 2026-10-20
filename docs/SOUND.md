# Lid sound

Close the lid and a sound plays: it starts as the lid comes down and ends as it lands.
Add any audio file; with several, Shut picks one each time. Optionally a sound when the
lid opens. Off until you turn it on.

## What you see

- **A tab, "Lid sound"**, between Lid effects and Stay awake, with the feature's face:
  three bars, still at rest, moving only while a sound plays (`LidSoundGlyph`; a pure
  function of time, a clock only while on screen, stilled by Reduce Motion). Its second
  line is the state in a few words: "Off", "Click · On", "3 sounds · random", "3 sounds ·
  in order", "Muted", "Playing Click…", "No sound chosen", "No sounds yet"; on a Mac that
  only reports the lid shut, "Click · after the lid shuts". Three tabs share the header, so
  each gets 102 points and its line truncates, with the whole of it in the tooltip and the
  accessibility label; the wordmark never gives.
- **The page answers "what will closing do?"** in the same words every time: "Closing the
  lid plays Click." / "Closing the lid plays one of 3 sounds." / "Closing the lid plays 3
  sounds in turn." / "Closing the lid is silent." / "Your Mac is muted, so closing is
  silent." Under it, one sentence: it starts as the lid comes down and ends as it lands;
  a different one each time, or which is next; that opening plays one too; and where the
  sound goes ("Through AirPods Pro."). One action: Turn on; Try it (the sound the next
  close would play, while the preview window plays the close); or, muted, Change, which
  opens Settings.
- **Pick and Volume**, on the right of the band, and nothing else, so the band is short
  (248 pt, under Stay awake's 320) and nothing in it scrolls. Random never plays the same
  sound twice running; In order goes down the list. Volume is Lid sound's own, as a share of
  the Mac's, which Shut never changes; letting go of the slider plays the sound at that
  level. What the dial means is a choice under Settings: **Of the Mac's** (a
  share of the Mac's volume as it is, so a quiet Mac means a quiet lid; the line under the
  dial says the Mac's level now) or **Its own level** (the default: Shut sets the Mac's volume to the
  dial for the sound, with the player at full, and puts it back when the sound ends; the
  old value is written to defaults first, so a sleep in between still gets it put back at
  the next launch, on the same output only). Outputs with no volume Shut can set keep the
  dial a share.
- **02 Timing**, the lower right, always in view over the folded Settings: Starts at is
  the angle above shut where the sound begins, always shown as a number:
  with "Same as the screen effect" on (the default) it is Speed's angle from Lid effects, so
  the sound and the screen begin together; off, the dial sets the sound's own angle, 20° to
  130°, and the hinge, not the overlay, says when. The answer at the top says it too: "It
  starts as the lid passes 60°".
- **01 Sounds**: the list, a well as long as the list is. The column scrolls, once; the
  well never scrolls inside it (it did, at four and a half rows, and six sounds made a
  scroll inside a scroll). Each row has a ▶ to hear it, its name, its length, a switch, and
  a … menu. A row at work is in ink with a Lime dot. A file that went missing says
  "Missing", with the switch off and disabled; one Core Audio cannot open says "Can't be
  played". "Add a sound…" sits in the section's heading, so it is there before the list is
  scrolled (a file panel; the popover stays open around it); its tooltip carries the rule:
  mp3, m4a, wav or aiff, or drop files on the list. Rows reorder by hold and drag: a grip shows
  when the pointer is near; hold the name a moment and the row lifts onto Linen and follows
  the pointer, the others step aside a row at a time (they jump, as the eyes jump between
  frames; nothing eases into place), and letting go keeps the order, which is what "In
  order" plays down. VoiceOver gets Move up and Move down on each row. The old rule line:
  m4a, wav or aiff, 30 s at most, or drop files on the list. A refused import says why in
  one Saffron line: too long, unreadable, already in the list, could not be copied.
- **02 Settings**, folded, with a summary ("Silent on open · stays quiet when muted").
  Opened: "On open" (Also on open, and which: the close's pick again, or one in
  particular), "When the Mac is muted" (Stay quiet, or Unmute for it), and "Extras" (how
  the sound ends with the lid, and "Restore the starter sounds" once one has been removed).
- **The menu bar menu** has "Play a Sound on Close" with a checkmark. The closing caption
  stays Stay awake's.
- **The update tour** for 0.4 has one slide: the glyph, the sentence, and a Play button
  that plays Click through the slide's own player.

## How it is timed

The lid controller already knows four moments; Lid sound listens to them and to the hinge:

| Moment | What Lid sound does |
| --- | --- |
| The lid starts to come down (`onLidStartedClosing`, progress > 0.003) | Picks the sound and wakes the audio hardware (`prepareToPlay`), hundreds of milliseconds before anything is heard. |
| The overlay appears (`onCloseBeginning`) | Plays, at the volume set. |
| The hinge reaches progress 0.9, a few degrees above shut | A 300 ms fade-out, so the sound lands with the lid. |
| The lid comes back up 0.05 from its lowest point | A 150 ms fade-out: the user changed their mind. |
| A close ends without the lid shutting (`onCloseEnded`: reopened to the top, the sensor went quiet, the display left, the feature was switched off, quit) | A prepared sound is dropped; a playing one fades out. |
| The opening begins (`onOpeningBeginning`: the pour-out after unlock, or the moment it would have begun with Animate opening off) | With "Also on open", plays the open's pick. |

The hinge, not the overlay's driver, is the fade source: a style's curve can read 0.9
while the lid is still half open, and "near shut" is about the physical lid. The
controller sinks the sensor's state while the feature is on, a stream that fires only on a
new sample and parks at 1 Hz when idle; nothing is read per frame.

With Lid effects off there is no overlay and its hooks never fire; the same pure state
machine (`LidSoundCue`) then starts the sound when the hinge crosses the threshold the
overlay would have used, so Lid sound works on its own.

One sound per close. Once a close's sound has played, the cue is spent until the lid comes
back up to a quarter of the band (a lid lifted halfway and closed again is a new close), and
a wake forgets it.

A close while a sleep from the last close is still finishing (see "When the Mac takes 30 s
to sleep" in `docs/AWAKE.md`) plays its sound as usual, but cannot sleep the Mac; the page
and the tab say "Still going to sleep" meanwhile, and the sound's line adds "The sound still
plays." Without that, a
Mac awake with the lid down, held by Stay awake or a few seconds from sleep, replayed the
sound from the hinge every 0.3 s: play, land-fade, play again, and sleep came late behind
the audio.

Why "ends with the lid": after the lid is physically shut, macOS sleeps on its own
schedule, usually within about a second, and no power assertion delays lid sleep. Anything
that must be heard has to be done by the time the lid lands, so the fade starts a few
degrees before. A sound shorter than the close simply ends. A very fast slam can still end
in a hard cut when sleep arrives first. Lid sound does not touch the kernel lid bit.

Macs without an angle sensor only report the lid shut, so the close plays on a timeline
after the lid is already down: the sound starts then, the landing fade is off (progress
jumps straight to 1), and sleep may cut it. The page says so on those Macs. Macs without a
lid get no Lid sound tab.

## If something is already playing

The lid sound plays over it. macOS mixes every app's audio and gives no app a way to turn
another down, so music or a call keep going and the lid sound is heard on top, at its own
volume. Nothing is paused, nothing is ducked.

## Audio off the main thread

Every call to `AVAudioPlayer` goes through one serial queue, and the player itself is made
there on first use. Measured on a MacBook Pro with AirPods as the output: the first `play`
after a wake blocked for fifteen seconds while Bluetooth came back, and the opening
animation froze behind it. The opening's sound is now made and prepared at wake
(`warmTheOpening`), so the unlock only has to play it; if the output is still coming back,
the queue waits, not the screen.

## Muted

Playback is silent while the Mac is muted or its volume is at zero, so the page says
"Muted" rather than promising a sound. The setting decides what to do:

- **Stay quiet** (default): nothing plays.
- **Unmute for it**: the output device's mute is lifted (CoreAudio, `kAudioDevicePropertyMute`
  on the default output), the sound plays, and mute comes back when it ends. The debt is
  written to defaults *before* the mute is touched, so if the Mac sleeps in between it is
  repaid at the next launch or wake, on the same output device only (another device is left
  alone, and the debt forgiven). Outputs with no mute control Shut can reach (some Bluetooth
  and HDMI outputs) cannot be unmuted; the page says so.

The Mac's volume is changed only under "Its own level", and always put back. The sound goes where the Mac's sound goes (AirPods,
a display's speakers); the page names the device. The output device is watched for its mute
and name only while one of Shut's windows is open.

## Files

The starters are listed in `Resources/Sounds/starters.json` beside their files: a name, a
file, and for a part of a file, from and to. Eight ship: five adhkar, each a part of
`Adhkar.mp3` (the author's own recording), and Click, Breath and Hum, generated by
`scripts/make-sounds.swift` (every sample computed, nothing recorded or borrowed, under a
second each). Adding one is a file and a line in the manifest. They are found through
`AppAssets.resourceBundle()`; a missing file is a "Missing" row, never a crash; a missing
manifest falls back to the generated three; `--self-check` confirms every listed file is
in the bundle. The list is seeded from the manifest on first launch, and a release that
brings new starters adds them at the end of an existing list (one the user already cut
themselves, by that name and part, is not doubled). A removed starter, whole or a part, is
hidden, not deleted, so it can be restored.

Own files are validated with `AVAudioFile` (length and sample rate give the duration),
refused over ten minutes, and copied into `~/Library/Application Support/Shut/Sounds/` under
their own name ("Rain.wav", then "Rain 2.wav"); the same bytes added twice (SHA-256) is one
row. The original is never needed again. Removing a row deletes Shut's copy.

**Any sound long enough can be cut.** A row at least a second long has "Cut" (in the
length's slot, with the pointer near): the sound's shape as bars, one per slice of the
file, read once off the main thread and kept only in memory, with the part on a Lime Wash
between two edges. Drag an edge to move it, or the part itself to slide it along; letting
go hears the part; the readout under it says from, to and how long. VoiceOver gets the
part as an adjustable element. Then a name, which starts as "Song · 0:03–0:07" and follows
the edges until the user writes one. "Add as a sound" makes the part a row of its own, right under its source, with
the source's file and no file of its own: cut as many parts from one file as you like, in
any order, and rename them; the file is deleted only when the last row playing it goes.
"Play only this part" makes the row itself play the part; "Whole file" undoes that. A part
is half a second at least, and never outside the file. A part plays from its start and
stops at its end with the landing fade, however the lid is held. Double-click a name to
rename it: Return keeps it, Escape leaves it; two rows never share a name.

**Packs.** Every sound belongs to one pack. Bundled packs come from `starters.json` (the
adhkar, and Starters, the generated Click, Breath and Hum), each with a `credit` line saying where its audio came
from, written beside it (rule 6), and an `onByDefault` flag: a pack is an offer, not a
fixture. Click, Breath and Hum start in the list; the adhkar do not, and wait folded under
the list as "More from Shut", with their credit, for whoever wants them, the way a phone
folds its older ringtones under the ones you chose. Mine leads the list and the bundled packs
follow it. Each pack's heading in the well (under All with more than one pack, or on top
with one pack chosen) carries its count and, with the pointer near, one × that takes the
whole pack out (a bundled one goes back under "More from Shut"; it never leaves the app;
Settings → Packs has the same ×), and
what the user decided about each bundled pack is kept across launches and releases. A pack
whose sounds are already in a list stays in it when the flag arrives. The user's own sounds
live in "Mine", and "New pack…" (under Settings, or from a row's "Move to") makes more. "Plays from", above the list, is
All or one pack: Random and In order work inside what is chosen, and In order keeps its
place per pack. Under All the list shows a small heading per pack; a sound carried across a
heading moves into that pack. A row's "…" menu has Hear, Rename, Cut, Move to, Keep for
later and Remove. A bundled pack can be put away whole (Hide, under Settings) and brought
back; a user pack can be renamed and removed, its sounds going to Mine, never deleted.

**The library.** "Keep for later" takes a sound out of the list and out of every pick,
file, cuts, name and clip all kept, and the folded "Library" row under the list counts it;
opened, each kept sound has Hear, "Use again" (back into its pack, switched on) and Remove.
The library is local to this Mac: no sync, no export.

**What ships, and what cannot.** Only audio that is free to publish can be bundled: the
app is open source under MIT and every file goes to every user. The adhkar are the
author's own recording; Click, Breath and Hum are generated. Clips of actors or famous
people are copyrighted performances (and a recognisable voice carries personality rights),
so they are never bundled; a user is free to add such a clip to their own list, which stays
on their Mac. Every bundled pack is in every download, so the Sounds folder is kept small.

**Find the parts.** In the cut editor, "Find the parts" looks for the silences and marks a
part between each on the shape, numbered, with a list under it: a name to type for each
(Tab moves on), its times, a ▶ to hear it, and a click to put the edges on it. "Add N
sounds" makes every part a row under the source, in order, with the names given (a blank
one gets "Song · 0:03–0:07"); a part under half a second is refused, and said once. The
detection is a pure function of the shape (`LidSoundLibrary.parts`): a slice quieter than
8 % of the loudest is silence, a silence under 0.12 s does not split, a part under 0.25 s
joins its neighbour, each part gets 0.05 s of air either side, and there are twelve at
most, the shortest gaps closed first. A sound with no silence in it is one part, and the
line says so.

**Play to the end.** Under Extras, off by default. On, the lid's sleep is held off while
this close's sound plays, with the same kernel call Stay awake makes
(`kPMSetClamshellSleepState`), and given back the moment the sound ends, so the Mac sleeps
right after and a two-second sound is heard whole however fast the lid comes down. The
landing fade is off then. Stay awake's marker is written for the hold, so a crash
mid-sound is undone at the next launch like any other; a hard stop a second past the
longest sound (31 s) gives the lid back whatever happened; and while Stay awake is holding
the lid itself the sound borrows nothing and gives nothing back, since the bit is its to
give back.

**A long file is clipped, not refused.** Over 30 s, its row grows a "Clip" disclosure: a
"Starts from" dial ("1:12 of 3:20"), and letting go of it plays from there. The lid plays
from that point for 30 s at most, then the landing fade, however the lid is held; the ▶ in
the row hears it from there too. The line under the dial says what the user is really
choosing: how much is heard depends on where the lid starts the sound and how fast it
closes. The note after such an import says so as well.

The list, the way chosen, the volume, the on-open choice and the mute setting are saved
under `lidSound.*` in UserDefaults; the list is one JSON blob so order is kept and a row's
fields travel together.

## Timers, and why

One: a one-shot that ends a fade, because `AVAudioPlayer` has no fade-complete callback. It
exists only while a sound is fading. The output listener is a CoreAudio property listener,
not a timer, and exists only while a window is open.

## What is not covered

Scrubbing the sound with the hinge (varispeed), a sound per style, a sound on sleep or wake
without a lid, syncing sounds between Macs, a fade curve setting. A locate dialog for a
file that went missing (remove it and add it again).
