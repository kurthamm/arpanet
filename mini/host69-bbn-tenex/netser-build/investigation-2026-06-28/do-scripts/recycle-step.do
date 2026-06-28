; Option-1 scripted host69-side IMP outage via bounded `step`, then reattach.
; Exercises TENEX's OWN imp-down/up recovery (IMPSTC->IMPDRQ->NETDWN->IMPRSN), which
; clears the 25 stale RFNM conns + companion state coherently (no table surgery -> no crash).
; CTY on telnet 2323 (no segfault); SCP from this .do. cwd=copy dir (media/=copies).
restore -F /tmp/claude-1000/-home-deltaprism-arpanet/ef23d23f-4517-4df6-a113-1c4da8dc08db/scratchpad/reset-test/host69-live.state
detach dc
detach tym
detach imp
detach mta0
detach dt0
detach dt1
attach -u dc 16945 speed=2400
attach -u tym 16946
attach -u imp 21052:127.0.0.1:21051
set imp nodebug
set console telnet=2323,nomessage
echo === PHASE1: settle with IMP UP ===
step 40000000
echo === todclk at outage start ===
examine 61251
echo === DETACH IMP (host69-side 1822 outage) ===
detach imp
step 400000000
echo === todclk after outage step (confirm >=10s elapsed) ===
examine 61251
echo === REATTACH IMP to imp05 (same reciprocal 21052->21051) ===
attach -u imp 21052:127.0.0.1:21051
echo === PHASE3: run to recover (NCP should be clean) ===
go
