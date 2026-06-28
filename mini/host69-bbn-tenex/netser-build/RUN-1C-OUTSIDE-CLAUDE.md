# Run the NETLIT 1c build/test from your own tmux (outside Claude)

Goal: discriminate whether the deterministic `SIGTERM received, PC: 102737` that kills
`pdp10-ki` ~5s into boot is **Claude's execution sandbox** or the **host/lab itself**.

These scripts are fully repo-local — no Claude scratchpad path. They generate their own
`.do` files and use `netser-build/scripts/{console-daemon,drain}.py`. Scratch dir defaults to
`/tmp/netlit-$USER` (override with `NETLIT_SCRATCH=/path`).

## Steps (from `mini/host69-bbn-tenex/`)

```bash
# 1. assemble netser-lite-1c.fai on-box (FAIL) -> rebuilds login.dta run tape
bash netser-build/build-1c.sh
#    expect: "*** ASSEMBLED OK ***" and a run tape listing (NETLIT REL / LOADER SAV / PA1050 SAV)

# 2. launch host69 (host-ready path) + auto-load NETLIT; needs imp05/lab running
bash netser-build/launch-1c-test.sh
#    expect: "*** NETLIT IS LISTENING ON SOCKET 1 ***"

# 3. fire the client (from the mini/ dir)
cd /home/deltaprism/arpanet/mini
NCP=ncp31 ./ncp-telnet -o 69
```

Watch `mini/host69-bbn-tenex/logs/cty.log` for:
```
RFC RECEIVED / CONTACT ACCEPTED / SOCKET NUMBER SENT / DATA SOCKETS OPEN / HERALD SENT
```
**Success target:** the client prints `BBN-TENEX NETLIT TEST`.

## Interpreting the result

- **`build-1c.sh` reaches "ASSEMBLED OK" (ki survives)** → the SIGTERM was Claude's
  sandbox, not the box. Continue the 1c test here.
- **ki still dies with `SIGTERM PC 102737` outside Claude** → not Claude. Inspect
  host-level supervision: systemd, cgroup limits, a watchdog, OOM policy, or a cleanup
  cron. (`logs/build.log` shows the SIMH side; `journalctl`/`dmesg` may show the killer.)
- **build works but the client test fails** → the network path is fine; debug the 1c ICP
  socket-swap itself (the `### ` markers and `cty.log` show exactly which ICP step stalls).
  Do NOT re-debug the launcher.

## What's where
- Source: `netser-build/netser-lite-1c.fai` (RFC 123/165 + lab-`ncp.c`-validated DOICP shim)
- Build: `netser-build/build-1c.sh`  Test: `netser-build/launch-1c-test.sh`
- Helpers: `netser-build/scripts/{console-daemon,drain}.py`
- Required (present on the box, gitignored): the built emulator
  `kit-cache/rcornwell-sims/BIN/pdp10-ki` (must carry output-done fix `37744c0`),
  the snapshot `snap/host69-live.state`, and `runtime/login-build/{subsys,dta}/`.
