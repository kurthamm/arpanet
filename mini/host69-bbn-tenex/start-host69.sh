#!/usr/bin/env bash
# Start the BBN-TENEX host #69: full unattended install to a live TENEX EXEC.
#
# Runs the emulator with the console on THIS terminal so you can type at the
# system once it comes up. The whole install (disk init -> EXEC -> DLUSER ->
# DUMPER restore of system.tap) is auto-driven by build-tenex-bringup.do and
# takes ~20-30 min on this shared, nice'd box (the disk re-init is the slow part
# -- that's emulated-CPU time, not typing, so it can't be hurried by hand).
#
# When it finishes it sits at the TENEX EXEC "!" prompt (logged in as SYSTEM,
# privileges enabled). From there you can drive a login test by typing:
#
#     DISABLE                      <- drop wheel so passwords are checked
#     CONNECT OPERATOR OPERATOR    <- bare dir name (NO <angle brackets>); must connect
#     DAYTIME                      <- prove a working session
#     CONNECT SYSTEM               <- back to the operator's own directory
#     ENABLE                       <- back to the "!" prompt
#
# Or a full fresh login:
#     LOGOUT                       <- confirm with <return>
#     LOGIN OPERATOR OPERATOR 220100   <- user / password / account
#
# Accounts (mini/host69-bbn-tenex/kit-cache/build-tenex/install/boot/users.txt):
#   OPERATOR / OPERATOR  (full privileges)   PMFDIR0, SUBSYS (blank password)
#
# To detach SIMH and stop: type ^E to reach the "sim>" prompt, then "quit".

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/kit-cache/rcornwell-sims/BIN/pdp10-ki"
DO="$HERE/runtime/build-tenex-bringup.do"
INSTALL="$HERE/kit-cache/build-tenex/install"

[[ -x "$BIN" ]] || { echo "missing emulator: $BIN" >&2; exit 1; }
[[ -f "$DO"  ]] || { echo "missing driver: $DO" >&2; exit 1; }

# Don't fight an already-running sim for the console ports.
if pgrep -x pdp10-ki >/dev/null 2>&1; then
  echo "A pdp10-ki sim is already running (ports 16945/16946 in use)." >&2
  echo "Stop it first:  kill \$(pgrep -x pdp10-ki)" >&2
  exit 1
fi

echo "Starting BBN-TENEX host #69 (console is this terminal)..."
echo "Install runs automatically; expect ~20-30 min to the '!' prompt."
cd "$INSTALL"
exec nice -n 10 "$BIN" "$DO"
