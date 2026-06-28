; FAITHFUL inspect harness: byte-for-byte the loginbuild runtime EXCEPT the console
; stays on stdio (the tmux pane) so we keep sim> access for READ-ONLY inspection.
; The ONLY intended delta from build-tenex-restore-loginbuild.do is:
;     set console telnet=2323,nomessage   ->   set console notelnet
; Everything else (media attaches, imp attach, imp nodebug, deposit) matches loginbuild,
; so the restored snapshot resumes with the same media its saved state expects.
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
set console notelnet
echo === RESTORED (faithful-inspect); media attached as loginbuild; console on stdio/pane ===
deposit 57174 777777777777
echo === ENTFLG=-1 ===
go
