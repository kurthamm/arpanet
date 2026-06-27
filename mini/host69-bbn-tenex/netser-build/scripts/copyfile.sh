#!/usr/bin/env bash
# copyfile.sh SRCNAME DESTPATH : COPY DTA1:SRCNAME <DESTPATH>, confirm [New file]
SCR=/tmp/claude-1000/-home-deltaprism-arpanet/8b7f08a0-a8a0-45c1-9900-263c6de29ffb/scratchpad
H=/home/deltaprism/arpanet/mini/host69-bbn-tenex
SRC="$1"; DEST="$2"
: > "$H/logs/cty.log"
printf 'COPY DTA1:%s %s\r' "$SRC" "$DEST" > "$SCR/cty.fifo"; sleep 4
printf '\r' > "$SCR/cty.fifo"; sleep 5   # confirm [New file] if prompted
tail -12 "$H/logs/cty.log"
pgrep -x pdp10-ki >/dev/null || echo "*** KI HALTED ***"
