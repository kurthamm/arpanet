#!/usr/bin/env bash
# verify-imp-routing.sh -- regression gate for "every visitor session goes through
# the IMP network" (Oscar's requirement). Two checks:
#   1) STATIC: no terminal-line bypass survives in do.sh -- @L must route via
#      dotelnet.sh -> ncp-telnet, never straight to a simulator's terminal port.
#   2) LIVE:   each host actually answers @L through the IMPs (native NCP for ITS,
#      the FEP bridge for Sigma/Multics/OS-360). WAITS is checked via its NCP
#      route (its login is interactive and doesn't emit an auto-banner).
#
# Exit non-zero if any check fails, so `make check` / CI catches a regression.
# Run from anywhere; it locates the repo by its own path.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../mini
ROOT="$(cd "$HERE/.." && pwd)"
DOSH="$ROOT/do.sh"
pass=0; fail=0
green(){ printf '  PASS  %s\n' "$*"; pass=$((pass+1)); }
red(){   printf '  FAIL  %s\n' "$*"; fail=$((fail+1)); }

echo "== 1. Static: no terminal-line bypass in do.sh =="
if grep -q 'local-host-terminal' "$DOSH"; then
    red "do.sh still references local-host-terminal (the bypass)"
elif ! grep -q 'exec ./dotelnet.sh' "$DOSH"; then
    red "do.sh does not route through dotelnet.sh/ncp-telnet"
else
    green "do.sh routes @L only through the IMPs (dotelnet.sh -> ncp-telnet)"
fi

# host : source-SESSION_NUMBER : expected-banner-regex : method
# (source 0-4/... = a TIP NCP; ITS use a non-FEP source, FEP hosts use 0)
HOSTS=(
    "70:5:Dynamic Modelling|turist:native ITS"
    "126:5:ITS PDP-10|turist:native ITS"
    "134:5:Artificial Intelligence|turist:native ITS"
    "198:5:Math Lab|turist:native ITS"
    "1:0:Sigma|MUX device:FEP"
    "6:0:HSLA|Multics:FEP"
    "65:0:CCN|360/91:FEP"
)

echo "== 2. Live: each host answers @L through the IMPs =="
for row in "${HOSTS[@]}"; do
    IFS=: read -r h s rex method <<<"$row"
    out="$( (printf '@L %s\r\n' "$h"; sleep 8) | SESSION_NUMBER="$s" timeout 30 "$DOSH" 2>&1 )"
    if printf '%s' "$out" | tr -d '\r' | grep -qiE "$rex"; then
        green "host $h ($method) -> $(printf '%s' "$out"|tr -d '\r'|grep -iE "$rex"|head -1|cut -c1-40)"
    else
        red "host $h ($method): no expected banner (got: $(printf '%s' "$out"|tr -d '\r'|grep -ivE '^\s*$|TELNET to host'|head -1|cut -c1-40))"
    fi
done

echo "== 3. WAITS #11 (interactive login; checked via NCP route) =="
# Host 11 is reached only via AMES ncp16 today, and that path is intermittent
# under load, so retry a few times before declaring it down (a single timeout is
# not a routing regression).
waits_ok=0
for _try in 1 2 3 4 5; do
    # ncp-ping resolves $NCP as a socket path relative to CWD; use an absolute
    # path so this works no matter where `make check` is invoked from.
    if NCP="$HERE/ncp16" timeout 12 "$HERE/ncp-ping" -c1 11 2>&1 | grep -qi 'reply from host'; then
        waits_ok=1; break
    fi
    sleep 3
done
if [ "$waits_ok" -eq 1 ]; then
    green "host 11 (WAITS via waitsconnect) answers on the ARPANET"
else
    red "host 11 (WAITS) not reachable over the IMPs after 5 tries"
fi

echo "== summary: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
