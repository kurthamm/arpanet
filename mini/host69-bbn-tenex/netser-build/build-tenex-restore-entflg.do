; Restore with SCP console parked on telnet 2323 (kept alive by an external
; persistent connection) so `go` can't return on console EOF.  Used to prove the
; IMP stays UP for a sustained period after the 1B22 CONI fix.
restore -F /home/deltaprism/arpanet/mini/host69-bbn-tenex/snap/host69-live.state
detach dc
detach tym
detach imp
attach -u dc 16945 speed=2400
attach -u tym 16946
attach -u imp 21052:127.0.0.1:21051
set imp nodebug
set console telnet=2323,nomessage
echo === RESTORED (park); resuming TENEX ===
deposit 57174 777777777777
echo === ENTFLG set -1 ===
go
