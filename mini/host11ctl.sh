#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-}"
HOST="${2:-11}"

usage() {
    cat <<USAGE
Usage: $(basename "$0") <status|stop|start|restart|verify> 11

Safely manages the Stanford/SU-AI WAITS PDP-10 host and its ARPANET bridge.
USAGE
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ "$HOST" == "11" ]] || fail "unknown host: $HOST"

tcp_ports() {
    echo "1025 2040 2041 2042 2043"
}

udp_ports() {
    echo "20112"
}

ensure_waits_files() {
    local url zip missing file
    url="https://obsolescence.dev/pidp10-sw/waits.zip"
    zip="$ROOT/host11/waits.zip"
    missing=0

    for file in DISK.octal SYS000.ckd SYS001.ckd SYS002.ckd SYSTEM.DMP.49 SYSTEM.DMP.K17; do
        if [[ ! -f "$ROOT/host11/$file" ]]; then
            echo "host 11: missing $file"
            missing=1
        fi
    done

    if [[ "$missing" == "0" ]]; then
        return
    fi

    echo "host 11: downloading WAITS archive"
    if [[ ! -f "$zip" ]]; then
        curl -fL "$url" -o "$zip"
    fi
    (cd "$ROOT/host11" && unzip -o "$zip")
}

screen_exists() {
    local name="$1"
    screen -ls | grep -q "[.]$name[[:space:]]"
}

is_host11_pid() {
    local pid="$1" cmdline
    cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
    grep -Eq 'pdp10-ka ./waits\.ini|waitsconnect' <<<"$cmdline"
}

port_pids() {
    local port pid
    {
        for port in $(tcp_ports); do
            lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
        done
        for port in $(udp_ports); do
            lsof -nP -tiUDP:"$port" 2>/dev/null || true
        done
    } | sort -n -u | while read -r pid; do
        [[ -z "$pid" ]] && continue
        if is_host11_pid "$pid"; then
            echo "$pid"
        fi
    done
}

pgid_for_pid() {
    ps -o pgid= -p "$1" 2>/dev/null | tr -d ' '
}

print_owners() {
    local pids
    pids="$(port_pids | tr '\n' ' ')"
    if [[ -z "${pids// }" ]]; then
        echo "host 11: no owned WAITS ports"
        return
    fi
    echo "host 11: owned WAITS ports by PID(s): $pids"
    ps -o pid,ppid,pgid,sid,stat,args -p $pids 2>/dev/null || true
}

kill_host11_port_owners() {
    local pid pgid pgids
    pgids=""
    while read -r pid; do
        [[ -z "$pid" ]] && continue
        pgid="$(pgid_for_pid "$pid")"
        [[ -z "$pgid" ]] && continue
        pgids+="$pgid "
    done < <(port_pids)

    pgids="$(tr ' ' '\n' <<<"$pgids" | sed '/^$/d' | sort -n -u | tr '\n' ' ')"
    [[ -z "${pgids// }" ]] && return

    echo "host 11: terminating process group(s): $pgids"
    for pgid in $pgids; do
        kill -TERM "-$pgid" 2>/dev/null || true
    done
    sleep 3
    for pgid in $pgids; do
        kill -KILL "-$pgid" 2>/dev/null || true
    done
}

wait_ports_clear() {
    local deadline=$((SECONDS + 15))
    while (( SECONDS < deadline )); do
        if [[ -z "$(port_pids)" ]]; then
            return 0
        fi
        sleep 1
    done
    print_owners
    return 1
}

backup_packs_once() {
    local backup_root backup_dir marker
    backup_root="${ARPANET_HOST11_BACKUP_DIR:-$HOME/arpanet-runtime-backups}"
    backup_dir="$backup_root/host11-initial"
    marker="$backup_dir/.complete"

    if [[ -f "$marker" ]]; then
        echo "host 11: initial WAITS pack backup already present at $backup_dir"
        return
    fi

    mkdir -p "$backup_dir"
    cp -p "$ROOT/host11"/SYS*.ckd "$backup_dir"/
    date -u +%Y-%m-%dT%H:%M:%SZ >"$marker"
    echo "host 11: backed up WAITS packs to $backup_dir"
}

build_waitsconnect() {
    if [[ ! -x "$ROOT/src/waits-ncpd/waitsconnect" ]] ||
       [[ "$ROOT/src/waits-ncpd/waitsconnect.c" -nt "$ROOT/src/waits-ncpd/waitsconnect" ]] ||
       [[ "$ROOT/src/waits-ncpd/imp.c" -nt "$ROOT/src/waits-ncpd/waitsconnect" ]]; then
        echo "host 11: building waitsconnect"
        make -C "$ROOT/src/waits-ncpd" waitsconnect
    fi
    [[ -x "$ROOT/host11/waitsconnect" ]] || fail "host 11 waitsconnect is not executable"
}

status_host() {
    for name in host11 waitsconnect; do
        if screen_exists "$name"; then
            echo "host 11: screen $name present"
        else
            echo "host 11: screen $name absent"
        fi
    done
    print_owners
}

stop_host() {
    echo "host 11: stopping"
    screen -S waitsconnect -X quit 2>/dev/null || true
    screen -S host11 -X quit 2>/dev/null || true
    sleep 1
    kill_host11_port_owners
    wait_ports_clear || fail "host 11 ports did not clear"
    echo "host 11: stopped"
}

start_host() {
    [[ -z "$(port_pids)" ]] || fail "host 11 ports already owned; run stop first"
    if screen_exists host11 || screen_exists waitsconnect; then
        fail "host 11 screen already exists; run stop first"
    fi
    ensure_waits_files
    backup_packs_once
    build_waitsconnect
    echo "host 11: starting screen host11"
    (cd "$ROOT/host11" && screen -dmS host11 ./pdp10-ka ./waits.ini)
    sleep 5
    echo "host 11: starting screen waitsconnect"
    (cd "$ROOT/host11" && screen -dmS waitsconnect ./waitsconnect)
}

verify_host() {
    local deadline=$((SECONDS + 120)) output
    while (( SECONDS < deadline )); do
        if output="$(cd "$ROOT" && timeout 10 env NCP=ncp16 ./ncp-ping -c1 11 2>&1)"; then
            printf '%s\n' "$output"
            echo "host 11: NCP verified"
            return 0
        fi
        sleep 5
    done
    printf '%s\n' "${output:-}"
    return 1
}

restart_host() {
    stop_host
    start_host
    verify_host || fail "host 11 did not pass NCP verification"
}

[[ -n "$ACTION" ]] || { usage; exit 2; }
case "$ACTION" in
    status) status_host ;;
    stop) stop_host ;;
    start) start_host ;;
    restart) restart_host ;;
    verify) verify_host ;;
    *) usage; exit 2 ;;
esac
