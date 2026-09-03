#!/usr/bin/env bash
# login-test.sh [N] -- drive N back-to-back authentic @L 69 logins against host69 (NETLIT-1e),
# proving the service serves real credentialed DEMO logins and re-listens between sessions.
#
# WHY this shape (hard-won): ncp-telnet must be driven with stdin from a HELD-OPEN pipe (raw fd),
# NOT a pty/pexpect -- under a pty the TENEX herald deterministically stalls at ~28 bytes and the
# session dies.  Each session holds the connection through a clean LOGOUT (a client EOF mid-session
# drops carrier and kills the login job).  Run from anywhere; needs a healthy mesh + host69 up.
#
# Account: DEMO / DEMO / 1 (non-privileged).  Client socket: -o (old telnet, socket 1).
set -u
MINI="$(cd "$(dirname "$0")/../../.." && pwd)"   # .../mini
cd "$MINI" || exit 1
N="${1:-5}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0
for n in $(seq 1 "$N"); do
  out="$TMP/s$n.out"; FIFO="$TMP/in$n.fifo"; mkfifo "$FIFO"
  exec 9<>"$FIFO"
  NCP=ncp31 timeout -s KILL 40 ./ncp-telnet -o 69 <&9 > "$out" 2>&1 &
  TP=$!
  sleep 8;  printf '\r'                 >&9   # kick the herald
  sleep 4;  printf 'LOGIN DEMO DEMO 1\r' >&9
  sleep 5;  printf 'SYSTAT\r'            >&9
  sleep 5;  printf 'LOGOUT\r'            >&9
  sleep 4;  exec 9>&-; wait "$TP" 2>/dev/null
  h=$(grep -c "SUMEX-AIM" "$out"); k=$(grep -c "KILLED JOB" "$out")
  if [ "$h" -ge 1 ] && [ "$k" -ge 1 ]; then echo "SESSION $n: PASS (herald+login+logout)"; pass=$((pass+1));
  else echo "SESSION $n: FAIL (herald=$h killed=$k) -- see below"; cat -v "$out" | sed 's/^/    /' | tail -6; fi
  sleep 6   # brief gap; NETLIT-1e re-listens in ~0s
done
echo "==== RESULT: $pass/$N full @L 69 logins ===="
[ "$pass" -eq "$N" ]
