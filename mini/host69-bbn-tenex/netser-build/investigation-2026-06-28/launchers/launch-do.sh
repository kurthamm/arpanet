#!/usr/bin/env bash
# Generic throwaway launcher: $1 = do-file. Stops prior throwaway, starts drainers +
# console-daemon, runs ki on the given do-file (cwd=copy dir so media/=copies).
set -u
DO="$1"
RT=/tmp/claude-1000/-home-deltaprism-arpanet/ef23d23f-4517-4df6-a113-1c4da8dc08db/scratchpad/reset-test
SCRIPTS=/home/deltaprism/arpanet/mini/host69-bbn-tenex/netser-build/scripts
BIN=/home/deltaprism/arpanet/mini/host69-bbn-tenex/kit-cache/rcornwell-sims/BIN/pdp10-ki
FIFO=$RT/cty.fifo
pkill -9 -x pdp10-ki 2>/dev/null || true
pkill -9 -f 'console-daemon.py' 2>/dev/null || true
pkill -9 -f 'netser-build/scripts/drain.py' 2>/dev/null || true
rm -f "$FIFO"
for i in $(seq 1 60); do ss -tan 2>/dev/null | grep -qE ':(16945|16946|2323)\b' || break; sleep 1; done
: > "$RT/dc16945.log"; : > "$RT/tym16946.log"; : > "$RT/cty.log"; : > "$RT/ki.log"
nohup python3 "$SCRIPTS/drain.py" 16945 "$RT/dc16945.log" >/dev/null 2>&1 &
nohup python3 "$SCRIPTS/drain.py" 16946 "$RT/tym16946.log" >/dev/null 2>&1 &
sleep 1
cd "$RT"
nohup "$BIN" "$DO" > "$RT/ki.log" 2>&1 </dev/null &
echo "[L] ki pid $!"
for i in $(seq 1 40); do ss -ltn 2>/dev/null | grep -q ':2323' && break; sleep 0.5; done
nohup python3 "$SCRIPTS/console-daemon.py" 2323 "$FIFO" "$RT/cty.log" >/dev/null 2>&1 &
echo "[L] console-daemon pid $!"
