#!/usr/bin/env bash
# Bring up BBN-TENEX host #69 with the AUTHENTIC ncp IMP attached to imp05 hi2.
# Full unattended install to a live ! EXEC, console parked on telnet 2323.
# The IMP (set imp ncp; attach -u imp 21052:127.0.0.1:21051) is present from boot
# so TENEX inits its 1822 host interface against a live imp05 hi2 (21051) peer.
#
# Console-line drainers (DC 16945 / TYM 16946) keep TENEX's TTY output flowing so
# the boot doesn't hang at "TENEX RESTARTING" (the tyhngu wedge fix).
#
# Runs in the background; tail the log to watch the ~20-40 min install.
set -u
H=/home/deltaprism/arpanet/mini/host69-bbn-tenex
BIN="$H/kit-cache/rcornwell-sims/BIN/pdp10-ki"
DO="$H/runtime/build-tenex-bootinstalled-ncp.do"
INSTALL="$H/kit-cache/build-tenex/install"
LOG="$H/logs/host69-installed.log"

if pgrep -x pdp10-ki >/dev/null 2>&1; then
  echo "A pdp10-ki sim is already running; stop it first: kill \$(pgrep -x pdp10-ki)" >&2
  exit 1
fi


# Persistent reconnecting drainers on both console lines (boot-wedge fix).
(
  for i in $(seq 1 120); do ss -ltn 2>/dev/null | grep -q ':16946' && break; sleep 1; done
  while pgrep -x pdp10-ki >/dev/null 2>&1; do timeout 1800 nc 127.0.0.1 16945 </dev/null >/dev/null 2>&1; sleep 0.2; done &
  while pgrep -x pdp10-ki >/dev/null 2>&1; do timeout 1800 nc 127.0.0.1 16946 </dev/null >/dev/null 2>&1; sleep 0.2; done &
) &

echo "[starting TENEX host69 ncp install -> live ! ; log: $LOG]"
cd "$INSTALL" || exit 1
nohup nice -n 10 "$BIN" "$DO" > "$LOG" 2>&1 < /dev/null &
echo "[pdp10-ki pid $!]"
