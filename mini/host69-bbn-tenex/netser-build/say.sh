#!/usr/bin/env bash
# say.sh "COMMAND" [wait_secs] : send one line to the TENEX console FIFO, wait, show new output.
SCR=/tmp/claude-1000/-home-deltaprism-arpanet/8b7f08a0-a8a0-45c1-9900-263c6de29ffb/scratchpad
H=/home/deltaprism/arpanet/mini/host69-bbn-tenex
CMD="$1"; W="${2:-4}"
: > "$H/logs/cty.log"
printf '%s\r' "$CMD" > "$SCR/cty.fifo"
sleep "$W"
tail -40 "$H/logs/cty.log"
pgrep -x pdp10-ki >/dev/null || echo "*** KI HALTED ***"
