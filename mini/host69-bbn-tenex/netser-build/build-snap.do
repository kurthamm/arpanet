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
set console wru=034
deposit 57174 777777777777
echo === SETTLE ===
step 250000000
echo === FORCEDOWN host-ready cycle ===
deposit IMP FORCEDOWN 1
step 450000000
deposit IMP FORCEDOWN 0
step 400000000
deposit 70360 0
echo === HOST-READY DONE ===
go
