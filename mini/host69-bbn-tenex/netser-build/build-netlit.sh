#!/usr/bin/env bash
# build-netlit.sh SRC.fai : assemble SRC on-box (FAIL) -> login-build/netlit.rel + rebuild login.dta run tape.
set -u
H=/home/deltaprism/arpanet/mini/host69-bbn-tenex
LB="$H/runtime/login-build"
INST="$H/kit-cache/build-tenex/install"
TENDMP="$INST/tools/tendmp"; DTBOOT="$INST/boot/dtboot.bin"
SCR=/tmp/claude-1000/-home-deltaprism-arpanet/8b7f08a0-a8a0-45c1-9900-263c6de29ffb/scratchpad
FIFO="$SCR/cty.fifo"; CLOG="$H/logs/cty.log"
SRC="$1"
echo "[B] CRLF source + tapes"
sed 's/$/\r/' "$SRC" > "$LB/dta/xcr.fai"
"$TENDMP" -T -L TENEX -b "$DTBOOT" -c "$LB/scratch.dta" "$LB/dta/dummy.txt" >/dev/null 2>&1
"$TENDMP" -T -L TENEX -b "$DTBOOT" -c "$LB/buildtape.dta" "$LB/dta/xcr.fai" "$LB/subsys/fail.sav" "$LB/subsys/pa1050.sav" >/dev/null 2>&1
echo "[B] boot host69 with build-1b.do"
pkill -9 -x pdp10-ki 2>/dev/null; pkill -9 -f console-daemon 2>/dev/null; pkill -9 -f drain.py 2>/dev/null; rm -f "$FIFO"
for i in $(seq 1 120); do ss -tan 2>/dev/null | grep -qE ':(16945|16946|2323)\b' || break; sleep 1; done
: > "$CLOG"
python3 "$SCR/drain.py" 16945 "$H/logs/dc16945.log" >/dev/null 2>&1 &
python3 "$SCR/drain.py" 16946 "$H/logs/tym16946.log" >/dev/null 2>&1 &
sleep 1
cd "$INST"
nohup nice -n 5 "$H/kit-cache/rcornwell-sims/BIN/pdp10-ki" "$H/runtime/build-1b.do" > "$H/logs/build1b.log" 2>&1 </dev/null &
KIPID=$!
for i in $(seq 1 40); do ss -ltn 2>/dev/null | grep -q ':2323' && break; sleep 0.5; done
nohup python3 "$SCR/console-daemon.py" 2323 "$FIFO" "$CLOG" >/dev/null 2>&1 &
sleep 4
echo "[B] drive FAIL assembly"
printf 'MOUNT DTA0:\r' > "$FIFO"; sleep 3
printf 'MOUNT DTA1:\r' > "$FIFO"; sleep 3
printf 'COPY DTA1:FAIL.SAV <SUBSYS>FAIL.SAV\r' > "$FIFO"; sleep 4; printf '\r' > "$FIFO"; sleep 3
printf 'COPY DTA1:PA1050.SAV <SUBSYS>PA1050.SAV\r' > "$FIFO"; sleep 4; printf '\r' > "$FIFO"; sleep 3
: > "$CLOG"
printf 'FAIL\r' > "$FIFO"; sleep 5
printf 'DTA0:XCR_DTA1:XCR.FAI\r' > "$FIFO"; sleep 12
echo "[B] FAIL output:"; tail -10 "$CLOG"
if ! grep -q "PROGRAM BREAK" "$CLOG"; then echo "[B] *** ASSEMBLY FAILED ***"; kill -TERM "$KIPID" 2>/dev/null; exit 1; fi
echo "[B] flush + extract"
kill -TERM "$KIPID" 2>/dev/null; sleep 3
pkill -9 -f console-daemon 2>/dev/null; pkill -9 -f drain.py 2>/dev/null
cd "$LB"; "$TENDMP" -x scratch.dta >/dev/null 2>&1
cp -f xcr.rel netlit.rel; cp -f netlit.rel dta/netlit.rel
"$TENDMP" -T -L TENEX -b "$DTBOOT" -c login.dta netlit.rel subsys/loader.sav subsys/pa1050.sav >/dev/null 2>&1
echo "[B] run tape login.dta rebuilt:"; "$TENDMP" -t login.dta 2>&1 | head -5
