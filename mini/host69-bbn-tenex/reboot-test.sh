#!/usr/bin/env bash
# One-shot: reboot installed host69 (fast), drain console, fresh IMP handshake,
# watch for NCP channel assignment. Self-reports to logs/reboot-test.out.
# Kills ONLY host69's ki + imp69 (never the live lab IMPs).
H=/home/deltaprism/arpanet/mini/host69-bbn-tenex
M=/home/deltaprism/arpanet/mini
SCRATCH=/tmp/claude-1000/-home-deltaprism-arpanet/7f668ce4-ad2e-40e9-9bc0-8e11c8f7b08f/scratchpad
exec > "$H/logs/reboot-test.out" 2>&1

echo "[reboot] cleanup"
pkill -9 -x pdp10-ki
for p in $(pgrep -x h316ov); do grep -qa imp69-hi2only /proc/$p/cmdline 2>/dev/null && kill -9 $p; done
pkill -9 -f pyconsole.py
sleep 2
: > "$H/logs/host69-installed.log"; : > "$H/logs/console2323-py.out"

echo "[reboot] start IMP FIRST (live peer before host69 device-init probes it)"
cd "$M"; : > "$H/logs/imp69-test.log"
"$M/h316ov" "$M/imp69-hi2only.simh" > "$H/logs/imp69-test.log" 2>&1 < /dev/null &
echo "[reboot] imp69 pid $!"
sleep 2

echo "[reboot] launch ki + drainers"
cd "$H/kit-cache/build-tenex/install" || exit 1
( for i in $(seq 1 60); do ss -ltn 2>/dev/null | grep -q ':2323' && break; sleep 1; done
  while pgrep -x pdp10-ki >/dev/null; do timeout 900 nc 127.0.0.1 16945 </dev/null >/dev/null 2>&1; sleep 0.3; done &
  while pgrep -x pdp10-ki >/dev/null; do timeout 900 nc 127.0.0.1 16946 </dev/null >/dev/null 2>&1; sleep 0.3; done & ) &
"$H/kit-cache/rcornwell-sims/BIN/pdp10-ki" "$H/runtime/build-tenex-bootinstalled-ncp.do" > "$H/logs/host69-installed.log" 2>&1 < /dev/null &
KIPID=$!
echo "[reboot] ki pid $KIPID"

echo "[reboot] start pyconsole (release go 100)"
python3 "$SCRATCH/pyconsole.py" >/dev/null 2>&1 &

echo "[reboot] wait for boot (CONI activity)"
for i in $(seq 1 90); do grep -qa TENEXCONI "$H/logs/host69-installed.log" && break; kill -0 $KIPID 2>/dev/null || { echo "[reboot] KI DIED during boot"; exit 1; }; sleep 2; done
echo "[reboot] CONI=$(grep -ca TENEXCONI "$H/logs/host69-installed.log") after boot (IMP was up first)"

echo "[reboot] watch for RDY / channel assign"
for i in $(seq 1 50); do
  cono=$(grep -ca TENEXCONO "$H/logs/host69-installed.log")
  rdy=$(grep -a TENEXCONI "$H/logs/host69-installed.log" | tail -1 | grep -o 'RDY=[01]')
  poll=$(grep -ca 'ncp poll' "$H/logs/host69-installed.log")
  rx=$(grep -ca 'packet received' "$H/logs/host69-installed.log")
  alive=$(kill -0 $KIPID 2>/dev/null && echo 1 || echo 0)
  echo "[w] i=$i cono=$cono $rdy poll=$poll host69rx=$rx kialive=$alive"
  [ "$cono" -gt 0 ] && { echo "[reboot] *** RESULT: TENEXCONO=$cono CHANNELS ASSIGNED ***"; break; }
  [ "$alive" = 0 ] && { echo "[reboot] *** RESULT: KI DIED ***"; break; }
  sleep 3
done
echo "[reboot] last ncp-poll lines:"; grep -a 'ncp poll' "$H/logs/host69-installed.log" | tail -3
echo "[reboot] latest CONI: $(grep -a TENEXCONI "$H/logs/host69-installed.log" | tail -1)"
echo "[reboot] DONE"
