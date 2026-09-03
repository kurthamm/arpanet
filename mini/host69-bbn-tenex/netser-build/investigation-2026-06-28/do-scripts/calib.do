; Calibration: confirm `step` returns to SCP and advances TODCLK (61251, in ms).
; CTY on telnet 2323 (no segfault); SCP reads from this .do. No imp (no imp05 contact).
restore -F /tmp/claude-1000/-home-deltaprism-arpanet/ef23d23f-4517-4df6-a113-1c4da8dc08db/scratchpad/reset-test/host69-live.state
detach dc
detach tym
detach imp
detach mta0
detach dt0
detach dt1
attach -u dc 16945 speed=2400
attach -u tym 16946
set imp nodebug
set console telnet=2323,nomessage
echo === CALIB todclk(61251) t0 ===
examine 61251
step 2000000
echo === after step 2,000,000 (t1) ===
examine 61251
step 20000000
echo === after step 20,000,000 (t2) ===
examine 61251
echo === CALIB DONE ===
quit
