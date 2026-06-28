; CLEAN throwaway (no reset deposit) for the natural IMP-down/up recycle test (A).
; CTY on telnet 2323 (no segfault); SCP/sim> stays on stdio (the tmux pane) so WRU (^E)
; breaks to sim> for detach/attach imp. Run with cwd=this dir (media/ = copies).
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
echo === CLEAN throwaway up; CTY=2323, sim> on pane (WRU ^E) ===
go
