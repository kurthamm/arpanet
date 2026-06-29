#!/usr/bin/env bash
# Launch host69 FOREGROUND in a tmux pane for golden-snapshot building.
# stdin stays the pane (so WRU C-\ breaks to sim> for SAVE); stdout -> log.
# Drainers run as background children (survive in tmux).  Run inside h69r:0.
set -u
H=/home/deltaprism/arpanet/mini/host69-bbn-tenex
SCR=/tmp/netlit-deltaprism
rm -f "$SCR/cty.fifo"; mkfifo "$SCR/cty.fifo" 2>/dev/null || true
: > "$H/logs/cty.log"; : > "$SCR/build-snap.log"
python3 "$H/netser-build/scripts/drain.py" 16945 "$H/logs/dc16945.log" >/dev/null 2>&1 &
python3 "$H/netser-build/scripts/drain.py" 16946 "$H/logs/tym16946.log" >/dev/null 2>&1 &
cd "$H/kit-cache/build-tenex/install"
# stdout/stderr go to the PANE (tty) so SIMH stays interactive and the WRU break
# (^E) reaches sim> for SAVE.  Detect progress via tmux capture-pane + cty.log.
exec nice -n 5 "$H/kit-cache/rcornwell-sims/BIN/pdp10-ki" "$SCR/build-snap.do"
