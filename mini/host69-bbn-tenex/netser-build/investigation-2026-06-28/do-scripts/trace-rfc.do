; Trace incoming RFC at host69's IMP: production restore + host-ready re-assert + NETLIT,
; with DEBUG_IRQ (recv-poll trace) enabled just before resume. Shows for each received
; 1822 msg: nw (1=host-ready NOP, >1=message body i.e. an RFC), buf0, and imp_link_up
; (did the NCP arm input to take it). => proves whether the @L 69 RFC reaches host69.
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
attach dt0  /home/deltaprism/arpanet/mini/host69-bbn-tenex/runtime/login-build/scratch.dta
attach -r dt1  /home/deltaprism/arpanet/mini/host69-bbn-tenex/runtime/login-build/login.dta
attach -r mta0 /home/deltaprism/arpanet/mini/host69-bbn-tenex/runtime/login-build/login.tap
set imp nodebug
set console telnet=2323,nomessage
set debug stdout
deposit 57174 777777777777
echo === SETTLE: imp up ===
step 250000000
echo === FORCEDOWN cycle: re-assert host-ready ===
deposit IMP FORCEDOWN 1
step 450000000
deposit IMP FORCEDOWN 0
step 400000000
echo === enable DEBUG_IRQ recv trace + CONO (arm/re-arm) + CONI (NCP-dispatch probe) ===
set imp debug=IRQ
set imp debug=CONO
set imp debug=CONI
echo === clear IMPFLS (70360): FORCEDOWN re-ran IMPRSS which set flush-count=-2, ===
echo === which would flush the first 2 body msgs (incl the @L 69 RFC). ===
deposit 70360 0
go
