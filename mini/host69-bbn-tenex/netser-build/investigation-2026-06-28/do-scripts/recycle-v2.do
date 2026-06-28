; Option (c) CORRECTED: let imp come UP first (imprdy=-1), THEN FORCEDOWN so the
; tear-down path runs (IMPSTU->IMPNOF->NETDWN abandons the 25 stuck conns), then
; FORCEDOWN 0 -> IMPRSS->IMPRSN brings NCP up clean.
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
echo === SETTLE: let imp come UP naturally ===
step 250000000
echo === imprdy after settle (want -1=777777777777, UP) ===
examine 70203
echo === FORCE DOWN (imp UP -> IMPSTU->IMPNOF->NETDWN abandons conns) ===
deposit IMP FORCEDOWN 1
step 450000000
echo === gate after down hold: imprdy impdrq ===
examine 70203
examine 70224
echo === FORCE UP (clear 1B22 -> IMPRSS->IMPRSN) ===
deposit IMP FORCEDOWN 0
step 400000000
echo === imprdy after recover ===
examine 70203
echo === running ===
go
