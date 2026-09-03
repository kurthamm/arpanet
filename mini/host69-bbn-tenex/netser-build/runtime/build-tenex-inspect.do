; Read-only host69 inspection: restore the booted snapshot, attach the IMP to imp05,
; but keep the console on STDIO (the tmux pane) so we can break to sim> and examine the
; IMP device / network state. NOT a public run -- diagnostic only.
restore -F /home/deltaprism/arpanet/mini/host69-bbn-tenex/snap/host69-live.state
detach dc
detach tym
detach imp
detach dt0
detach dt1
detach mta0
set console notelnet
attach -u dc 16945 speed=2400
attach -u tym 16946
attach -u imp 21052:127.0.0.1:21051
set imp nodebug
deposit 57174 777777777777
echo === HOST69 INSPECT (console on stdio/pane); resuming TENEX ===
go
