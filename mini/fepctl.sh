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
stop_one() { IFS=: read -r host _ <<<"$1"; screen -S "fep$host" -X quit 2>/dev/null || true; echo "fep$host stopped"; }
status_one() { IFS=: read -r host _ <<<"$1"; screen -ls | grep -q "[.]fep$host[[:space:]]" && echo "fep$host: up" || echo "fep$host: down"; }

if [[ "$target" == all ]]; then list=$(rows); else list=$(row_for "$target"); [[ -n "$list" ]] || { echo "no FEP entry for host $target" >&2; exit 1; }; fi
while IFS= read -r row; do "${action}_one" "$row"; done <<<"$list"
