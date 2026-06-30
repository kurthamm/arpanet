#!/usr/bin/env bash
# host69ctl.sh <daemon|setup|verify|status|stop|restart> [69]
#
# Lifecycle for the BBN-TENEX host #69 ARPANET login service (GOLDEN SNAPSHOT model).
# `@L 69` reaches a real TENEX @ EXEC where the non-privileged DEMO account logs in.
#
# The login state (DEMO account created + NETLIT-1d loaded & LISTENING on socket 1)
# is baked into snap/host69-login.state.  The service just RESTORES it -- no DLUSER,
# no LOADER, no console-FIFO choreography.  Build the snapshot with
# netser-build/build-snap-launch.sh + the WRU/SAVE procedure (see the real-login-gate
# memory) when NETLIT-1d changes.
#
# systemd model (arpanet-host69.service, Type=exec, After/Requires arpanet-noc):
#   ExecStart      = host69ctl.sh daemon  -> foreground SIMH ki (systemd main proc).
#   ExecStartPost  = host69ctl.sh setup   -> wait host-ready (FORCEDOWN re-asserts it
#                    against the live imp05); passive drainers keep the console drained.
#   Restart=on-failure, RestartSec>=90 handles port TIME_WAIT + ki crashes.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H="$ROOT/host69-bbn-tenex"
ACTION="${1:-status}"; HOST="${2:-69}"
[ "$HOST" = "69" ] || { echo "unknown host: $HOST" >&2; exit 1; }

SCR="${NETLIT_SCRATCH:-/tmp/netlit-$USER}"; mkdir -p "$SCR"
HELP="$H/netser-build/scripts"
BIN="$H/kit-cache/rcornwell-sims/BIN/pdp10-ki"
SNAP="$H/snap/host69-login.state"          # GOLDEN snapshot: DEMO + NETLIT listening
DO="$SCR/run-h69.do"; RUNLOG="$H/logs/run-h69.log"

ki_pid() { pgrep -f 'run-h69[.]do' 2>/dev/null | head -1; }

# host69-LOCAL health: ki up and the golden boot reached host-ready.  Mesh routing
# to host 69 is the noc's job and must NOT gate this service.
netlit_up() { [ -n "$(ki_pid)" ] && grep -q "HOST-READY DONE" "$RUNLOG" 2>/dev/null; }
reachable() { ( cd "$ROOT" && NCP=ncp31 timeout 12 ./ncp-ping -c1 69 2>/dev/null | grep -q "Reply from" ); }
# host69's IMP is imp05; its hi2 (imp05.local.simh: attach -u hi2 21051:127.0.0.1:21052) must be
# UP+bound before we assert host-ready, else host69 boots peerless ("Host is not up").  noc starts
# imp05 asynchronously, so the daemon WAITS on this before restore+FORCEDOWN (boot-ordering fix).
imp05_ready() { pgrep -f 'h316ov.*imp05' >/dev/null && ss -uan 2>/dev/null | grep -q ':21051'; }

gen_do() {
  cat > "$DO" <<EOF
echo === BOOT $BOOTID ===
restore -F $SNAP
detach dc
detach tym
detach imp
detach dt0
detach dt1
detach mta0
attach -u dc 16945 speed=2400
attach -u tym 16946
attach -u imp 21052:127.0.0.1:21051
set imp nodebug
set console telnet=2323,nomessage
deposit 57174 777777777777
echo === SETTLE ===
step 200000000
echo === FORCEDOWN host-ready cycle ===
deposit IMP FORCEDOWN 1
step 450000000
deposit IMP FORCEDOWN 0
step 400000000
deposit 70360 0
echo === HOST-READY DONE ===
go
EOF
}

# ExecStart: become the SIMH ki in the foreground (systemd main process).
cmd_daemon() {
  for f in "$BIN" "$SNAP"; do [ -e "$f" ] || { echo "host69: MISSING $f" >&2; exit 1; }; done
  # Clean slate: kill any stray host69 ki/helpers (e.g. a manual launch-1d-login.sh run-1c.do) that
  # would hold 2323/16945/21052 and segfault our console/socket bind.  pdp10-ki is host69-only.
  pkill -9 -x pdp10-ki 2>/dev/null; pkill -9 -f "$HELP/console-daemon.py" 2>/dev/null; pkill -9 -f "$HELP/drain.py" 2>/dev/null
  # Per-boot id + fresh runlog FIRST, so ExecStartPost (run concurrently under Type=exec) anchors to
  # THIS boot and never matches a stale HOST-READY DONE (the .do echoes "=== BOOT $BOOTID ===" first).
  BOOTID="$$-$(date +%s)"; echo "$BOOTID" > "$SCR/host69.bootid"; : > "$RUNLOG"
  # Boot-ordering: wait (<=180s) for imp05 + its hi2 (21051) so host69 asserts host-ready to a READY
  # imp05.  Not up in time -> exit 1 -> systemd Restart=on-failure retries (RestartSec=90).
  local i
  for i in $(seq 1 90); do imp05_ready && break; sleep 2; done
  imp05_ready || { echo "host69: imp05/hi2 (21051) not up after ~180s wait" >&2; exit 1; }
  echo "host69: imp05/hi2 up -- restoring golden snapshot"
  gen_do
  # best-effort port clear; residual TIME_WAIT -> bind fail -> setup fails -> systemd restarts
  for i in $(seq 1 60); do ss -tan 2>/dev/null | grep -qE ':(2323|16945|16946|21052)\b' || break; sleep 1; done
  # passive drainers (children, die with the cgroup): 16945/16946 = DC/TYM lines,
  # 2323 = NETLIT's console -- the 2323 drainer also UNBLOCKS the FORCEDOWN steps
  # (SIMH `set console telnet` waits for a console connection).  drain.py retries.
  python3 "$HELP/drain.py" 16945 "$H/logs/dc16945.log" >/dev/null 2>&1 < /dev/null &
  python3 "$HELP/drain.py" 16946 "$H/logs/tym16946.log" >/dev/null 2>&1 < /dev/null &
  python3 "$HELP/drain.py" 2323  "$H/logs/cty.log"      >/dev/null 2>&1 < /dev/null &
  cd "$H/kit-cache/build-tenex/install" || exit 1
  exec nice -n 5 "$BIN" "$DO" > "$RUNLOG" 2>&1
}

# ExecStartPost: wait for the golden boot to re-assert host-ready.
cmd_setup() {
  local ok=0 i bid
  sleep 3                                   # let cmd_daemon write the bootid file first
  bid="$(cat "$SCR/host69.bootid" 2>/dev/null)"
  echo "host69: golden restore (boot $bid) -- waiting for HOST-READY..."
  # Anchor to THIS boot: wait for the ki to echo '=== BOOT <bid> ===' (covers the daemon's imp05
  # wait + restore).  Until that appears, any HOST-READY DONE in the runlog is stale -> ignore it.
  for i in $(seq 1 150); do
    grep -q "=== BOOT $bid ===" "$RUNLOG" 2>/dev/null && break
    ki_pid >/dev/null || { echo "host69: ki gone before boot marker (see $RUNLOG)" >&2; exit 2; }
    sleep 2
  done
  grep -q "=== BOOT $bid ===" "$RUNLOG" 2>/dev/null || { echo "host69: boot marker $bid never appeared" >&2; exit 2; }
  for i in $(seq 1 110); do
    grep -q "HOST-READY DONE" "$RUNLOG" 2>/dev/null && { ok=1; break; }
    ki_pid >/dev/null || { echo "host69: ki gone during host-ready (see $RUNLOG)" >&2; exit 2; }
    sleep 2
  done
  [ "$ok" = 1 ] || { echo "host69: host-ready timed out (console 2323 bind / TIME_WAIT?)" >&2; exit 2; }
  echo "host69: restored golden snapshot; NETLIT LISTENING, DEMO account ready (@L 69 -> TENEX login)"
  # Best-effort reachability head-start + log.  Does NOT gate the service: mesh convergence is the
  # noc's job and can take minutes; failing here would risk a restart loop (each bounce churns the mesh).
  for i in $(seq 1 6); do
    reachable && { echo "host69: reachable on mesh (ncp-ping 69)"; break; }
    sleep 15
  done
  exit 0
}

do_stop() {
  local pid; pid="$(ki_pid)"
  [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null
  pkill -9 -f "$HELP/drain.py" 2>/dev/null; pkill -9 -f "$HELP/console-daemon.py" 2>/dev/null
  sleep 2
  pkill -9 -x pdp10-ki 2>/dev/null   # host69-only emulator; clear the ki + any stray
  return 0
}

case "$ACTION" in
  daemon)  cmd_daemon ;;
  setup)   cmd_setup ;;
  verify)  if netlit_up; then echo "host69: OK (ki up, golden boot host-ready)"; exit 0; else echo "host69: not up" >&2; exit 1; fi ;;
  status)  if ki_pid >/dev/null; then echo "host69: ki up (pid $(ki_pid))"; else echo "host69: ki down"; fi
           netlit_up && echo "host69: host-ready (golden boot)" || echo "host69: not host-ready"
           reachable && echo "host69: reachable on mesh (ncp-ping 69)" || echo "host69: NOT reachable on mesh (check arpanet-noc / arpanet-recover.sh recover)" ;;
  stop)    do_stop; echo "host69: stopped" ;;
  restart) sudo systemctl restart arpanet-host69.service 2>/dev/null || { do_stop; echo "use systemctl"; } ;;
  *)       echo "Usage: $(basename "$0") <daemon|setup|verify|status|stop> 69" >&2; exit 2 ;;
esac
