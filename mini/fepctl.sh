#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
CONF=fep-hosts.conf
action="${1:?usage: fepctl.sh start|stop|status host|all}"
target="${2:?usage: fepctl.sh start|stop|status host|all}"

rows() { grep -v '^#' "$CONF" | grep -v '^$'; }
row_for() { rows | awk -F: -v h="$1" '$1==h'; }

# In bulk (`start all`) a host whose NCP socket or backing simulator line is not
# up is SKIPPED (a deployment need not run every host, e.g. OS/360 #65 is absent
# on the droplet). An explicit single-host start stays fail-fast so the operator
# hears about it. ALL_MODE is set from $target below.
start_one() {
    local row="$1"
    IFS=: read -r host ncp port flags <<<"$row"
    if [[ ! -S "$ncp" ]]; then
        echo "fep$host: NCP socket $ncp missing (is ncpdov for host $host running?)" >&2
        [[ "$ALL_MODE" == 1 ]] && { echo "fep$host: skipped"; return; } || exit 1
    fi
    if ! ss -H -ltn | grep -q ":$port "; then
        echo "fep$host: simulator line port $port not listening" >&2
        [[ "$ALL_MODE" == 1 ]] && { echo "fep$host: skipped (host not running here)"; return; } || exit 1
    fi
    screen -ls | grep -q "[.]fep$host[[:space:]]" && { echo "fep$host already running"; return; }
    # ncp-telnet -s serves a SINGLE connection then exits (its NCP re-listen fails
    # with "NCP listen error"), so a bare bridge dies after the first visitor logs
    # in -- the historical FEP "whack-a-mole". Wrap it in a respawn loop so the
    # listener re-arms immediately and the FEP host stays reachable across unlimited
    # logins (inetd-style). arg0 "fepbridge$host" makes the loop greppable; it is
    # the screen window's process-group leader, so stop_one tears the whole tree
    # (loop + ncp-telnet + fep-line.py) down atomically via its pgroup.
    # shellcheck disable=SC2086
    screen -dmS "fep$host" bash -c '
        while true; do
            env NCP="$1" ./ncp-telnet -s -- ./fep-line.py "$2" "$3" $4 || true
            sleep 0.5
        done' "fepbridge$host" "$ncp" "$host" "$port" "$flags"
    echo "fep$host: ARPANET TELNET server on $ncp -> line port $port (auto-respawn)"
}

# Find the ncp-telnet -s server for $host and its fep-line.py children by
# exact command line. `screen -X quit` does not reliably kill this tree, so
# stop_one below verifies and force-kills rather than trusting it.
fep_pids() {
    local host="$1" pids="" more="" loop=""
    # The respawn-loop wrapper (pgroup leader). Listed FIRST so stop_one kills its
    # process group first -- that atomically takes down the loop AND its current
    # ncp-telnet/fep-line.py children, leaving nothing to respawn.
    loop="$(pgrep -f "fepbridge$host " || true)"
    pids="$(pgrep -f "ncp-telnet -s -- \./fep-line\.py $host " || true)"
    more="$(pgrep -f "fep-line\.py $host " || true)"
    printf '%s\n%s\n%s\n' "$loop" "$pids" "$more" | sed '/^$/d' | sort -u
}

stop_one() {
    IFS=: read -r host _ <<<"$1"
    local was_running=0
    if screen -ls | grep -q "[.]fep$host[[:space:]]"; then
        was_running=1
        screen -S "fep$host" -X quit
    fi

    local pids
    pids="$(fep_pids "$host")"
    if [[ -z "$pids" ]]; then
        if [[ "$was_running" -eq 1 ]]; then
            echo "fep$host stopped"
        else
            echo "fep$host: not running"
        fi
        return
    fi

    local pid
    for pid in $pids; do
        kill -TERM -- "-$pid" 2>/dev/null
    done

    local waited=0
    while (( waited < 5000 )); do
        pids="$(fep_pids "$host")"
        [[ -z "$pids" ]] && break
        sleep 0.5
        waited=$((waited + 500))
    done

    if [[ -n "$pids" ]]; then
        for pid in $pids; do
            kill -KILL -- "-$pid" 2>/dev/null
        done
        sleep 0.5
        pids="$(fep_pids "$host")"
    fi

    if [[ -n "$pids" ]]; then
        echo "fep$host: failed to stop, surviving pid(s): $(tr '\n' ' ' <<<"$pids")" >&2
        exit 1
    fi

    echo "fep$host stopped"
}

status_one() { IFS=: read -r host _ <<<"$1"; screen -ls | grep -q "[.]fep$host[[:space:]]" && echo "fep$host: up" || echo "fep$host: down"; }

if [[ "$target" == all ]]; then ALL_MODE=1; list=$(rows); else ALL_MODE=0; list=$(row_for "$target"); [[ -n "$list" ]] || { echo "no FEP entry for host $target" >&2; exit 1; }; fi
while IFS= read -r row; do "${action}_one" "$row"; done <<<"$list"
