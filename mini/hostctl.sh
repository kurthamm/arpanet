#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-}"
HOST="${2:-}"

usage() {
    cat <<USAGE
Usage: $(basename "$0") <status|stop|start|restart|verify> <6|70|126|all>

Safely manages the hosted ITS PDP-10 screens. It refuses to start a host
when that host's simulator ports are still owned by an old process.
USAGE
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

host_dir() {
    case "$1" in
        6) echo "host06" ;;
        70) echo "host70" ;;
        126) echo "host126" ;;
        *) fail "unknown host: $1" ;;
    esac
}

clean_dir() {
    case "$1" in
        6) echo "006" ;;
        70) echo "106" ;;
        126) echo "126" ;;
    esac
}

screen_name() {
    case "$1" in
        6) echo "host06" ;;
        70) echo "host70" ;;
        126) echo "host126" ;;
    esac
}

tcp_ports() {
    case "$1" in
        6) echo "16000 16002 16003 16015 16016 16017 16018 16019 16020" ;;
        70) echo "17000 17002 17003 17015 17016 17017 17018 17019 17020" ;;
        126) echo "10000 10002 10003 10015 10016 10017 10018 10019 10020" ;;
    esac
}

udp_ports() {
    case "$1" in
        6) echo "20062" ;;
        70) echo "21062" ;;
        126) echo "21622" ;;
    esac
}

hosts_for() {
    if [[ "$1" == "all" ]]; then
        echo "6 70 126"
    else
        echo "$1"
    fi
}

screen_exists() {
    screen -ls | grep -q "[.]$(screen_name "$1")[[:space:]]"
}

is_host_sim_pid() {
    local pid="$1"
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q 'pdp10-ka-fixed ./mini-run'
}

port_pids() {
    local host="$1" port pid
    {
        for port in $(tcp_ports "$host"); do
            lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
        done
        for port in $(udp_ports "$host"); do
            lsof -nP -tiUDP:"$port" 2>/dev/null || true
        done
    } | sort -n -u | while read -r pid; do
        [[ -z "$pid" ]] && continue
        if is_host_sim_pid "$pid"; then
            echo "$pid"
        fi
    done
}

pgid_for_pid() {
    ps -o pgid= -p "$1" 2>/dev/null | tr -d ' '
}

print_owners() {
    local host="$1" pids
    pids="$(port_pids "$host" | tr '\n' ' ')"
    if [[ -z "${pids// }" ]]; then
        echo "host $host: no owned simulator ports"
        return
    fi
    echo "host $host: owned simulator ports by PID(s): $pids"
    ps -o pid,ppid,pgid,sid,stat,args -p $pids 2>/dev/null || true
}

kill_host_port_owners() {
    local host="$1" pid pgid pgids
    pgids=""
    while read -r pid; do
        [[ -z "$pid" ]] && continue
        pgid="$(pgid_for_pid "$pid")"
        [[ -z "$pgid" ]] && continue
        pgids+="$pgid "
    done < <(port_pids "$host")

    pgids="$(tr ' ' '\n' <<<"$pgids" | sed '/^$/d' | sort -n -u | tr '\n' ' ')"
    [[ -z "${pgids// }" ]] && return

    echo "host $host: terminating process group(s): $pgids"
    for pgid in $pgids; do
        kill -TERM "-$pgid" 2>/dev/null || true
    done
    sleep 3
    for pgid in $pgids; do
        kill -KILL "-$pgid" 2>/dev/null || true
    done
}

wait_ports_clear() {
    local host="$1" deadline=$((SECONDS + 15))
    while (( SECONDS < deadline )); do
        if [[ -z "$(port_pids "$host")" ]]; then
            return 0
        fi
        sleep 1
    done
    print_owners "$host"
    return 1
}

restore_clean_packs() {
    local host="$1" dir clean backup_root ts
    dir="$(host_dir "$host")"
    clean="$(clean_dir "$host")"
    backup_root="${ARPANET_HOST_BACKUP_DIR:-$HOME/arpanet-runtime-backups}"
    ts="$(date +%Y%m%d-%H%M%S)"

    mkdir -p "$backup_root/$dir-$ts"
    cp -p "$ROOT/$dir"/rp03.* "$backup_root/$dir-$ts"/ 2>/dev/null || true
    cp -p "$ROOT/$dir/$clean"/rp03.* "$ROOT/$dir"/
    cp -p "$ROOT/$dir/$clean"/dskdmp.rim "$ROOT/$dir"/ 2>/dev/null || true
    echo "host $host: restored clean packs; previous packs saved under $backup_root/$dir-$ts"
}

status_host() {
    local host="$1"
    if screen_exists "$host"; then
        echo "host $host: screen $(screen_name "$host") present"
    else
        echo "host $host: screen $(screen_name "$host") absent"
    fi
    print_owners "$host"
}

stop_host() {
    local host="$1"
    echo "host $host: stopping"
    screen -S "$(screen_name "$host")" -X quit 2>/dev/null || true
    sleep 1
    kill_host_port_owners "$host"
    wait_ports_clear "$host" || fail "host $host ports did not clear"
    echo "host $host: stopped"
}

start_host() {
    local host="$1" dir
    dir="$(host_dir "$host")"
    [[ -z "$(port_pids "$host")" ]] || fail "host $host ports already owned; run stop first"
    if screen_exists "$host"; then
        fail "screen $(screen_name "$host") already exists; run stop first"
    fi
    restore_clean_packs "$host"
    echo "host $host: starting screen $(screen_name "$host")"
    (cd "$ROOT/$dir" && screen -dmS "$(screen_name "$host")" ../pdp10-ka-fixed ./mini-run)
}

verify_host() {
    local host="$1" dest deadline=$((SECONDS + 120))
    case "$host" in
        6) dest=6 ;;
        70) dest=70 ;;
        126) dest=126 ;;
    esac
    while (( SECONDS < deadline )); do
        if (cd "$ROOT" && timeout 10 env NCP=ncp31 ./ncp-ping -c1 "$dest" >/tmp/hostctl-ncp.$host 2>&1); then
            cat /tmp/hostctl-ncp.$host
            echo "host $host: NCP verified"
            return 0
        fi
        sleep 5
    done
    cat /tmp/hostctl-ncp.$host 2>/dev/null || true
    return 1
}

restart_host() {
    local host="$1"
    stop_host "$host"
    start_host "$host"
    verify_host "$host" || fail "host $host did not pass NCP verification"
}

[[ -n "$ACTION" && -n "$HOST" ]] || { usage; exit 2; }
case "$ACTION" in
    status|stop|start|restart|verify) ;;
    *) usage; exit 2 ;;
esac

for host in $(hosts_for "$HOST"); do
    case "$ACTION" in
        status) status_host "$host" ;;
        stop) stop_host "$host" ;;
        start) start_host "$host" ;;
        restart) restart_host "$host" ;;
        verify) verify_host "$host" ;;
    esac
done
