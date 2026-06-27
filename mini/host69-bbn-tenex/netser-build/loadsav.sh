#!/usr/bin/env bash
# loadsav.sh NAME DESTDIR : GET DTA1:NAME.SAV then SSAVE 0 777 <DESTDIR>NAME.SAV, confirm [New file]
SCR=/tmp/claude-1000/-home-deltaprism-arpanet/8b7f08a0-a8a0-45c1-9900-263c6de29ffb/scratchpad
H=/home/deltaprism/arpanet/mini/host69-bbn-tenex
NAME="$1"; DEST="${2:-SUBSYS}"
: > "$H/logs/cty.log"
printf 'GET DTA1:%s.SAV\r' "$NAME" > "$SCR/cty.fifo"; sleep 5
printf 'SSAVE 0 777 <%s>%s.SAV\r' "$DEST" "$NAME" > "$SCR/cty.fifo"; sleep 4
printf '\r' > "$SCR/cty.fifo"; sleep 4   # confirm [New file]
tail -20 "$H/logs/cty.log"
pgrep -x pdp10-ki >/dev/null || echo "*** KI HALTED ***"
