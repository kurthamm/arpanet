#!/usr/bin/env bash
# Round trip: TIP-side NCP (host 31) -> IMP network -> test NCP (host 02, SRI-ARC, no FEP host attached) -> `cat`.
# Concurrency is tested within a single run: one FEP server, two parallel client sessions.
# (Running the whole script twice would start two ncp-telnet -s servers competing for the
# same single listener slot on ncp02 socket 23 -- the daemon has room for only one, so the
# second registration displaces the first, and whichever script instance finishes first
# tears down the "fep-test" screen that both instances' clients depend on.)
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -S ncp31 && -S ncp02 ]] || { echo "ncp31/ncp02 sockets missing: start ./arpanet first"; exit 2; }

if screen -ls 2>/dev/null | grep -q "[.]fep-test[[:space:]]"; then
  echo "fep-test screen session already exists -- refusing to start a second FEP server on ncp02 socket 23" >&2
  exit 2
fi

screen -dmS fep-test env NCP=ncp02 ./ncp-telnet -s -- cat

outA=$(mktemp)
outB=$(mktemp)
trap 'rm -f "$outA" "$outB"; if screen -ls 2>/dev/null | grep -q "[.]fep-test[[:space:]]"; then screen -S fep-test -X quit; fi' EXIT

sleep 2

# ncp-telnet -c exits as soon as its stdin hits EOF, which can happen before the
# server's echo has made the round trip back over the (multi-hop, sometimes multi-
# second) IMP path; hold stdin open briefly after sending so the reply has time to
# arrive before the client tears its connection down. 10s gives margin for two
# concurrent sessions competing for the same simulated IMP path.
run_client () {
  local marker="$1"
  local outfile="$2"
  { printf '%s\r\n' "$marker"; sleep 10; } \
    | timeout 30 env NCP=ncp31 ./ncp-telnet -c 2 2>/dev/null \
    | tr -d '\r' > "$outfile"
}

run_client "HELLO FEP A" "$outA" &
pidA=$!
run_client "HELLO FEP B" "$outB" &
pidB=$!

set +e
wait "$pidA"; rcA=$?
wait "$pidB"; rcB=$?
set -e

a=$(cat "$outA")
b=$(cat "$outB")

if grep -q 'HELLO FEP A' <<<"$a" && grep -q 'HELLO FEP B' <<<"$b"; then
  echo "PASS: FEP round trip through IMPs (2 concurrent sessions)"
else
  echo "FAIL: concurrent round trip missing a marker (client rc: A=$rcA B=$rcB)"
  echo "--- client A output ---"
  echo "$a"
  echo "--- client B output ---"
  echo "$b"
  exit 1
fi
