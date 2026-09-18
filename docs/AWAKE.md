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

- **The Awake bar**, under the header of the panel, always says what is keeping
  the Mac awake in one sentence, with the one thing to do about it: "Cursor is
  working · 47 min · Let it sleep". The menu bar mark gains a dot while the lid is
  being held.
- **As the lid comes down**, the closing screen says what will happen: "Staying
  awake · Cursor is working". With nothing to hold for there is no caption and the
  lid sleeps your Mac as it always has.
- **When you come back**, a short receipt: how long it stayed awake and for what,
  when it slept, how much battery went. If a hold was cut short it says why.
- **Hold Option as you close the lid** to do the opposite this once: sleep although
  something is working, or stay awake for an hour although nothing is.

## How "something is working" is known

Shut has no list of agents to keep up to date. Tools that must not be interrupted
already ask macOS not to idle-sleep (it is what `caffeinate` does; Claude Code
does it while it works). Shut reads those requests and walks each one up the
process tree to the app it belongs to, so `caffeinate <- claude <- zsh <- Cursor`
is "Cursor". Apps seen asking appear in **Allowed apps** by themselves; developer
tools and anything run from a terminal are allowed by default, a music player is
not. You decide.

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

The Awake page installs the command as a link in `~/.local/bin`. The wrapped
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

- **Battery floor** (20 %, adjustable 10–50 %): on battery, at the floor the Mac is
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
undo each other. Intel MacBooks are untested.
