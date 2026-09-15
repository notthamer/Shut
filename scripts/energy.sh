#!/bin/bash
# Measures what Shut costs while it runs: CPU, memory, idle wakeups and context
# switches per second from `top`, plus (with sudo) CPU and GPU power from
# powermetrics. Run it with the lid open and nothing happening for the "at rest"
# number, then again with the panel open, then once more while you close and
# reopen the lid.
#
#   scripts/energy.sh              # 30 s of top, no sudo needed
#   scripts/energy.sh 60           # 60 s
#   sudo scripts/energy.sh 30      # also CPU / GPU power for the whole machine
#
# Measure the release build (scripts/build.sh, then open build/Shut.app). A
# build run from Xcode carries the debugger and its instrumentation and reads
# several times higher.
set -euo pipefail
SECS="${1:-30}"

PID=$(pgrep -f "Shut.app/Contents/MacOS/Shut" | head -1 || true)
if [ -z "$PID" ]; then echo "Shut is not running. open build/Shut.app first."; exit 1; fi
EXE=$(ps -o command= -p "$PID" | cut -d' ' -f1)
echo "Shut pid $PID"
echo "  $EXE"
case "$EXE" in *DerivedData*) echo "  (Xcode debug build: numbers will read high)";; esac
echo "  $(sysctl -n hw.model), macOS $(sw_vers -productVersion), $(pmset -g batt | sed -n 2p | awk -F'\t' '{print $2}')"
echo

echo "Sampling $SECS s…"
top -l $((SECS + 1)) -s 1 -pid "$PID" -stats pid,cpu,mem,power,idlew,csw 2>/dev/null \
  | grep -E "^$PID " | tail -n "$SECS" \
  | awk -v secs="$SECS" '
      NR==1 { w0=$5; c0=$6 }
      { cpu+=$2; pw+=$4; mem=$3; w1=$5; c1=$6; n++ }
      END {
        gsub(/\+/,"",w0); gsub(/\+/,"",w1); gsub(/\+/,"",c0); gsub(/\+/,"",c1);
        printf "  CPU            %.2f %% (mean of %d samples)\n", cpu/n, n;
        printf "  Memory         %s\n", mem;
        printf "  Idle wakeups   %.1f /s\n", (w1-w0)/(n-1);
        printf "  Ctx switches   %.0f /s\n", (c1-c0)/(n-1);
      }'

if [ "$(id -u)" -eq 0 ]; then
  echo
  echo "powermetrics ($SECS s, whole machine)…"
  powermetrics --samplers cpu_power,gpu_power -i $((SECS * 1000)) -n 1 2>/dev/null \
    | grep -E "CPU Power|GPU Power|Combined Power|GPU HW active residency" | sed 's/^/  /'
else
  echo
  echo "Run with sudo to add CPU and GPU power from powermetrics."
fi
