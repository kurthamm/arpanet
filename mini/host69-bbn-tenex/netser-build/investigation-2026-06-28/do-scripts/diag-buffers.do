; (1)+(2): is it buffer starvation, and does FORCEDOWN break input-arming?
; Examine free-input-buffer state before (STATE A, no forcedown) and after (STATE B) a
; FORCEDOWN cycle; DEBUG_IRQ shows link_up (input armed) in each phase.
restore -F /home/deltaprism/arpanet/mini/host69-bbn-tenex/snap/host69-live.state
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
deposit 57174 777777777777
set imp debug=IRQ
echo === SETTLE (no forcedown) ===
step 250000000
echo === STATE A buffers: IMPNFI(70227) IMPFRI(70226) IMPINP(70331) IMINFB(70335) ===
examine 70227
examine 70226
examine 70331
examine 70335
echo === FORCEDOWN cycle ===
deposit IMP FORCEDOWN 1
step 450000000
deposit IMP FORCEDOWN 0
step 400000000
echo === STATE B buffers: IMPNFI(70227) IMPFRI(70226) IMPINP(70331) IMINFB(70335) ===
examine 70227
examine 70226
examine 70331
examine 70335
echo === DONE ===
quit
