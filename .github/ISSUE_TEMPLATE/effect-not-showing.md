---
name: Effect didn't play (or played in the wrong place)
about: The lid closed but nothing showed, it showed on the wrong Space or display, or something stayed on screen
title: "Overlay: <what happened>"
labels: overlay
---

### What you were doing

<!-- Desktop, a full-screen app, another Space, Stage Manager, an external display? Which style? -->

### Console lines

Open Console.app, filter on subsystem `app.shut`, close the lid once more, and
paste everything from `snapshot ready` to `teardown:` (the `overlay placement`
line matters most). Logs contain no screen content.

```
paste here
```

### Your Mac

<!-- Model, macOS version, whether the status line says "Following the lid". -->
