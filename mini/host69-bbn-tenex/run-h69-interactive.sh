#!/bin/bash
# Run BBN-TENEX host #69 with the console IN THIS TERMINAL (your SSH session).
# The install auto-runs (~3 min); DON'T type until you see the "!" prompt.
# Wedge fix: background drainers keep the DC/TYM console lines flowing so the
# boot doesn't hang at "TENEX RESTARTING".
#
# When it reaches "!", you are SYSTEM (privileged). Try:
#   DAYTIME            (date/time)
#   DIRECTORY          (lists SYSTEM, OPERATOR, PMFDIR0, SUBSYS)
#   DISABLE            then  CONNECT OPERATOR OPERATOR   (password test) then ENABLE
# To stop: Ctrl-E for the sim> prompt, then  quit
set -u
H=/home/deltaprism/arpanet/mini/host69-bbn-tenex
BIN="$H/kit-cache/rcornwell-sims/BIN/pdp10-ki"
DO="$H/runtime/build-tenex-interactive.do"
INSTALL="$H/kit-cache/build-tenex/install"

if pgrep -x pdp10-ki >/dev/null 2>&1; then
  echo "A pdp10-ki sim is already running; stop it first: kill \$(pgrep -x pdp10-ki)" >&2
  exit 1
fi

# fresh disk
"$H/reset-disk.sh" >/dev/null 2>&1 && echo "[disk reset]"

# background console-line drainers (the boot-wedge fix); auto-exit when sim ends
(
  for i in $(seq 1 90); do ss -ltn 2>/dev/null | grep -q ':16946' && break; sleep 1; done
  while pgrep -x pdp10-ki >/dev/null 2>&1; do timeout 1800 nc 127.0.0.1 16945 </dev/null >/dev/null 2>&1; sleep 0.2; done &
  while pgrep -x pdp10-ki >/dev/null 2>&1; do timeout 1800 nc 127.0.0.1 16946 </dev/null >/dev/null 2>&1; sleep 0.2; done &
) &

echo "[starting TENEX — install auto-runs ~3 min; do NOT type until you see '!']"
cd "$INSTALL" || exit 1
exec nice -n 10 "$BIN" "$DO"
