#!/usr/bin/env bash
# host69ctl.sh <daemon|setup|verify|status|stop|restart> [69]
#
# Lifecycle for the BBN-TENEX host #69 ARPANET login service.  `@L 69` reaches a
# real TENEX @ EXEC where the non-privileged DEMO account can log in.
#
# systemd model (arpanet-host69.service, Type=exec, After/Requires arpanet-noc):
#   ExecStart      = host69ctl.sh daemon  -> foreground SIMH ki (the main process
#                    systemd tracks/keeps alive; oneshot would SIGTERM it).
#   ExecStartPost  = host69ctl.sh setup   -> land host-ready, create DEMO (DLUSER),
#                    load NETLIT, leave it LISTENING.
#   Restart=on-failure handles a port still in TIME_WAIT ("bind error 98") and ki
#                    crashes -- systemd just relaunches.
# No tmux/screen needed: the ki is systemd's main process.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H="$ROOT/host69-bbn-tenex"
ACTION="${1:-status}"; HOST="${2:-69}"
[ "$HOST" = "69" ] || { echo "unknown host: $HOST" >&2; exit 1; }

SCR="${NETLIT_SCRATCH:-/tmp/netlit-$USER}"; mkdir -p "$SCR"
HELP="$H/netser-build/scripts"
FIFO="$SCR/cty.fifo"; CLOG="$H/logs/cty.log"
LB="$H/runtime/login-build"
BIN="$H/kit-cache/rcornwell-sims/BIN/pdp10-ki"; SNAP="$H/snap/host69-live.state"
DO="$SCR/run-h69.do"; RUNLOG="$H/logs/run-h69.log"

ki_pid() { pgrep -f 'run-h69[.]do' 2>/dev/null | head -1; }

# host69-LOCAL health: ki up and NETLIT reached LISTENING.  Mesh routing to host
# 69 is the noc's job and must NOT gate this service.
netlit_up() { [ -n "$(ki_pid)" ] && grep -q "LISTENING" "$CLOG" 2>/dev/null; }
reachable() { ( cd "$ROOT" && NCP=ncp31 timeout 12 ./ncp-ping -c1 69 2>/dev/null | grep -q "Reply from" ); }

gen_do() {
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
deposit 70360 0
echo === HOST-READY DONE ===
go
EOF
}

# ExecStart: become the SIMH ki in the foreground (systemd main process).
cmd_daemon() {
  pgrep -f 'h316ov' >/dev/null || { echo "host69: lab/imp05 (h316ov) not running" >&2; exit 1; }
  for f in "$BIN" "$SNAP" "$LB/login.dta"; do [ -e "$f" ] || { echo "host69: MISSING $f" >&2; exit 1; }; done
  gen_do
  rm -f "$FIFO"; mkfifo "$FIFO" 2>/dev/null || true
  : > "$CLOG"; : > "$RUNLOG"
  # best-effort port clear; residual TIME_WAIT -> bind fail -> setup fails -> systemd restarts
  for i in $(seq 1 60); do ss -tan 2>/dev/null | grep -qE ':(2323|16945|16946|21052)\b' || break; sleep 1; done
  # drainers as children (keep DC/TYM console buffers drained; die with the cgroup)
  python3 "$HELP/drain.py" 16945 "$H/logs/dc16945.log" >/dev/null 2>&1 < /dev/null &
  python3 "$HELP/drain.py" 16946 "$H/logs/tym16946.log" >/dev/null 2>&1 < /dev/null &
  cd "$H/kit-cache/build-tenex/install" || exit 1
  exec nice -n 5 "$BIN" "$DO" > "$RUNLOG" 2>&1
}

# ExecStartPost: land host-ready, create DEMO, load NETLIT -> LISTENING.
cmd_setup() {
  local ok=0 i
  # The ki does `set console telnet=2323` then `step`, which BLOCKS until a telnet
  # client connects to 2323.  So we must connect the console-daemon FIRST (once the
  # ki has bound 2323) -- otherwise host-ready never advances.  If 2323 never binds
  # (TIME_WAIT from a prior ki), fail so systemd restarts us.
  ok=0
  for i in $(seq 1 120); do
    ss -ltn 2>/dev/null | grep -q ':2323' && { ok=1; break; }
    ki_pid >/dev/null || { echo "host69: ki gone before console bound" >&2; exit 2; }
    sleep 1
  done
  [ "$ok" = 1 ] || { echo "host69: console 2323 never bound (TIME_WAIT?) -- failing for restart" >&2; exit 2; }
  setsid python3 "$HELP/console-daemon.py" 2323 "$FIFO" "$CLOG" >/dev/null 2>&1 < /dev/null &
  sleep 2

  echo "host69: waiting for HOST-READY (~75-120s)..."
  ok=0
  for i in $(seq 1 100); do
    grep -q "HOST-READY DONE" "$RUNLOG" 2>/dev/null && { ok=1; break; }
    ki_pid >/dev/null || { echo "host69: ki gone during host-ready" >&2; exit 2; }
    sleep 2
  done
  [ "$ok" = 1 ] || { echo "host69: host-ready timed out" >&2; exit 2; }
  sleep 3

  ok=0
  for i in $(seq 1 15); do : > "$CLOG"; printf '\r' > "$FIFO"; sleep 1; grep -q '!' "$CLOG" && { ok=1; break; }; done
  [ "$ok" = 1 ] || { echo "host69: console did not reach EXEC" >&2; exit 3; }

  W(){ printf '%s\r' "$1" > "$FIFO"; sleep "${2:-3}"; }
  W "MOUNT DTA1:" 3
  W "RUN DTA1:DLUSER.SAV" 5            # create non-priv DEMO (cosmetic CAN'T CREATE is OK)
  W "L" 3
  W "DTA1:DEMUSR.TXT" 6
  W "" 4
  W "COPY DTA1:LOADER.SAV <SUBSYS>" 5; W "" 3
  W "COPY DTA1:PA1050.SAV <SUBSYS>" 5; W "" 3
  : > "$CLOG"
  W "LOADER" 5
  W "DTA1:NETLIT" 5
  printf '\033G' > "$FIFO"; sleep 4
  printf '\r'    > "$FIFO"; sleep 3
  : > "$CLOG"
  W "START" 6
  if grep -q "LISTENING" "$CLOG"; then
    echo "host69: NETLIT LISTENING on socket 1 (@L 69 -> TENEX login; DEMO account ready)"
    exit 0
  fi
  echo "host69: NETLIT did not reach LISTENING (see $CLOG)" >&2
  exit 4
}

do_stop() {
  local pid; pid="$(ki_pid)"
  [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null
  pkill -9 -f "console-daemon.py 2323" 2>/dev/null
  pkill -9 -f "$HELP/drain.py" 2>/dev/null
  sleep 2
  pid="$(ki_pid)"; [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  return 0
}

case "$ACTION" in
  daemon)  cmd_daemon ;;
  setup)   cmd_setup ;;
  verify)  if netlit_up; then echo "host69: OK (ki up, NETLIT listening)"; exit 0; else echo "host69: NETLIT not up" >&2; exit 1; fi ;;
  status)  if ki_pid >/dev/null; then echo "host69: ki up (pid $(ki_pid))"; else echo "host69: ki down"; fi
           netlit_up && echo "host69: NETLIT listening" || echo "host69: NETLIT not listening"
           reachable && echo "host69: reachable on mesh (ncp-ping 69)" || echo "host69: NOT reachable on mesh (check arpanet-noc / arpanet-recover.sh recover)" ;;
  stop)    do_stop; echo "host69: stopped" ;;
  restart) sudo systemctl restart arpanet-host69.service 2>/dev/null || { do_stop; echo "use systemctl"; } ;;
  *)       echo "Usage: $(basename "$0") <daemon|setup|verify|status|stop> 69" >&2; exit 2 ;;
esac
