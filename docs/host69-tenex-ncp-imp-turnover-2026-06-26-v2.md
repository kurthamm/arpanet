# Host #69 BBN-TENEX — SOLVED: live on the ARPANET (turnover 2026-06-26 v2)

**Branch:** `host69-tenex-ncp-imp`. This SUPERSEDES the v1 turnover and the older
handoff's CHKBT/SYSJOB/CONI framing. Memory: `host69-tenex-saverestore-breakthrough.md`.

## TL;DR — what was wrong, what's fixed

Every prior session was blocked because **there was never a way to reach and HOLD a
fully-booted TENEX** — so all NCP/CONI/SYSJOB findings were made on a half-booted,
wedged system. Two root facts, both now handled:

1. **Reboot-from-disk is unfinished upstream.** Lars Brinkhoff's `build-tenex` README:
   *"Rebooting with SYSGO$G doesn't work."* The CHKBT wedge IS that non-feature. So we
   **don't reboot** — we SIMH-`SAVE` a fully-booted monitor and `RESTORE` it (seconds).
2. **The IMP dropped ~20s after coming up** due to an inverted CONI ready-bit in the
   emulator (details below). **Fixed.**

**Status now: host #69 is a persistent, stable BBN-TENEX (SUMEX-AIM 1.31.82) LIVE on
the real lab ARPANET via imp05**, NCP up, IMP stays on indefinitely, interactive EXEC.
Validated: `DAYTIME` → `THURSDAY, JUNE 22, 1972`; `SYSTAT` → UP, jobs listed;
`ncp-telnet 69` reaches it (was a timeout).

## The two fixes

### A. Persistence = SIMH SAVE/RESTORE (not reboot)
- **Capture once:** `runtime/build-tenex-capture.do` + scratchpad `run-capture.sh`.
  Full install-to-live (the only path that boots), then `save snap/host69-live.state`
  at the live `!` EXEC. Per-send `sleep 1` removes the GET/SSAVE EXEC.SAV keystroke
  race. (Canonical de-flake is SIMH `send delay=1M`, used by build-tenex/install.do.)
- **Start forever:** `runtime/build-tenex-restore-park.do` + scratchpad `run-final.sh`.
  `restore -F` the state, re-bind socket devices (dc 16945 / tym 16946 / imp UDP), park
  SCP console on telnet 2323, `go`. Comes up in seconds, no SYSLOD/CHKBT.
- `restore -F` is REQUIRED (TENEX writes the rp03 packs as it runs → disk "newer than
  the save" → SIMH aborts without -F). TODO for full reproducibility: snapshot
  `install/media/tenex*.rp03` atomically with the `.state`.

### B. IMP stays up = CONI 1B22 bit-sense fix  (kx10_imp.c, in the patch)
- Symptom: `***** NETWORK ON, IMP ON` then exactly ~20s later `IMP OFF`.
- Diagnosis (data, not theory): CONI stayed `220120` (RDY=1) the whole time, but
  TENEX's `IMPRDY` gate flipped -1→positive ("going down"). In impdv.mac, `IMPRSS`
  (4212) only proceeds when ready line **1B22 (0020000) is OFF**, and `IMPSTT` (4073)
  marks the imp DOWN when **1B22 is ON** (→ IMPRDT → IMPDRQ ~10s+ later = the 20s drop).
  So TENEX wants 1B22 CLEAR during normal up-operation.
- The lab patch wrongly raised 1B22 on `host_ready`. **Fix:** in the CONI TYPE_BBN+NCP
  handler (~kx10_imp.c:1085) REMOVE `if (host_ready) *data |= 0020000;` so 1B22 stays
  clear. Rebuild: `cd kit-cache/rcornwell-sims && make pdp10-ki` (~3min). CONI now reads
  `200120`; IMP stays on indefinitely (validated on test IMP and real imp05).
- Captured in `patches/rcornwell-ncp-imp.patch` (regenerated `git diff HEAD`).

## Console/stability gotchas
- Sim EXITS on console EOF (`go` returns). Keepalive = park SCP console on telnet 2323
  AND hold a PERSISTENT connection to it. Use `scratchpad/console-daemon.py` (dedicated
  reader thread + FIFO control) — it is solid; `drain.py` on 2323 is flaky (reconnects
  on telnet negotiation and drops `go`). `screen` alone was also flaky here.
- Drive the live EXEC: `printf 'SYSTAT\r' > scratchpad/cty.fifo`; output → `logs/cty.log`.

## What's NOT possible without more work (honest)
- **Fresh login / network login needs NETSER, which build-tenex never builds.** Upstream
  `install.do` has `sources.do`/`build.do` COMMENTED OUT, so `<SUBSYS>` is empty and
  `<SYSTEM>` has only EXEC.SAV — no NETSER/SYSJOB/LOGIN. So:
  - `ncp-telnet 69` → "Open refused" (NCP reachable, but no network login server).
  - Logging the console operator out → the line bells (no logger to spawn a login EXEC).
- A login EXEC DOES exist on **TTY 111** (`SYSTAT` shows "JOB 3 NOT LOGGED IN EXEC"),
  but mapping/reaching its physical line (DC 16945 / TYM 16946) was flaky in testing
  (TYM raw-telnet gives nothing; TYM is a TYMNET line, not raw NVT).
- The reachable, authentic experience today = the **operator EXEC on the CTY** (real
  BBN-TENEX, already logged in). For the browser `@L 69`, wire it to host69's console
  (port 2323) like the ITS hosts use localhost terminal lines.

## Files (scratchpad = session 6401bbf3)
- runtime/ (gitignored): build-tenex-capture.do, build-tenex-restore-ncp.do,
  build-tenex-restore-park.do, build-tenex-restore-dbg.do
- scratchpad: run-capture.sh, run-final.sh, run-restore.sh, run-live2.sh,
  console-daemon.py, drain.py
- patches/rcornwell-ncp-imp.patch (regenerated, has the 1B22 fix)
- snap/host69-live.state (the booted snapshot; needs the matching rp03 packs)

## Next steps
1. Wire `@L 69` in the web launcher → host69 console (2323). See how `@L 134` maps.
2. Make the snapshot reproducible (snapshot rp03 packs with the .state).
3. (Big, optional) Build NETSER/SYSJOB/the subsystem to get real network/fresh login —
   this is finishing the upstream build-tenex bootstrap, a substantial TENEX-from-source
   effort.
4. Production cutover (imp05 + website) per `host69-production-cutover.md`.
