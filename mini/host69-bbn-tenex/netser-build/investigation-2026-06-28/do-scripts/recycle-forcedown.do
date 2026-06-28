; Option (c): drive a clean host69-side IMP down/up via the FORCEDOWN lever (1B22).
; TENEX sees 1B22 ON -> IMPSTT down -> IMPRDT -> IMPDRQ (~20s) -> NETDWN clears the 25
; stale RFNM-waiting links; then FORCEDOWN 0 -> 1B22 off -> IMPRSS -> IMPRSN brings NCP
; up clean. Throwaway, isolated copies, telnet console (no segfault). cwd=copy dir.
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
echo === PHASE1: settle with IMP up ===
step 40000000
echo === FORCE DOWN: deposit IMP FORCEDOWN 1 (surface 1B22) ===
deposit IMP FORCEDOWN 1
examine IMP FORCEDOWN
echo === hold down ~40s todclk for IMPDRQ/NETDWN ===
step 650000000
echo === todclk after down hold ===
examine 61251
echo === FORCE UP: deposit IMP FORCEDOWN 0 (clear 1B22) ===
deposit IMP FORCEDOWN 0
echo === recover ~25s todclk (IMPRSS/IMPRSN) ===
step 400000000
echo === recovered; running ===
go
