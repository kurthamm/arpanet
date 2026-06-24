# BBN-TENEX Host #69 — Boot "TENEX RESTARTING" Wait: Investigation (2026-06-24)

Status: **SOLVED 2026-06-24.** Root cause = a **TTY-output flow-control hang**
(`tyhngu`), NOT the drum/speed/packs/binary. The fix is to **keep the DC/TYM console
sockets drained** during boot (a connected reader, or persistent reconnecting `nc`).
With draining, `TENEX RESTARTING, WAIT...` → `TENEX IN OPERATION` cleared ~8/8 in a
row (vs ~0% for hours before). See the SOLVED note below; the investigation that
follows is retained as the trail that led there.

## SOLVED — root cause + fix (2026-06-24)

- Named it from `kit-cache/build-tenex/tenex.dis` (a full monitor disassembly +
  symbol table that was in the repo all along — every prior session wrongly believed
  no map existed). The recorded spin PCs map to `tcobq`/`ttomax`/`ttoct`/`ttoin` →
  **`tyhngu`** ("TTY hung", 130000), wrapped in the `hlockp`/`hlockr` line interlocks
  and `nopilk` PI-lock counters. The monitor blocks at startup writing console output
  to a line whose output buffer fills and never drains.
- Confirmed in `PDP10/kx10_dc.c` (~line 249): the DC line only transmits a char when
  `lp->conn` (a TCP client is connected); an undrained line stalls TENEX's output
  buffer → `tyhngu`. This explains the PTY-vs-file difference AND the intermittence
  (draining depended on whether an `nc`/client happened to be attached — the controller
  gate "captures the DC listener" so it succeeded; bare boots wedged).
- **FIX:** persistent reconnecting drainers on DC (16945) + TYM (16946) for the whole
  boot. Free in production too: a connected ARPANET/NCP visitor IS a drainer.
- Also rebuilt `BIN/pdp10-ki`: `scp.c:9317 sim_check_console(30)` → `604800` (the
  hardcoded 30s console connect-timeout was exiting the sim before a human connected).
  Console disconnect-exit avoided with `set console ...,buffered=` (txbfd) or a tmux PTY.
- The real remaining work is the **authentic user login** (SYSJOB/NCP), not the boot.
  See `docs/host69-tenex-getup-plan.md` and memory `host69-tenex-authentic-goal`.

---

Original investigation (status at the time: unresolved) follows.

## TL;DR

- **Solved:** DLUSER (cosmetic error, dirs really created), the full unattended
  install to a live TENEX EXEC, and the EXEC `CONNECT`/`SYSTAT` crash (date bug).
- **Blocker:** after `SYSLOD$G` → `CLOBBER? Y`, the monitor prints
  `TENEX RESTARTING, WAIT... NO CHECKDSK` and then **does not reach
  `TENEX IN OPERATION`**. It is **WAITING, not spinning randomly** (the TYM console
  literally shows `TENEX RESTARTING, WAIT...`). This phase swaps the swappable
  monitor in from the **drum (DDC device)**.
- It is **intermittent**: ~6 clean successes early in the session (19:31–21:10),
  then a near-100% failure streak for hours. Same files, same binary.
- **Ruled out by controlled test:** emulation speed (fast frozen-box AND slow
  nice'd both wedge), disk packs (committed / snapshot / pristine all wedge),
  the emulator binary (my fflush build AND the pre-session `pdp10-ki.orig` both
  wedge), the boot dectape (`syslod.dta` committed AND freshly-rebuilt both wedge),
  the install do-file vs bare boot (both wedge), and the IMP (`set imp disabled`
  still wedges).
- **Not yet resolved:** what makes the drum-swap wait intermittent, and why the
  failure rate jumped mid-session with all files constant.

## What is SOLVED (proven, in transcripts)

1. **DLUSER "CAN'T CREATE" is cosmetic.** Directories ARE created. Proof:
   immediately after the `? CAN'T CREATE USER SUBSYS...` message,
   `SSAVE 0 777 <SUBSYS>DUMPER.SAV` returns `[New file]` and `DIRECTORY <SUBSYS>`
   lists it. CRDIR creates+commits the dir and sets the password, then errors on a
   later step (the documented MESSAGE.TXT issue) and takes the +1 return, so DLUSER
   prints "CAN'T CREATE" wrongly. See `transcripts/bringup.txt`.
2. **Full unattended install works** (when the boot doesn't wedge): boot → mini-exec
   → GET EXEC.SAV/START → ENABLE → SSAVE EXEC.SAV → RUN DLUSER → SSAVE
   <SUBSYS>DUMPER.SAV → RUN DUMPER restore of `system.tap` (L/N/Y/0/N) → stable
   `!` EXEC with `<SUBSYS>` fully populated (CCL/MACRO/TECO/LOADER/FAIL/PA1050/
   STENEX/RUNFIL/JOBDAT/DLUSER/DUMPER), no BUGCHK loop. Proven ~6× (transcripts
   `bringup.txt`, `loginverify.txt`, `credproof2.txt`, timestamps 19:31–21:10).
3. **EXEC `CONNECT`/`SYSTAT` "ILLEG INSTRUCTION TRAP" is a date bug.** Root-caused
   to `ODCER → ITRAP` in `datime.mac` (the ODCNV date-convert JSYS error path, which
   TENEX surfaces to programs as a fake illegal-instruction PSI). Triggered by the
   installer typing "06/22/26" → TENEX read **1926** (out of ODCNV range) and/or a
   never-logged-in dir's last-login = 0. Fix: set the install date to **1972**
   (`expect "MM/DD/YY HH:MM --" send "06/22/72 ..."`). NOTE: `CONNECT` uses BARE
   directory names (`DIRNAM`+recognition), NOT `<angle brackets>` (those print `?`).
   LOGIN needs user+password+ACCOUNT (`.LOGIN`, x1cmd.mac:1473; SYSTEM uses 220100).
   A real login session was NEVER captured this session — that work remains.

## The BLOCKER: drum-swap wait at "TENEX RESTARTING"

- The monitor prints `TENEX RESTARTING, WAIT... NO CHECKDSK` and stops there. The
  CPU is `STATE=R, WCHAN=0` (pure emulated-CPU activity, NOT blocked in any host
  syscall, NO open network socket — only the DC/TYM line listeners on 16945/16946).
- This phase is `swpmon.mac` `RUNDD3` (~:756): prints the message, then `CALL CHKBT`
  (check disk bit table), then tries CHECKDSK (GTJFN fails → `NO CHECKDSK` at :795),
  then `RUNDD2` → DDMP/SYSJOB forks → eventually `TENEX IN OPERATION` (:517 TIOMSG).
  It never reaches TIOMSG. The wait is somewhere in RUNDD2 / the restart.
- **Instruction trace of the wait** (`transcripts/histdebug.txt`, captured via
  `set cpu history` after stepping 50M instrs past NO CHECKDSK): the monitor is
  cycling the **scheduler + UUO/JSYS handler** (PCs 101027–105172, plus 114xxx–130xxx
  = the UUO/exec0/startup-JSYS region per the probe-jsys-flags notes), doing
  `CONO PI`, PI-lock counters at 775452/775454, queue scans, and a table search
  (`MOVE 2,0(1) / CAME 2,117264 / ADDI 1,1 / MOVEM 1,777025`) that never matches.
  Looks like the scheduler running while job 0 waits on a startup fork/IO that never
  completes. (To name 117264/430315/etc. you need the monitor symbol map — there is
  NO `.map`/`.sym`/`.lst` in the repo; the probe hard-coded addresses from analysis
  that wasn't saved.)
- **Drum (DDC) localization.** "TENEX RESTARTING" swaps the swappable monitor in
  from the drum. `kx10_ddc.c` `ddc_svc` sets `DDC_DON|DDC_HUD` ("Drum Hung") when a
  referenced drum unit is **not attached** (:261). hardware.do attaches only
  `ddc0`(tenex0.ddc) and `ddc1`(tenex1.ddc); units 2,3 unattached. `tenex1.ddc` is
  **0 bytes**. The DDC uses `sim_fread`/`sim_fwrite` DIRECTLY (so the disk_write
  fflush change does NOT touch the drum). This is the most likely seat of the wait
  but was not proven — resetting the drum to 0 bytes did not change the outcome.

## RULED OUT (each by a controlled test)

| Hypothesis | Test | Result |
|---|---|---|
| Emulation speed/clock | nice'd slow run (≈real KI-10 speed) AND frozen full-core run | both wedge |
| Disk pack content | committed, snapshot(installed-verified), pristine packs | all wedge |
| Emulator binary | my fflush build AND `pdp10-ki.orig-20260620` | both wedge |
| Boot dectape | committed `syslod.dta` AND freshly `verify_build_tenex_media`-rebuilt | both wedge |
| Install do-file rules | bare gate boot (no post-`go 100` rules) vs full install do-file | both wedge |
| `^Z` timing / phasing | trigger `^Z` on `NO EXEC`; phase rules after boot | still wedge |
| IMP/network init | `set imp disabled` | still wedge |
| Swap drum content | reset tenex0.ddc/tenex1.ddc to 0 bytes | still wedge |
| Host load (degraded ARPANET) | froze ARPANET (load→1.2) vs resumed | both wedge |

The canonical controller gate `verify-build-tenex-syslod-boot` reached
`TENEX IN OPERATION` **twice** (looked reliable) but its **bare boot do-file also
wedged** on a direct retry — i.e. the gate's successes were the lucky draws, not a
real fix. This is the strongest evidence the failure is genuinely intermittent.

## Phase-0 method note (what was sound)

The disciplined step that worked: **differential debugging.** "It worked at 19:31,
identical files fail now" → run pristine git-committed inputs (Phase 0). Result
0/3 EXEC → it is NOT the files, it is host/runtime state. That split the problem
cleanly. The error afterward was chasing one hypothesis per failure instead of
committing; and assuming "spin" when it is a device WAIT.

## NOT YET TRIED / next leads

- **Name the wait via the monitor symbol map.** Build the monitor from the `.mac`
  sources WITH a load map/listing (or extract the DDT symbol table from
  `boot/tenex.sav`), then identify what 117264 / the search table / 777025 are and
  what condition job 0 is blocked on. This is the single highest-value next step;
  everything else was guessing without it.
- **Drum/DDC device proof.** Enable `sim_debug` on the `ddc` device during a wedged
  boot and watch for `Drum Hung`/`Exceed Capacity`, or attach all 4 ddc units, or
  pre-size the drum files. Confirm whether the restart is blocked on a drum I/O.
- **Why the rate jumped mid-session** with constant files: only host runtime state
  was left as a variable (a full host reboot is the crude reset, untested/unwanted).

## Artifacts (in this repo unless noted)

- Proof of working install: `mini/host69-bbn-tenex/transcripts/bringup.txt`,
  `loginverify.txt`, `credproof2.txt`.
- Wait diagnostics: `transcripts/histdebug.txt` (instruction history of the wait),
  `transcripts/build-tenex-syslod-tym.txt` (TYM showing "TENEX RESTARTING, WAIT"),
  `transcripts/phase0-results.txt` (the files-vs-environment split).
- Working install driver (when boot doesn't wedge): `runtime/build-tenex-loginbaked.do`
  (1972 date, install + LOGOUT/LOGIN OPERATOR baked). Boot-only canonical:
  `runtime/build-tenex-syslod.do`.
- Helpers: `mini/host69-bbn-tenex/run-host69.sh` (interactive run),
  `start-host69.sh`, `reset-disk.sh`, `resume-arpanet.sh` (+ `frozen-pids.txt`).
- Scratch: session scratchpad has `phase0.sh`, `fastretry.sh`, `freeze_list.txt`.
- DLUSER 1B6 patch (cosmetic, harmless): `install/subsys/dluser.sav` byte 2200
  367740→363740; backup `.orig-1B6`. (Note: `prepare_build_tenex` reverts it.)
