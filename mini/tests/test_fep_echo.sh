#!/usr/bin/env bash
# Round trip: TIP-side NCP (host 31) -> IMP network -> test NCP (host 02, SRI-ARC, no FEP host attached) -> `cat`.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -S ncp31 && -S ncp02 ]] || { echo "ncp31/ncp02 sockets missing: start ./arpanet first"; exit 2; }
# Unique session name per invocation: this script is also run two-at-once (see
# the brief's concurrency check) and a shared literal name races between instances.
sess="fep-test-$$"
screen -dmS "$sess" env NCP=ncp02 ./ncp-telnet -s -- cat
trap 'screen -S "$sess" -X quit 2>/dev/null || true' EXIT
sleep 2
# ncp-telnet -c exits as soon as its stdin hits EOF, which can happen before the
# server's echo has made the round trip back over the (multi-hop, sometimes multi-
# second) IMP path; hold stdin open briefly after sending so the reply has time to
# arrive before the client tears its connection down. 8s gives margin for two
# concurrent sessions competing for the same simulated IMP path.
out=$( { printf 'HELLO FEP\r\n'; sleep 10; } | timeout 30 env NCP=ncp31 ./ncp-telnet -c 2 2>/dev/null | tr -d '\r')
grep -q 'HELLO FEP' <<<"$out" || { echo "FAIL: no echo through IMP path; got: $out"; exit 1; }
echo "PASS: FEP round trip through IMPs"
