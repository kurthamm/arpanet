#!/usr/bin/env bash
# build-1c.sh [SRC.fai] -- assemble a NETLIT source on-box (FAIL) and rebuild the
# login.dta run tape.  FULLY REPO-LOCAL / self-contained: no Claude scratchpad,
# generates its own build .do, uses the repo's console-daemon.py/drain.py.
# Override the scratch dir with NETLIT_SCRATCH=/path (default /tmp/netlit-$USER).
# Default source: netser-build/netser-lite-1c.fai
set -u
H="$(cd "$(dirname "$0")/.." && pwd)"            # .../mini/host69-bbn-tenex
SRC="${1:-$H/netser-build/netser-lite-1c.fai}"
SCR="${NETLIT_SCRATCH:-/tmp/netlit-$USER}"; mkdir -p "$SCR"
HELP="$H/netser-build/scripts"                   # repo-local console-daemon.py/drain.py
FIFO="$SCR/cty.fifo"; CLOG="$H/logs/cty.log"
LB="$H/runtime/login-build"
INST="$H/kit-cache/build-tenex/install"
TENDMP="$INST/tools/tendmp"; DTBOOT="$INST/boot/dtboot.bin"
BIN="$H/kit-cache/rcornwell-sims/BIN/pdp10-ki"
SNAP="$H/snap/host69-live.state"
DO="$SCR/build-1c.do"

echo "[B] H=$H"
echo "[B] SRC=$SRC"
echo "[B] SCRATCH=$SCR  (override with NETLIT_SCRATCH=...)"
for f in "$SRC" "$HELP/console-daemon.py" "$HELP/drain.py" "$TENDMP" "$DTBOOT" "$BIN" "$SNAP" \
         "$LB/subsys/fail.sav" "$LB/subsys/pa1050.sav" "$LB/subsys/loader.sav" "$LB/dta/dummy.txt"; do
  [ -e "$f" ] || { echo "[B] MISSING: $f"; exit 1; }
done

# --- generate the build .do (no imp needed for assembly) ---
cat > "$DO" <<EOF
restore -F $SNAP
detach dc
detach tym
detach imp
detach mta0
detach dt0
detach dt1
attach -u dc 16945 speed=2400
attach -u tym 16946
attach dt0  $LB/scratch.dta
attach -r dt1  $LB/buildtape.dta
set imp nodebug
set console telnet=2323,nomessage
deposit 57174 777777777777
echo === BUILD EXEC READY ===
go
EOF

# --- prep tapes (CRLF source; build tape; fresh writable scratch) ---
echo "[B] prep tapes"
sed 's/$/\r/' "$SRC" > "$LB/dta/xcr.fai"
chmod u+w "$LB/scratch.dta" "$LB/buildtape.dta" 2>/dev/null
"$TENDMP" -T -L TENEX -b "$DTBOOT" -c "$LB/scratch.dta"   "$LB/dta/dummy.txt" >/dev/null 2>&1
"$TENDMP" -T -L TENEX -b "$DTBOOT" -c "$LB/buildtape.dta" "$LB/dta/xcr.fai" "$LB/subsys/fail.sav" "$LB/subsys/pa1050.sav" >/dev/null 2>&1
echo "[B] build tape: $("$TENDMP" -t "$LB/buildtape.dta" 2>&1 | grep -E 'XCR|FAIL|PA1050' | tr '\n' ' ')"

# --- launch the emulator + console ---
echo "[B] launch host69 (build instance)"
pkill -9 -x pdp10-ki 2>/dev/null; pkill -9 -f console-daemon 2>/dev/null; pkill -9 -f "$HELP/drain.py" 2>/dev/null; rm -f "$FIFO"
for i in $(seq 1 60); do ss -tan 2>/dev/null | grep -qE ':(16945|16946|2323)\b' || break; sleep 1; done
: > "$CLOG"; : > "$H/logs/build.log"
python3 "$HELP/drain.py" 16945 "$H/logs/dc16945.log" >/dev/null 2>&1 &
python3 "$HELP/drain.py" 16946 "$H/logs/tym16946.log" >/dev/null 2>&1 &
sleep 1
( cd "$INST" && nice -n 5 "$BIN" "$DO" > "$H/logs/build.log" 2>&1 < /dev/null ) &
KIPID=$!
echo "[B] KIPID=$KIPID"
for i in $(seq 1 60); do ss -ltn 2>/dev/null | grep -q ':2323' && break; sleep 0.5; done
python3 "$HELP/console-daemon.py" 2323 "$FIFO" "$CLOG" >/dev/null 2>&1 &

# --- wait for the EXEC prompt (verify the console actually reaches TENEX) ---
EXECOK=0
for i in $(seq 1 25); do
  : > "$CLOG"; printf '\r' > "$FIFO"; sleep 1
  grep -q '!' "$CLOG" && { EXECOK=1; echo "[B] EXEC responds after ${i}s"; break; }
  pgrep -x pdp10-ki >/dev/null || { echo "[B] KI DIED during boot at ${i}s (see logs/build.log)"; exit 2; }
done
[ "$EXECOK" = 1 ] || { echo "[B] CONSOLE NEVER REACHED EXEC -- aborting (ki left running for inspection)"; exit 3; }

# --- drive the FAIL assembly ---
W(){ printf '%s\r' "$1" > "$FIFO"; sleep "${2:-3}"; }
echo "[B] stage FAIL + PA1050, assemble"
W "MOUNT DTA0:" 3; W "MOUNT DTA1:" 3
W "COPY DTA1:FAIL.SAV <SUBSYS>FAIL.SAV" 5; W "" 3
W "COPY DTA1:PA1050.SAV <SUBSYS>PA1050.SAV" 5; W "" 3
pgrep -x pdp10-ki >/dev/null || { echo "[B] KI DIED during COPY"; exit 2; }
: > "$CLOG"
W "FAIL" 5
W "DTA0:XCR_DTA1:XCR.FAI" 18
echo "[B] FAIL output:"; tail -6 "$CLOG"

if grep -q "PROGRAM BREAK" "$CLOG"; then
  echo "[B] *** ASSEMBLED OK -- flushing + extracting ***"
  kill -TERM "$KIPID" 2>/dev/null; sleep 3
  pkill -9 -f console-daemon 2>/dev/null; pkill -9 -f "$HELP/drain.py" 2>/dev/null
  ( cd "$LB" && "$TENDMP" -x scratch.dta >/dev/null 2>&1
    cp -f xcr.rel netlit.rel; cp -f netlit.rel dta/netlit.rel
    "$TENDMP" -T -L TENEX -b "$DTBOOT" -c login.dta netlit.rel subsys/loader.sav subsys/pa1050.sav >/dev/null 2>&1 )
  echo "[B] RUN TAPE login.dta:"; "$TENDMP" -t "$LB/login.dta" 2>&1 | head -5
  echo "[B] DONE.  Now run the test:  bash $H/netser-build/launch-1c-test.sh"
else
  echo "[B] *** NO PROGRAM BREAK -- assembly failed.  NOT killing the ki (inspect logs/cty.log). ***"
  exit 4
fi
