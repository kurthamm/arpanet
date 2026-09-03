; RESET TEST (throwaway, isolated copies): semantic NCP recycle via IMPDRQ.
; Run with cwd = this dir so restore's media/ auto-attach resolves to the COPIES.
; Canonical state/packs untouched. Telnet console (no segfault). No IMP debug.
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
echo === RESET TEST: deposit IMPDRQ(70224) = -1 to recycle NCP (IMPNOF->IMPRSS->IMPRSN) ===
deposit 70224 777777777777
echo === IMPDRQ set; resuming TENEX ===
go
