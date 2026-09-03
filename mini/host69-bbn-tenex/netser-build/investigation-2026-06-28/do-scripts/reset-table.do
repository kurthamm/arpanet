; RESET TEST 2 (throwaway, isolated copies): TABLE reset = "make all IMP links unused"
; (IMPRSN's link-table effect), applied surgically by deposit before go.
;   IMPLT1[0..127] := 600000  (1B18+1B19 = free entry)
;   IMPLT2[0..127] := 0       (clears RFNMC "rfnm outstanding")
;   IMPLT3[0..127] := 0       (already 0; ensure)
; This empties exactly what RFNCHK scans, so the once/min IMPBUG must stop.
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
echo === TABLE RESET: make all 128 IMP links free (IMPLT1=600000, IMPLT2=0, IMPLT3=0) ===
deposit 71030-71227 600000
deposit 71230-71427 0
deposit 71430-71627 0
echo === links reset; resuming TENEX ===
go
