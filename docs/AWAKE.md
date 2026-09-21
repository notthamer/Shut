# Stay awake

Close the lid and walk away; what was working keeps working, and when it is done
your Mac goes to sleep by itself.

Shut never asks "for how long?". It keeps the Mac awake with the lid shut while a
**reason** is true and lets it sleep when none is:

| Reason | True while |
| --- | --- |
| Something is working | an app you allowed is asking macOS to stay awake: a coding agent in a terminal, a render, an export, a download |
| A display is connected | an external display is plugged in (macOS only allows this on a charger with a keyboard and mouse; Shut lifts both conditions) |
| These apps are open | an app you picked is running |
| I say so | an hour, four hours, or until you stop it |
| A command says so | `shut hold` on the command line |

It is off until you turn it on, and the first time it says what it does on one
screen.

## What you see

- **The eyes.** A pair of cartoon pixel eyes with brows (sixteen by twelve,
  `Resources/eyes.png`, six frames: four gazes, shut, asleep) is the face of the feature: open, the Mac stays awake with the lid shut;
  shut, the lid sleeps it; heavy-lidded while winding down; sound asleep when the
  feature is off. They sit on a small capsule whose colour is the status (Lime,
  Linen, Saffron) in the "Stay awake" tab and, larger, at the top of the Stay awake
  page. While holding they rest on the words beside them, roll once around the other
  corners and blink, on a six-second loop that is a
  pure function of time (`AwakeEyes.frame(_:at:)`); only a face that moves has a
  clock, only while it is on screen, and Reduce Motion stills it. The large sleeping eyes on
  the page breathe out a very soft "z z z", one letter at a time (opacity only).
- **The Awake page answers "when?" without a click.** Under the headline, "Stays
  awake when" lists the four triggers, each with one line about it and its switch:
  an app is busy (apps that ask macOS to stay awake), a display is connected, an app
  is open (apps you pick), you say so: one dial from Off through five minutes to
  twelve hours and on to "until I stop", with the choice said whole under it ("Awake
  until 6:40 PM · 1 h 12 min left"); while it runs the thumb drifts back towards Off. The trigger at work right now says who, in ink
  with a Lime dot ("Claude Code, now"). The lists of apps unfold from their rows;
  only **Settings** stays folded, with a one-line summary. Opened, it is two groups in
  plain words, every row with a line under its name saying what it does: "Protects
  your Mac" (sleep when battery reaches, stay awake on any power or the charger only,
  then sleep after, lock the screen, follow Low Power Mode) and "Extras" (tell me what
  happened, and a line saying what the Option key does; it has no switch, because nobody
  holds Option while closing a lid by accident).
  Who is keeping the Mac awake is said once, in those rows ("Claude Code in Cursor ·
  47 min"); a card appears above them only to warn (battery near the floor).
- **The first switch-on** goes through a Void Black sheet with the eyes asleep at the
  top; "Turn on" opens them, and the sheet leaves a moment later.
- **Two sections, as two tabs in the header that each carry their own state.** "Lid
  effects" with a lid icon and, under it, the style and whether it is running ("Fold ·
  On", "Fold · Paused", "Fold · plain fade for now"); "Stay awake" with the eyes and, under
  it, what it is doing ("Claude Code · 47 min", "Sleeping in 4 min", "Battery 24 % ·
  sleeps at 20 %", "Zoom is asking", "Lid will sleep your Mac", "Off"). The chosen tab has
  a Linen ground and the 2-pt spectrum line beneath it. A name alone had read as a
  subtitle of "Shut.", not as somewhere to go; and because each tab says what it is
  doing, the state of Stay awake shows from the Lid effects side with no status row. To
  act on it (Let it sleep, Allow) is one click away, on its tab, and in the menu. The
  header has one switch, in one place; it belongs to the section on show and says On or
  Off.
- **The page is a grid, with the same vertical rule as the Lid effects page.** Top left,
  where the eye lands: the eyes and, under them, the answer to the one question anyone
  has, always in the same words ("Closing the lid will sleep your Mac." / "Closing the
  lid keeps your Mac awake."), then when that ends (who is working is said once, in the box on the right; every fact
  is on the page once: a sentence that repeats its label, its headline or its neighbour
  is cut), and the
  one action (Let it sleep, Allow). Top right: "Keep it awake" with the two ways side by side,
  "Automatically" (the rules below decide; one sentence says which are on, and while they are
  keeping the Mac awake a box under the choice, "Keeping it awake now", lists who with
  icon and time, three at most and "and N more") and "For a set
  time" (one click starts the time last used, a dial under it changes it from 5 min to
  12 h or until stopped; when it runs out the page is automatic again), so going from one
  to the other is one click either way, and, only while
  closing will keep the Mac awake, a small preview of the close with its caption. Under
  a hairline, the rules in two numbered sections like the Lid effects page: "01 Keep it
  awake while" (the three reasons) on the left and "02 Settings" (folded, with its
  summary) on the right, each scrolling by itself. At the foot, "03 Last time", one quiet
  strip in small type, with an × that removes the note until the next one. On battery at or under the chosen level the page says so with both
  numbers, wherever it speaks: the tab ("Battery 18 % · too low"), the answer, a Saffron
  card with a bar filled to now and a tick at the level ("now 18 %", "needs more than
  20 %") and, while Settings is folded, a "Change the level" button that opens it, the line under the battery slider, and the set-time dial ("Not right now: the
  battery is too low."). If "An app is busy" is off the answer says that agents and builds
  will not keep the Mac awake.
- **One panel size.** Both sections have the same height, whatever their state. (For a
  day the panel followed the Stay awake page's content; a window that changes size when
  the tab changes felt wrong, and a test now holds it to one size.)
- **A button shows where it leads.** Actions that keep the Mac awake ("Keep it awake",
  "Allow") are Lime with the open eyes; actions that let it sleep ("Let it sleep", "Not
  this app") are an outline with the shut eyes, because a working Mac going to sleep is
  the user's call and never the thing Shut pushes. Under the button one line says what
  pressing it will do ("Just this once: closing the lid will sleep your Mac, even though
  Claude Code is working."). They used to be one dark button with four meanings, one of
  them labelled "Undo".
- **Said once.** The eyes are small in the tab and large over the answer on the page, bare
  both times: no capsule, no border, no ground. A control that has its
  explanation written under it has no tooltip repeating it. The header switch says "On"
  or "Off": the section's name is already beside it, selected.
- **Readable.** Text that carries meaning is Carbon (5.4:1 on the paper); Slate, which
  was 3.2:1 as #888888, is #767676 now and is kept for eyebrows and scales. A whole
  reason row opens its list, not only the word at its end.
- **The menu bar mark** carries a badge that says what the lid will do, in the one
  place that is always on screen: a dot while holding, a ring while winding down
  after the work ended, Saffron when a limit is near or has stopped the hold. Its
  tooltip is the headline ("Claude Code is working in Cursor.").
- **As the lid comes down**, the closing screen says what will happen: "Staying
  awake · Cursor is working". With nothing to hold for there is no caption and the
  lid sleeps your Mac as it always has. The caption brings its own dark gradient
  (measured against a plain white desktop), and a limit that lets the Mac sleep
  ("Sleeping · battery is at 18 %") is set in Saffron.
- **When you come back**, the receipt is handed over: a slip of paper under the menu
  bar icon, once the lid is open and the screen unlocked. The time comes first: how
  long as the headline ("Awake for 1 h 34 min"), the clock times on their own line
  ("9:25 PM → 10:59 PM, then it slept"), then for what and how much battery went. If a hold was cut short
  it says why, on Saffron. It never takes focus, fades after seven seconds (hovering
  keeps it), and a click opens the Awake page, which keeps it under "Last time".
  "Receipt when I come back" in Options switches it off; with Shut's panel already
  open the bar says it instead.
- **Hold Option as the lid comes down**, at the start or at any point on the way, to
  do the opposite this once: sleep although something is working, or stay awake for
  an hour although nothing is. A second press takes it back, and the caption
  crossfades to say which way it went. Option is read on the frames a close already
  draws: no timer, no event tap, no permission. The first five captioned closes
  carry a one-line hint, "Hold ⌥ to let it sleep instead"; using Option once ends
  the lesson early.

## How "something is working" is known

Shut has no list of agents to keep up to date. Tools that must not be interrupted
already ask macOS not to idle-sleep (it is what `caffeinate` does; Claude Code
does it while it works). Shut reads those requests and walks each one up the
process tree to the app it belongs to, so `caffeinate <- claude <- zsh <- Cursor`
is "Cursor", and the tool is named too: the first process on the way up that is not
plumbing. A short list gives the common ones their proper names (Claude Code, Codex,
Gemini CLI, Aider, OpenCode, Cursor Agent, Goose, Amp, Copilot CLI, Qwen Code), also
when the binary is named after its platform (`codex-aarch64-apple-darwin`) or is a
script run by node or python (the script's name, or its package's, is read from the
process arguments). The list is cosmetic: a tool that is not on it is recognised just
the same and shows under its own name. No logos are bundled. A tool borrows its maker's
app icon when that app is installed (Claude Code: Claude; Codex: the Codex or ChatGPT
app; Cursor Agent: Cursor) and otherwise shows the app it runs in. Apps seen asking
appear in **Allowed apps** by themselves; developer
tools and anything run from a terminal are allowed by default, a music player is
not. The list never outgrows the page: it shows six and a half rows and scrolls inside
itself beyond that, grows a filter past eight apps, puts the apps keeping the Mac awake
right now first (then the ones asking that may not, then the ones switched on), and
forgets an app that was never switched on, never decided about and not seen for two
months. You decide, and you are asked where you are already looking: while nothing is
holding the lid, an app that is asking and has never been decided about turns the
bar and the Awake page into one question, "Zoom is asking to stay awake", with
**Allow** and **Not this app**. Either answer is remembered and the question is
never asked about that app again.

macOS sends no event when one app's request ends, so the list is read when it
matters: as the lid starts to close, while Shut's window is open, and once every
30 s while the feature is on. One IOKit call each time. With the feature off
nothing is read, apart from one look as the lid closes (that is how Shut can say,
once, "Cursor was working when you shut the lid, and your Mac slept").

For anything that does not ask macOS to stay awake:

```bash
shut hold -- npm run build          # hold while this command runs
shut hold --pid 4242                # hold while that process lives
shut hold start --id render --ttl 2h
shut hold stop --id render
shut hold status
```

Most people never need it: `caffeinate -i <command>`, which ships with macOS, is seen
by Shut like any other request to stay awake. `shut hold` adds the command's name in
the caption and works with "An app is busy" switched off. There is no installer in
the interface; link it yourself once:
`ln -s /Applications/Shut.app/Contents/MacOS/Shut ~/.local/bin/shut`. The wrapped
command always runs, with or without Shut, so an alias never breaks a workflow.
Any tool with hooks can call it; for Claude Code, in `~/.claude/settings.json`:

```json
{ "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "shut hold start --id claude --ttl 2h" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "shut hold stop --id claude" }] }] } }
```

(Claude Code needs none of this; it is already seen. The recipe is the shape for
tools that are not.)

## How the lid is held

Power assertions stop idle sleep only. The lid is a separate path inside
`IOPMrootDomain`, and its user client has one call that turns lid-close sleep
off: `kPMSetClamshellSleepState` (selector 12, in the public SDK's
`IOPMLibDefs.h`). The kernel applies no privilege or entitlement check to it, so
Shut needs **no root, no helper and no password**. Measured on a MacBook Pro
(Mac14,9, macOS 26.5): lid shut on battery with no display attached, and on a
charger, awake throughout.

Three properties of that call shape the rest:

1. The kernel keeps one bit for every app that uses it, and `powerd` rewrites it
   when the power source changes. Shut puts it back on those events, and every
   10 s while it is holding with the lid shut. If the Mac sleeps anyway, the
   receipt says so rather than pretending.
2. Clearing the bit with the lid shut makes the Mac sleep at once. "The work
   finished" and "now go to sleep" are the same call.
3. The bit outlives the process, though never a reboot (it is not written to
   disk). Shut writes a marker file while it holds; a launch that finds the marker
   restores the lid first. Quit, an update relaunch and a newer copy taking over
   all restore it. Shut only ever undoes what it did, because the bit is shared
   with other keep-awake apps.

Apple menu → Sleep still sleeps the Mac.

## Limits, which always win

- **Battery floor** (20 % until the Stay awake page is first opened, when it starts once from the step just under the charge, 65 % → 60 %, so nobody has to work out a number; adjustable 5–100 %; the line under the slider says the charge right now, with a link, "Use 60 %, just under it", whenever the level is not that one; every change is saved): on battery, at the floor the Mac is
  allowed to sleep whatever is working.
- **Heat**: at thermal state *serious* with the lid shut, *critical* always.
- **8 hours on battery.** On a charger a desk setup can run all day.
- **Low Power Mode** pauses holding. **Charger only** is a switch.
- **Lock when shut** (on): a Mac that never slept is unlocked for whoever opens it
  next. macOS has no public "lock now"; Shut looks up `SACLockScreenImmediate` at
  run time, checks that the session really locked, retries, and logs a failure.
- After work stops Shut waits five minutes (1–30) before letting go: an agent
  between two steps looks finished for a moment.
- Another user taking over the screen ends the hold.

**Do not put a working Mac in a bag.** A shut lid is a worse radiator and nobody is
watching the screen. The limits are there for the day someone does it anyway.

## What is not covered

Agents in Docker or a dev container, and agents that run in the cloud (there is
nothing local to keep awake). Two keep-awake apps share the one kernel bit and can
undo each other. Intel MacBooks are untested. Macs without a lid (mini, iMac, Studio)
do not get the feature at all.

## When the charger goes in or comes out with the lid shut

The kernel keeps one lid bit for every userspace caller, and powerd is one of them. When
the power source changes it recomputes that bit and writes its answer over ours; if its
answer is "sleep" and ours is not back in time, the Mac goes into Clamshell Sleep with the
work still running. (Seen for real: on battery, lid shut, charger plugged in, asleep
fifteen seconds later.) Two things stand against that, neither needing root:

- While holding, Shut also takes a `PreventSystemSleep` assertion, the one `caffeinate -s`
  takes. powerd honours it on the charger only, and there it keeps lid sleep off by
  itself, so after the charger goes in its answer is the same as ours.
- For half a minute after any power change, while holding with the lid shut, Shut puts
  the bit back twice a second (it used to put it back once, then every ten seconds).

Pulling the charger out with the lid shut is the harder direction: on battery powerd does
not honour that assertion, so only the second defence applies. It needs testing on a real
lid before it is promised.

## If Shut dies while holding

The kernel's lid bit outlives the process that set it, so every way Shut can end has
to put it back. Quitting, an update and a handover to another copy restore it on the
way out. A crash leaves a marker file, and the next launch restores it before doing
anything else. That left one case: Shut force-killed while holding and never opened
again, which used to mean a Mac that did not sleep when shut until its next reboot.

While a hold is armed Shut therefore keeps a **guard**: a second copy of its own
executable (`Shut --lid-guard <pid>`) that sleeps in the kernel on a process event
until Shut exits, then restores lid sleep, removes the marker and exits. No root, no
helper to install, no CPU while it waits, and it exists only while a hold does. When
a hold ends the ordinary way Shut restores the lid itself and dismisses the guard.
As the lid starts to close, Shut also sets the bit again whatever happened to it
since (powerd rewrites it, another keep-awake app can clear it).

## First run and the update tour

- **First run** (`WelcomeWindow.swift`): a walk on the canvas (Bone, the app's own ground; it
  was a dark stage). Hello; pick a style and watch it (the real gallery and preview); turn Stay
  awake on or leave it (turning it on here is the consent, same words and bag warning; the eyes
  wake); then how Stay awake works, in the update tour's own three playable slides (a new user
  never gets the what's-new card, so its lessons are here: one set of stages and words); a last
  step that says the choices back. No lid: hello, style, done. Back, dots, Continue.
- **Update tour** (`WhatsNewTour` in `WhatsNew.swift`): a release with something to see gets
  slides in the what's-new card instead of the changelog's words: a small stage with the real
  views drawn live (never a picture that can go out of date), a headline, one sentence. Two
  stages can be played with; their state is the slide's own and touches no setting. One height
  for every slide, Later on every slide, "Show me" on the last. A release without a tour falls
  back to the text card.
