#!/usr/bin/env bash
# fep-wait-and-start.sh -- wait (bounded) for the NCP sockets that the FEP hosts
# need, then start the FEP bridges. Shared by both entry points: the interactive
# `mini/arpanet` launcher and deploy/systemd/arpanet-fep.service.
#
# The NOC (arpanet-noc) creates each FEP host's NCP socket (mini/ncpNN) when that
# host's IMP reaches RUNNING. An `ncp-telnet -s` bridge cannot bind its source NCP
# until that socket exists, so we wait for them before `fepctl start all`.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

CONF="fep-hosts.conf"
TIMEOUT="${FEP_SOCKET_TIMEOUT:-60}"

[[ -f "$CONF" ]] || { echo "fep-wait-and-start: missing $CONF" >&2; exit 1; }

# Socket name is field 2 of each non-comment, non-blank line: host:ncpNN:port:flags
mapfile -t sockets < <(grep -vE '^\s*(#|$)' "$CONF" | cut -d: -f2 | sort -u)
[[ ${#sockets[@]} -gt 0 ]] || { echo "fep-wait-and-start: no FEP hosts in $CONF" >&2; exit 1; }

echo "Waiting (<=${TIMEOUT}s) for FEP NCP sockets: ${sockets[*]}"
waited=0
while :; do
  missing=()
  for s in "${sockets[@]}"; do
    [[ -S "$s" ]] || missing+=("$s")
  done
  (( ${#missing[@]} == 0 )) && break
  if (( waited >= TIMEOUT )); then
    echo "ERROR: FEP NCP sockets did not appear within ${TIMEOUT}s: ${missing[*]}" >&2
    exit 1
  fi
  sleep 2
  waited=$((waited + 2))
done

exec ./fepctl.sh start all
