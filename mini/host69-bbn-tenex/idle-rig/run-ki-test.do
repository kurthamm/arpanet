echo === TEST BOOT (isolated idle rig) ===
restore -F /home/deltaprism/arpanet/mini/host69-bbn-tenex/snap/host69-login.state
; SAFETY: force every disk onto the DISPOSABLE copy (never the live packs)
detach ddc0
detach ddc1
detach dpa0
detach dpa1
detach dpa2
detach dpa3
detach dpa4
detach dpa5
detach dpa6
attach ddc0 /home/deltaprism/arpanet/mini/host69-bbn-tenex/idle-rig/install/media/tenex0.ddc
attach ddc1 /home/deltaprism/arpanet/mini/host69-bbn-tenex/idle-rig/install/media/tenex1.ddc
attach dpa0 /home/deltaprism/arpanet/mini/host69-bbn-tenex/idle-rig/install/media/tenex0.rp03
attach dpa1 /home/deltaprism/arpanet/mini/host69-bbn-tenex/idle-rig/install/media/tenex1.rp03
attach dpa2 /home/deltaprism/arpanet/mini/host69-bbn-tenex/idle-rig/install/media/tenex2.rp03
attach dpa3 /home/deltaprism/arpanet/mini/host69-bbn-tenex/idle-rig/install/media/tenex3.rp03
attach dpa4 /home/deltaprism/arpanet/mini/host69-bbn-tenex/idle-rig/install/media/tenex4.rp03
attach dpa5 /home/deltaprism/arpanet/mini/host69-bbn-tenex/idle-rig/install/media/tenex5.rp03
attach dpa6 /home/deltaprism/arpanet/mini/host69-bbn-tenex/idle-rig/install/media/tenex6.rp03
; private I/O ports (no collision with the live ki's 16945/16946/2323/21052)
detach dc
detach tym
detach imp
detach dt0
detach dt1
detach mta0
attach -u dc 46945 speed=2400
attach -u tym 46946
attach -u imp 41052:127.0.0.1:41051
set imp nodebug
set console telnet=42323,nomessage
deposit 57174 777777777777
echo === SETTLE ===
step 200000000
echo === FORCEDOWN host-ready cycle ===
deposit IMP FORCEDOWN 1
step 450000000
deposit IMP FORCEDOWN 0
step 400000000
deposit 70360 0
echo === HOST-READY DONE ===
set cpu idle
go
