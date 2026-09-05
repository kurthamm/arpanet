#!/usr/bin/env bash
# verify-imp-routing.sh -- regression gate for "every visitor session goes through
# the IMP network" (Oscar's requirement). Two checks:
#   1) STATIC: no terminal-line bypass survives in do.sh -- @L must route via
#      dotelnet.sh -> ncp-telnet, never straight to a simulator's terminal port.
#   2) LIVE:   each host actually serves @L through the IMPs. This delegates to
#      arpanet-health.sh, which probes the REAL @L visitor path per host (not
#      ncp-ping, which the IMP answers even when the guest is dead). The old gate
#      used an ncp16 ncp-ping false-positive and referenced the retired
#      waitsconnect bridge -- both removed.
#
# Exit non-zero if any required check fails, so `make check` / CI catches a
# regression. host 69 (TENEX) and host 41 (PiDP-10) are in-flight and reported
# informationally, not as gate failures.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../mini
ROOT="$(cd "$HERE/.." && pwd)"
DOSH="$ROOT/do.sh"
pass=0; fail=0
green(){ printf '  PASS  %s\n' "$*"; pass=$((pass+1)); }
red(){   printf '  FAIL  %s\n' "$*"; fail=$((fail+1)); }
info(){  printf '  INFO  %s\n' "$*"; }

echo "== 1. Static: no terminal-line bypass in do.sh =="
if grep -q 'local-host-terminal' "$DOSH"; then
    red "do.sh still references local-host-terminal (the bypass)"
elif ! grep -q 'exec ./dotelnet.sh' "$DOSH"; then
    red "do.sh does not route through dotelnet.sh/ncp-telnet"
else
    green "do.sh routes @L only through the IMPs (dotelnet.sh -> ncp-telnet)"
fi

# Hosts this effort is responsible for -- must serve @L through the IMPs.
REQUIRED="70 126 134 198 1 6 11 65"
# In-flight, other owner -- reported but never fail the gate.
INFLIGHT="69 41"

echo "== 2. Live: each host serves @L through the IMPs (via arpanet-health.sh) =="
health="$("$HERE/arpanet-health.sh" 2>/dev/null)"
printf '%s\n' "$health" | sed 's/^/    /'

status_of(){ printf '%s\n' "$health" | awk -v h="$1" '$1==h {print $4}'; }

for h in $REQUIRED; do
    st="$(status_of "$h")"
    if [ "$st" = "UP" ]; then green "host $h serves @L through the IMPs"
    else red "host $h does not serve @L (status: ${st:-unknown})"; fi
done
for h in $INFLIGHT; do
    st="$(status_of "$h")"
    info "host $h (in-flight): ${st:-not-probed}"
done

echo "== summary: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
