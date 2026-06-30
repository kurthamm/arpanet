# TURNOVER — host69 BBN-TENEX go-live (post-reboot session start, 2026-06-30)

You are picking this up in a **fresh session after a deliberate reboot**. The reboot IS the test
(Phase 1d). Read this first, then `docs/host69-go-live-plan.md` (the plan) and
`docs/host69-ncp-login-investigation.md` §9 (gotchas) before touching anything. Project context:
`docs/journal/README.md` (the knowledge spine).

> Scratchpad test scripts live under `/tmp` and were wiped by the reboot. The persistent login test
> is `mini/host69-bbn-tenex/netser-build/scripts/login-test.sh` (use it, don't rewrite a pexpect one).

---

## State at reboot (all committed + pushed on branch `host69-tenex-ncp-imp`)
- **Login is DONE, hardened, and durably deployed.** `@L 69` → real BBN-TENEX `@` EXEC → credentialed
  DEMO login (`DEMO/DEMO/1`), via **NETLIT-1e** + **`ATPTY`** (NETSER not needed). NETLIT-1e re-listen
  is hardened (0 s, no crash; 5/5 gate). Baked into the **golden snapshot** `snap/host69-login.state`
  (gitignored, on-disk only); `arpanet-host69.service` restores it and is **`enabled`** (auto-start).
- **Phase 1a/1b/1c DONE** (commit `c709900`): imp05 hi2 wiring, boot-ordering fix (`host69ctl.sh`
  waits for imp05+hi2 before host-ready), clean-slate stray-ki sweep, per-boot marker (fixes the
  `Type=exec` stale-health-check race), `TimeoutStartSec=600`, service enabled.
- Latest commits: `c709900` (Phase 1), `c8cd9d0` (NETLIT-1e), pushed to origin.

## ★ FIRST ACTIONS — validate Phase 1d (did host69 survive the reboot?)
Run, from `mini/`:
```
systemctl is-enabled arpanet-host69.service          # expect: enabled
systemctl is-active  arpanet-host69.service          # expect: active (may still be booting ~2-4 min after reboot)
ps -eo args | grep '[p]dp10-ki.*run-h69'             # expect: exactly ONE ki
# mesh sanity (a known host) -- set NCP=, use -c1, do NOT use `timeout -s KILL` (it eats ncp-ping's
# block-buffered stdout and looks empty even on success -- see investigation §9):
NCP=ncp31 ./ncp-ping -c1 11
# host69 reachability (be patient: convergence after a cold boot takes minutes):
NCP=ncp31 ./ncp-ping -c1 69                          # expect: Reply from host 105
# the real test -- a full login:
bash host69-bbn-tenex/netser-build/scripts/login-test.sh 1
```
**PASS = host69 reachable + `login-test.sh` shows `PASS` with no manual intervention.** That closes
the Phase 1 gate. If it passes, you may proceed to Phase 2 (scenarios).

## If host69 did NOT come up (recovery, in order)
1. Check the boot: `sudo journalctl -u arpanet-host69.service -b | grep host69ctl` and
   `tail -40 mini/host69-bbn-tenex/logs/run-h69.log` (look for `=== HOST-READY DONE ===`, `BUGHLT`, or
   a port `bind error 98`). cty: `tail mini/host69-bbn-tenex/logs/cty.log` (`LISTENING` good;
   `All connections busy` is **benign** console noise, not a failure).
2. If "Host is not up" / unreachable but the ki is healthy → it's mesh routing, not host69. Be patient
   (minutes). **Do NOT restart imp05 to "nudge" it — that islands the mesh.** If the broader mesh is
   islanded (known hosts 11/16 also unreachable): `sudo mini/arpanet-recover.sh recover`, WAIT for
   convergence, then `sudo systemctl restart arpanet-host69`.
3. If the ki segfaulted on a port `bind error` → a stray `pdp10-ki` held the ports. `host69ctl.sh` now
   sweeps strays at start, but to be safe: `pkill -9 -x pdp10-ki` + console-daemon/drain.py, wait for
   ports `2323/16945/16946/21052` to clear, `systemctl reset-failed arpanet-host69`, then start.
4. Rollback option: the prior 1d-NETLIT golden snapshot is preserved as
   `snap/host69-login.state.1d-bak` (the live one is the hardened 1e).

## How to test logins (the ONLY method that works)
`netser-build/scripts/login-test.sh [N]`. It drives `ncp-telnet -o 69` with stdin from a **held-open
FIFO** (raw fd), NOT a pty/pexpect — under a pty the herald deterministically stalls at ~28 bytes and
the session dies. `-o` = old telnet (socket 1). Hold the connection through a clean `LOGOUT`.

## What's next — the plan
`docs/host69-go-live-plan.md` is authoritative. After Phase 1d passes:
- **Phase 2 — 1972 booklet scenarios on #69.** The ICCC '72 booklet (`arpa/scenarios.pdf`, NIC 11863)
  has **four BBN-TENEX scenarios**: **#3 BBN Tenex** (EXEC tour + TECO + F40/SNDMSG/TELNET — feasible
  now for the built-in/TECO parts; F40/SNDMSG/TELNET have source in the kit but aren't built), **#18
  DOCTOR**, **#11 LIFE**, **#15 Chess** (the latter three need their period programs sourced/built —
  not in our kit). Restoring **#18 DOCTOR to #69** retires the current "18A on MIT-AI #134" fake.
  Scenario page: `arpa/2026-scenarios.html` (numbering convention: original # = authentic, `NNA` =
  adaptation). Login string for the page is `DEMO/DEMO/1` (booklet used `iccc/iccc/11514`).
- **Phase 3 — website wiring**; **Phase 4 — deploy** (outward-facing; confirm before publishing).

## Hard-won gotchas (full list: investigation §9; don't relearn these)
- Don't reboot TENEX — SAVE/RESTORE. Don't rebuild NETSER — `ATPTY` is the login key.
- Golden snapshot, not a console "séance." When building a snapshot, idle at LISTENING before the
  `C-\` break (a bad capture-point PC → `BUGHLT` on restore). `build-snap-launch.sh` doesn't wait for
  ports — clear TIME_WAIT first or the ki segfaults.
- Mesh: after any host69/imp05 change, WAIT for convergence; never restart imp05 to nudge.
- Always one `pdp10-ki` (host69-only emulator); kill strays.

## Repo / where things live
- Service: `mini/host69ctl.sh`, `mini/arpanet-host69.service` (+ live copy in `/etc/systemd/system/`).
- Emulator: `mini/host69-bbn-tenex/kit-cache/rcornwell-sims/BIN/pdp10-ki`; fixes in
  `netser-build/emulator-fork/`. NETLIT source: `netser-build/netser-lite-1e.fai`; run tape
  `runtime/login-build/login.dta` (gitignored). Snapshots in `snap/` (gitignored, on-disk only).
- Memories: `host69-real-login-gate`, `host69-production-cutover`, `host69-go-live-plan`,
  `host69-tenex-saverestore-breakthrough`, `kurt-*` (working-style).
