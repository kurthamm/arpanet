; Restore the booted TENEX snapshot AND attach the build media so we can DUMPER
; the login-server toolchain + NETSER sources onto the live disk.
;   dt0  = syslod DECtape (carries DUMPER.SAV; <SUBSYS> is empty on the snapshot)
;   mta0 = login.tap (FAIL/LINK10/PA1050/MACRO/LOADER/RUNFIL/DUMPER + NETSER.FAI/STALLM.FAI + SYSJOB)
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
echo === RESTORED (loginbuild); dt0=syslod.dta mta0=login.tap; resuming TENEX ===
deposit 57174 777777777777
echo === ENTFLG=-1 ===
go
