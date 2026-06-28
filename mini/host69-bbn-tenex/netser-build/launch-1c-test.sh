#!/usr/bin/env bash
# launch-1c-test.sh -- launch host69 on the host-ready (FORCEDOWN) path with the
# NETLIT run tape, then load + START NETLIT and leave it LISTENING.  Repo-local /
# self-contained.  After it prints "LISTENING", from mini/ run:
#     NCP=ncp31 ./ncp-telnet -o 69
# and watch  mini/host69-bbn-tenex/logs/cty.log  for:
#     RFC RECEIVED / CONTACT ACCEPTED / SOCKET NUMBER SENT / DATA SOCKETS OPEN / HERALD SENT
# Success: the client prints  BBN-TENEX NETLIT TEST
# Requires imp05 (h316ov) already running (the lab).  Override scratch: NETLIT_SCRATCH=...
set -u
H="$(cd "$(dirname "$0")/.." && pwd)"
SCR="${NETLIT_SCRATCH:-/tmp/netlit-$USER}"; mkdir -p "$SCR"
HELP="$H/netser-build/scripts"
FIFO="$SCR/cty.fifo"; CLOG="$H/logs/cty.log"
LB="$H/runtime/login-build"; INST="$H/kit-cache/build-tenex/install"
BIN="$H/kit-cache/rcornwell-sims/BIN/pdp10-ki"; SNAP="$H/snap/host69-live.state"
DO="$SCR/run-1c.do"
for f in "$BIN" "$SNAP" "$LB/login.dta" "$HELP/console-daemon.py" "$HELP/drain.py"; do
  [ -e "$f" ] || { echo "MISSING: $f"; exit 1; }
done
pgrep -f 'h316ov' >/dev/null || echo "WARNING: imp05/lab (h316ov) not running -- start the lab first or the network test won't work"

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
attach -u imp 21052:127.0.0.1:21051
attach dt0  $LB/scratch.dta
attach -r dt1  $LB/login.dta
attach -r mta0 $LB/login.tap
set imp nodebug
set console telnet=2323,nomessage
deposit 57174 777777777777
echo === SETTLE ===
step 250000000
echo === FORCEDOWN host-ready cycle ===
deposit IMP FORCEDOWN 1
step 450000000
deposit IMP FORCEDOWN 0
step 400000000
echo === clear IMPFLS ===
deposit 70360 0
echo === HOST-READY DONE ===
go
EOF

echo "[T] launch host69 (host-ready path), scratch=$SCR"
pkill -9 -x pdp10-ki 2>/dev/null; pkill -9 -f console-daemon 2>/dev/null; pkill -9 -f "$HELP/drain.py" 2>/dev/null; rm -f "$FIFO"
for i in $(seq 1 60); do ss -tan 2>/dev/null | grep -qE ':(16945|16946|2323)\b' || break; sleep 1; done
: > "$CLOG"; : > "$H/logs/run-1c.log"
python3 "$HELP/drain.py" 16945 "$H/logs/dc16945.log" >/dev/null 2>&1 &
python3 "$HELP/drain.py" 16946 "$H/logs/tym16946.log" >/dev/null 2>&1 &
sleep 1
( cd "$INST" && nice -n 5 "$BIN" "$DO" > "$H/logs/run-1c.log" 2>&1 < /dev/null ) &
KIPID=$!; echo "[T] KIPID=$KIPID"
for i in $(seq 1 60); do ss -ltn 2>/dev/null | grep -q ':2323' && break; sleep 0.5; done
python3 "$HELP/console-daemon.py" 2323 "$FIFO" "$CLOG" >/dev/null 2>&1 &

echo "[T] waiting for HOST-READY (~75-120s)..."
for i in $(seq 1 80); do
  grep -q "HOST-READY DONE" "$H/logs/run-1c.log" 2>/dev/null && { echo "[T] host-ready after ~${i}x2s"; break; }
  pgrep -x pdp10-ki >/dev/null || { echo "[T] KI DIED during host-ready (see logs/run-1c.log)"; exit 2; }
  sleep 2
done
sleep 3

# verify EXEC
EXECOK=0
for i in $(seq 1 15); do : > "$CLOG"; printf '\r' > "$FIFO"; sleep 1; grep -q '!' "$CLOG" && { EXECOK=1; break; }; done
[ "$EXECOK" = 1 ] || { echo "[T] console did not reach EXEC; ki left running for inspection"; exit 3; }
echo "[T] EXEC ready -- loading NETLIT"

W(){ printf '%s\r' "$1" > "$FIFO"; sleep "${2:-3}"; }
W "MOUNT DTA1:" 3
W "COPY DTA1:LOADER.SAV <SUBSYS>" 5; W "" 3      # confirm [New file]
W "COPY DTA1:PA1050.SAV <SUBSYS>" 5; W "" 3
: > "$CLOG"
W "LOADER" 5
W "DTA1:NETLIT" 5
printf '\033G' > "$FIFO"; sleep 4
printf '\r'    > "$FIFO"; sleep 3
: > "$CLOG"
W "START" 6
echo "[T] NETLIT startup:"; tail -8 "$CLOG"
if grep -q "OPENF OK LISTENING\|LISTENING" "$CLOG"; then
  echo
  echo "[T] *** NETLIT IS LISTENING ON SOCKET 1 ***"
  echo "[T] Now, from $H/.. (the mini/ dir), run:    NCP=ncp31 ./ncp-telnet -o 69"
  echo "[T] Watch  $CLOG  for: RFC RECEIVED / CONTACT ACCEPTED / SOCKET NUMBER SENT / DATA SOCKETS OPEN / HERALD SENT"
  echo "[T] Success = the client prints:  BBN-TENEX NETLIT TEST"
  echo "[T] (host69 KIPID=$KIPID left running; kill -TERM it when done.)"
else
  echo "[T] NETLIT did not reach LISTENING -- check copyfile.sh path / the load sequence above."
fi
