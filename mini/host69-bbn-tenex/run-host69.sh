#!/bin/sh
# Run BBN-TENEX host #69 in THIS terminal (the terminal is the TENEX console).
# The do-file auto-drives the finicky install (SYSLOD, disk init, EXEC, DLUSER,
# DUMPER restore) and then stops at the EXEC "!" prompt, where YOU type by hand.
#
# Disk date is set to 1972 (in TENEX's valid range -> avoids the date-convert trap).
# The other 5 ARPANET host sims are frozen (paused) so this runs at full speed;
# run ./resume-arpanet.sh when you are done to bring them back.
#
# To stop the simulator: press Ctrl-E to get the "sim>" prompt, then type:  quit

cd /home/deltaprism/arpanet/mini/host69-bbn-tenex/kit-cache/build-tenex/install || exit 1
BIN=/home/deltaprism/arpanet/mini/host69-bbn-tenex/kit-cache/rcornwell-sims/BIN/pdp10-ki
DO=/home/deltaprism/arpanet/mini/host69-bbn-tenex/runtime/build-tenex-bringup-1972.do

# Refuse to fight an existing sim for the console ports.
if pgrep -x pdp10-ki >/dev/null 2>&1; then
  echo "A pdp10-ki sim is already running. Stop it first:  kill \$(pgrep -x pdp10-ki)" >&2
  exit 1
fi

exec "$BIN" "$DO"
