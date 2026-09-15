# How the hinge is read

The lid angle sensor reports whole degrees and only changes about ten times a
second, so reading it directly makes any effect pulse. Shut fits a line through
recent readings (position and rate, no lag), passes the result through a 1€ filter
whose cutoff follows the measured rate, and learns your hinge: the closed angle is
the lowest reading ever seen, the open angle follows wherever the lid rests. The
effect then runs in a band above shut, with a small share tracking the whole travel
so something always answers. Nobody types angles.

## What it costs to leave running

Shut is meant to be forgotten about. At rest the sensor is read once a second,
ten times a second for a little while after the lid last moved, and 120 times a
second only while it is moving. The sensor's own input reports act as a doorbell
that wakes the poller when the hinge is touched. No frame is drawn unless the
overlay is on screen and progress changed; the display link pauses after half a
second of stillness. The GPU is never waited on from the main thread. App Nap is
declined so a close is never missed while you are in another app.

## Safety

The overlay is click-through, sits above everything, joins every Space and
full-screen app, and is torn down when the lid reopens, when the sensor goes quiet
for half a second, when the built-in display disappears, on sleep, and on quit.
After unlock the fresh snapshot springs back out; if a black overlay is ever on
screen for more than 1.5 s while the Mac is awake and unlocked, it is force-hidden
and the event is logged.
