# NETSER-lite (NETLIT) — Status & Handoff

**Date:** 2026-06-27  **Branch:** `host69-tenex-ncp-imp`
**Goal:** authentic 1972 experience — a visitor types `@L 69` over the simulated ARPANET,
reaches host69 (BBN-TENEX / SUMEX-AIM 1.31.82), gets a herald, logs in. The missing piece
is a userland program that listens on the ARPANET LOGIN socket (socket 1). Historically that
is **NETSER**; building the full NETSER is blocked by a FAIL/STALLM assembler bootstrap that
no reachable toolchain can satisfy (see `host69-netser-build-attempt` memory + RESEARCH-FINDINGS.md).

**The pivot (Kurt's call):** instead of rebuilding historical NETSER, build **NETSER-lite
(NETLIT)** — a minimal NCP listener in *primitive* FAIL (no STALLM, no macros, no FAIL-v11
features) that just listens on socket 1, accepts the connection, prints a herald, closes.
"Prove the NCP mechanics with a tiny listener before recreating the whole historical beast."

---

## ★ WHERE WE ARE (milestone 1a program: WORKING)

**NETLIT is built from source and RUNS, listening on ARPANET socket 1.** Console output:
```
START
NETLIT OPENING LISTEN SOCKET 1
GTJFN OK
OPENF OK LISTENING
STS=12926844928 HOST=511 SKT=-2     (GDSTS observe loop, every ~1s)
```
So `GTJFN "NET:1#."` and `OPENF` (listen) both succeed and the program is in its observe loop.
Native TENEX JSYS code runs fine even though it was loaded by LOADER (a TOPS-10 program under
PA1050) — PA1050 only intercepts `CALLI`, not `JSYS (104)`.

**Blocked on:** the end-to-end `@L 69` test. Right now host69 is NOT NCP-reachable
(`ncp-ping 69` and *all* lab hosts time out; no host69↔imp05 socket). This is **lab plumbing
fallout** from when the lab was torn down for the (abandoned) TOPS-20 detour; `arpanet-noc`
restart didn't fully restore the host-connection ports. NOT a NETLIT problem. See "Blocker".

---

## ★ THE THREE WALLS WE CRACKED (hard-won; don't relearn these)

1. **Primitive FAIL works.** A hand-written FAIL source using only `OPDEF`, `__` defines, plain
   PDP-10 instructions, and labeled `ASCIZ`/`BYTE` data assembles cleanly. (The STALLM/FAIL-v11
   bootstrap wall only applies to the *historical* NETSER source, not to code we write fresh.)

2. **FAIL requires CRLF source line-endings.** LF-only source (what a unix file + `tendmp`
   produce) makes FAIL *count* lines but never recognize `END` →
   `FATAL END OF FILE & NO END STMT` (even a 3-line file; proven: MINTST/LF fails, MINCR/CRLF
   gives `PROGRAM BREAK`). **Fix:** `sed 's/$/\r/' x.fai > xcr.fai` before `tendmp`.

3. **`dskasn` BUGHLT 140046 = incremental DSK file GROWTH.** Fixed-size `COPY DTAx:F DSK:F`
   is FINE. But any *growing* DSK write BUGHLTs the monitor: FAIL `.REL` output to DSK,
   `COPY TTY: DSK:`, LOADER `.SAV` output to DSK. **Fix (route A):** keep assembly I/O OFF
   DSK — source from a DECtape, output the `.REL` to a *writable* DECtape; only the
   `FAIL.SAV`/`PA1050.SAV`/`LOADER.SAV` toolchain lives on DSK (read-only use). Also note:
   only **one** FAIL/LOADER invocation per restart (a 2nd one BUGHLTs — PA1050 DSK scratch
   accumulates).

Plus the run mechanics:
- **LOADER load + EXEC START.** `LOADER` → `*DTA1:NETLIT` loads the REL (returns to `*`, no
  unresolved globals). `$G` (altmode-G) just *exits* the loader with the image loaded
  ("EXIT."). Then at the EXEC `!` prompt, **`START`** runs the loaded image. (Do NOT expect
  `$G` to start it.)
- **Preserve artifacts with `kill -TERM`, never `-9`.** SIMH buffers the DECtape in memory and
  only flushes to the host file on clean shutdown/detach. SIGTERM flushes; SIGKILL loses it.
  Then `tendmp -x scratch.dta` to extract host-side.

---

## ★ THE WORKING BUILD → LOAD → RUN LOOP (reproducible)

All paths relative to `mini/host69-bbn-tenex/`. Helper scripts in `netser-build/scripts/`
(copies of the live session scripts; the live ones run from the scratchpad).

**Tapes / devices (set by `runtime/build-tenex-restore-loginbuild.do`, copy in `netser-build/runtime/`):**
- `dt0` = `runtime/login-build/scratch.dta` — blank **WRITABLE** DECtape (DTA0:, for output).
  Make a fresh one: `tendmp -T -L TENEX -b boot/dtboot.bin -c scratch.dta dummy.txt`
  (needs ≥1 file e.g. a `dummy.txt` so the directory is valid). Only DTA0:/DTA1: exist — no DTA2:.
- `dt1` = `runtime/login-build/login.dta` — read-only toolchain+input tape (DTA1:).
- console = telnet **2323**; the `.do` also `deposit 57174 777777777777` (ENTFLG=-1).

**Build (assemble NETLIT.REL):**
1. `cp netser-build/netser-lite.fai runtime/login-build/dta/x.fai`
   `sed 's/$/\r/' runtime/login-build/dta/x.fai > runtime/login-build/dta/xcr.fai`  ← CRLF!
2. From `kit-cache/build-tenex/install/`: `tools/tendmp -T -L TENEX -b boot/dtboot.bin -c
   .../login.dta  .../dta/xcr.fai  .../dta/pa1050.sav  .../subsys/fail.sav`
   (flat tape, 6-char names → DTA1:XCR.FAI etc.)
3. `bash netser-build/scripts/run-loginbuild.sh`  (restores host69 + media + 2323 console daemon)
4. On TENEX `!` (drive via the cty FIFO; see copyfile.sh): `MOUNT DTA0:` ; `MOUNT DTA1:` ;
   `COPY DTA1:FAIL.SAV <SUBSYS>FAIL.SAV` ; `COPY DTA1:PA1050.SAV <SUBSYS>PA1050.SAV`
5. **ONE** FAIL run: `FAIL` then `DTA0:XCR_DTA1:XCR.FAI`. Success = `PROGRAM BREAK nnnnnn'`.
   Do NOT run DIRECTORY or anything else after (DSK ops BUGHLT).
6. Preserve: `kill -TERM` the `pdp10-ki` pid → flushes scratch.dta; `tendmp -x scratch.dta`.

**Run (load + start NETLIT):**
1. Build a run tape: `tendmp ... login.dta  netlit.rel  loader.sav  pa1050.sav`
   (netlit.rel → DTA1:NETLIT.REL).
2. `run-loginbuild.sh` ; on `!`: `MOUNT DTA1:` ; `COPY DTA1:LOADER.SAV <SUBSYS>` ;
   `COPY DTA1:PA1050.SAV <SUBSYS>`.
3. `LOADER` → `*DTA1:NETLIT` (load) → `$G` (exit loader, image loaded) → at `!` type `START`.
4. NETLIT prints its banner + GDSTS loop on the 2323 console.

---

## ★ LAB TOPOLOGY (learned 2026-06-27)

- host69 ↔ its IMP = **imp05**, interface **hi2**.
  `imp05.local.simh`: `attach -u hi2 21051:127.0.0.1:21052`  (imp05 listens 21051, dials 21052).
  host69 restore: `attach imp 21052:127.0.0.1:21051`  (host69 listens 21052, dials 21051).
  → link is imp05:21051 ↔ host69:21052.
- The lab IMPs (imp01..imp05+) are supervised by **`arpanet-noc.service`** (systemd). ~37
  `h316ov` processes when fully up.
- NCP client tools live in `mini/`: `ncp-ping`, `ncp-telnet`, `ncp-finger`, invoked
  `NCP=ncp31 ./ncp-ping -c1 <hostnum>`. `ncp31` is a config selector, not a daemon.
- Host management: `mini/hostctl.sh`; health: `mini/arpanet-health.sh`.
- `@L 69` = ICP to host 69 socket 1 (the telnet/login contact socket) = NETLIT's listen socket.

---

## ★ CURRENT BLOCKER (next thing to fix) — lab NCP connectivity

`ncp-ping 69` AND ping to hosts 1/2/3/40 all TIME OUT; `ss` shows **no listener on the 2105x
host-ports** and **no host69↔imp05 (21051/21052) socket**, despite 37 IMPs running and
`arpanet-noc` active. So the host-connection layer is down lab-wide (teardown fallout).
**This must be restored before the `@L 69` test is meaningful** — the earlier `ncp-telnet 69`
"hang instead of Open refused" was just unreachability, NOT a received RFC.

Investigation TODO (research the repo, don't guess):
- Why isn't imp05 `hi2` listening on 21051? (running imp05 = pid using `imp05.local.simh`.)
  Is the running imp05 the one `arpanet-noc` supervises, or a stray from `run-loginbuild.sh`?
- Does `hostctl.sh` bring host lines up? Read it. Does `arpanet-health.sh` show the gap?
- Confirm `ncp31` config path to host 69 (memory: route `05:1:69` is *commented*; the physical
  hi2 link carried it before — so the hi2 link being down is the likely root).

---

## ★ AFTER CONNECTIVITY: remaining NETLIT milestones

**1a finish (observe):** with the path up, run NETLIT, connect `@L 69`, watch GDSTS — expect
the state to leave idle and reach **RFCR (4)** (states: PNDG=2 RFCR=4 OPND=7 LSNG=3). If it
never reaches RFCR, suspect (Kurt's traps) **byte size** (OPENF mode `400000,,100000` vs the
RFC's byte size) or the local socket spec, NOT the JSYS sequence.

**1b (accept + herald):** inline only NETSER `DOICP`'s skeleton (no SGNON/CRPROC/PTY/LOGIN):
- `MTOPR fn 20` on the listen JFN = **accept** (RFCR→OPND). (fn 24 in MKICPF is listen-config.)
- Then the ICP: allocate local socket pair, `GTJFN` send+recv data sockets
  (`NET:<lcl>.<fhost>-<fskt+2>;T`), `BOUT` the new socket number over the ICP link, `CLOSF` it,
  `OPENF` send (`103000,,100000`) + recv. Then `SOUT` herald `BBN-TENEX NETSER-LITE TEST\r\n`,
  read with `BIN`, close both. (Source refs: netser.fai MKICPF ~516, DOICP ~804, CHECK ~560.)

**TENEX JSYS numbers** (from `build-tenex/mon/stenex.mac` `DEFJS name,num`; JSYS = `104B8+num`):
GTJFN=20 GNJFN=17 RLJFN=23 OPENF=21 CLOSF=22 SOUT=53 NOUT=224 PSOUT=76 PBOUT=74 MTOPR=77
GDSTS=145 DISMS=167 HALTF=170 SYSGT=16 CVSKT=? GETAB=10 BIN/BOUT=? SIR=125 EIR=126 AIC=131 ATI=137.

---

## ★ ARTIFACTS INVENTORY (`netser-build/`)

- `netser-lite.fai` — master source (LF), milestone 1a (listen + GDSTS observe).
- `NETCRL.FAI` — the CRLF source FAIL actually assembled.
- `netlit.rel` — **the assembled object** (3855 B, `PROGRAM BREAK 000206'`).
- `artifacts/` — redundant backups: `scratch-NETCRL-REL.dta` (full tape w/ NETCRL.REL),
  `netlit.rel`, `NETCRL.FAI`, `netser-lite.fai`, `SHA256SUMS.txt`, `README-NETLIT.txt`.
- `scripts/` — `run-loginbuild.sh`, `console-daemon.py`, `copyfile.sh`, `drain.py`, `dskscan.py`.
- `runtime/build-tenex-restore-loginbuild.do` — restore driver (dt0=writable scratch, dt1=login).
- `README.md`, `RESEARCH-FINDINGS.md` — prior research (FAIL bootstrap, etc.).
