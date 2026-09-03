; Diagnostic: why is the already-requested recycle wedged? Examine nettch + gate vars,
; then capture a few CONI words (is 1B19 power on? is 1B22 off?) via CONI debug.
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
set debug stdout
step 40000000
echo ===GATE VARS: nettch(70225) imprdy(70203) impdrq(70224) neton(70204) imprdl(70214) imprdt(70215)===
examine 70225
examine 70203
examine 70224
examine 70204
examine 70214
examine 70215
echo ===enable CONI debug, capture a few===
set imp debug=CONI
step 30000000
set imp nodebug
echo ===DONE===
quit
