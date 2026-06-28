; Diagnostic: does FORCEDOWN(1B22) drive TENEX's down-detection chain?
; Watch imprdt(70215) imprdl(70214) impdrq(70224) imprdy(70203) before/during force-down.
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
show imp
step 40000000
echo ===BEFORE FORCEDOWN (imprdt imprdl impdrq imprdy)===
examine 70215
examine 70214
examine 70224
examine 70203
deposit IMP FORCEDOWN 1
examine IMP FORCEDOWN
step 120000000
echo ===AFTER ~7s 1B22 ON===
examine 70215
examine 70214
examine 70224
step 300000000
echo ===AFTER ~25s 1B22 ON===
examine 70215
examine 70224
examine 70203
echo ===DONE===
quit
