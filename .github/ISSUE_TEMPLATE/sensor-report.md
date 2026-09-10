---
name: Lid sensor compatibility report
about: Sinkhole says "Lid sensor not found", or the angle looks wrong
title: "Sensor: <your Mac model>"
labels: sensor
---

Run this in Terminal from a clone of the repo and paste the output below:

```bash
swift run lidangle-cli --report
```

If the sensor is found, also close the lid slowly with the log running and paste
the last few lines, so we can learn your display-off angle:

```bash
swift run lidangle-cli --log angles.csv   # close the lid, reopen, Ctrl-C
tail -5 angles.csv
```

### Report output

<!-- paste here -->

### Anything else

<!-- Did the angle track the lid? Any errors in Console.app under subsystem com.sinkhole.app? -->
