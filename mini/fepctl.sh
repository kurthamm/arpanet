#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
CONF=fep-hosts.conf
action="${1:?usage: fepctl.sh start|stop|status host|all}"
target="${2:?usage: fepctl.sh start|stop|status host|all}"

rows() { grep -v '^#' "$CONF" | grep -v '^$'; }
row_for() { rows | awk -F: -v h="$1" '$1==h'; }

start_one() {
    local row="$1"
    IFS=: read -r host ncp port flags <<<"$row"
    [[ -S "$ncp" ]] || { echo "fep$host: NCP socket $ncp missing (is ncpdov for host $host running?)" >&2; exit 1; }
    ss -H -ltn | grep -q ":$port " || { echo "fep$host: simulator line port $port not listening" >&2; exit 1; }
    screen -ls | grep -q "[.]fep$host[[:space:]]" && { echo "fep$host already running"; return; }
    # shellcheck disable=SC2086
    screen -dmS "fep$host" env NCP="$ncp" ./ncp-telnet -s -- ./fep-line.py "$host" "$port" $flags
    echo "fep$host: ARPANET TELNET server on $ncp -> line port $port"
}

# Find the ncp-telnet -s server for $host and its fep-line.py children by
# exact command line. `screen -X quit` does not reliably kill this tree, so
# stop_one below verifies and force-kills rather than trusting it.
fep_pids() {
    local host="$1" pids=""
    if pids="$(pgrep -f "ncp-telnet -s -- \./fep-line\.py $host ")"; then
        :
    else
        pids=""
    fi
    local more=""
    if more="$(pgrep -f "fep-line\.py $host ")"; then
        :
    else
        more=""
    fi
    printf '%s\n%s\n' "$pids" "$more" | sed '/^$/d' | sort -u
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

if [[ "$target" == all ]]; then list=$(rows); else list=$(row_for "$target"); [[ -n "$list" ]] || { echo "no FEP entry for host $target" >&2; exit 1; }; fi
while IFS= read -r row; do "${action}_one" "$row"; done <<<"$list"
