#!/usr/bin/env bash
# Relaunch host69 with the FORCEDOWN-hostready .do. Mirrors run-loginbuild.sh but uses
# forcedown-hostready.do. Does NOT restart imp05 (only starts it if absent).
set -u
H=/home/deltaprism/arpanet/mini/host69-bbn-tenex
M=/home/deltaprism/arpanet/mini
SCR=/tmp/claude-1000/-home-deltaprism-arpanet/8b7f08a0-a8a0-45c1-9900-263c6de29ffb/scratchpad
BIN="$H/kit-cache/rcornwell-sims/BIN/pdp10-ki"
FIFO=$SCR/cty.fifo; CLOG=$H/logs/cty.log
DO="$H/runtime/forcedown-hostready.do"
echo "[L] stop old ki + drainers + console daemon (imp05 left alone)"
pkill -9 -x pdp10-ki 2>/dev/null || true
pkill -9 -f "$SCR/drain.py" 2>/dev/null || true
pkill -9 -f 'console-daemon' 2>/dev/null || true
rm -f "$FIFO"
for i in $(seq 1 100); do ss -tan 2>/dev/null | grep -qE ':(16945|16946|2323)\b' || break; sleep 1; done
echo "[L] ports clear after ${i}s; imp05: $(pgrep -f 'imp05' >/dev/null && echo up || echo DOWN)"
: > "$H/logs/dc16945.log"; : > "$CLOG"; : > "$H/logs/host69-hostready.log"
python3 "$SCR/drain.py" 16945 "$H/logs/dc16945.log" >/dev/null 2>&1 &
python3 "$SCR/drain.py" 16946 "$H/logs/tym16946.log" >/dev/null 2>&1 &
sleep 1
cd "$H/kit-cache/build-tenex/install"
nohup nice -n 5 "$BIN" "$DO" > "$H/logs/host69-hostready.log" 2>&1 </dev/null &
echo "[L] ki pid $!"
for i in $(seq 1 40); do ss -ltn 2>/dev/null | grep -q ':2323' && break; sleep 0.5; done
nohup python3 "$SCR/console-daemon.py" 2323 "$FIFO" "$CLOG" >/dev/null 2>&1 &
echo "[L] console-daemon pid $!"
sleep 3
echo "[L] ki up? $(pgrep -x pdp10-ki >/dev/null && echo YES || echo NO)"
