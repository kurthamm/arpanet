# Plan: Get BBN-TENEX Host #69 Up and Running

Status: active. Owner: Kurt. Updated 2026-06-22. Private lab only — `@L 69`
stays disabled until every gate passes on an unattended run.

## PROGRESS LOG

- 2026-06-24 (later): **BOOT WEDGE SOLVED + goal reframed to the authentic user
  experience.** (1) The "TENEX RESTARTING" wedge was a **TTY-output flow-control hang
  (`tyhngu`)**, not the drum — fixed by **draining the DC/TYM console sockets** during
  boot (cleared ~8/8 vs ~0% before). Named via `kit-cache/build-tenex/tenex.dis`;
  confirmed in `kx10_dc.c`. Full writeup: `docs/host69-tenex-boot-wait-findings.md`.
  (2) Rebuilt `BIN/pdp10-ki` — `scp.c` `sim_check_console(30)`→`604800` (the hardcoded
  30s console connect-timeout was killing the sim before a human could connect). (3)
  Confirmed: install keystroke automation (SIMH expect/send) RACES at full speed; run
  slow. DUMPER restore of `system.tap` is intermittently fatal (IO DATA ERROR / BUGHLT)
  and is NOT needed for login. (4) **GOAL REFRAMED (Kurt):** the deliverable is the
  historically-accurate 1972 USER experience — `@L 69` → `BBN-TENEX` herald → `@login`
  → scenario — NOT the operator install (which is invisible plumbing). **Blocker to
  that = `NO SYSJOB`:** TENEX boots without SYSJOB, so it never opens a login line or
  runs the logger; only the operator `!` console is alive. We HAVE the pieces:
  `kit-cache/imsss/files/system/sysjob.sav.3` + `autojobs.run.1`, `logger.mac`, and the
  disabled `mini/arpanet` route `05:1:69:21051:21052:BBN-TENEX`. NEXT PHASE: install
  SYSJOB+AUTOJOBS → TENEX serves logins → wire IMP to ARPANET IMP 05 → enable `@L 69`.
  See memory `host69-tenex-authentic-goal`.

- 2026-06-24: **Boot blocker re-localized — intermittent "TENEX RESTARTING" drum-swap
  WAIT, not a spin. Full writeup: `docs/host69-tenex-boot-wait-findings.md`.** After
  CLOBBER, monitor prints `TENEX RESTARTING, WAIT... NO CHECKDSK` and never reaches
  `TENEX IN OPERATION`. It is WAITING (TYM console shows "WAIT..."; CPU WCHAN=0, no
  host syscall/socket) in the swappable-monitor swap-in from the DRUM (DDC). ~6 clean
  installs early (19:31-21:10) then near-100% failure for hours, same files. Ruled
  out by controlled test: speed (slow nice'd AND frozen both wedge), packs, binary
  (fflush AND orig), dectape (committed AND rebuilt), do-file-vs-bare-boot, ^Z timing,
  IMP-disabled, drum reset. Canonical gate `verify-build-tenex-syslod-boot` hit IN
  OPERATION 2x but its bare boot also wedged on retry → intermittent, successes are
  luck. ALSO this session: CONNECT/SYSTAT "ILLEG INSTRUCTION TRAP" root-caused to the
  ODCNV date converter on a 1926 date → fixed by installing with a 1972 date.
  Real LOGIN never captured. NEXT: get the monitor symbol map to name the wait
  condition; sim_debug the ddc device. Don't re-chase the ruled-out variables.

- 2026-06-23: **DLUSER blocker DISSOLVED — "CAN'T CREATE" is cosmetic; dirs ARE
  created. Full unattended bring-up to a stable live TENEX now reproducible.**
  - Instrumented the emulator's CRDIR JSYS (240) at dispatch level (`kx10_cpu.c`
    `[CRDIR]` trace). Two findings overturn the old theory: (1) running DLUSER from
    the MINI-EXEC (master SYSTEM job, WHEEL active) ALSO fails identically →
    privilege-gate hypothesis DISPROVEN; (2) after the "CAN'T CREATE USER SUBSYS"
    error, `SSAVE 0 777 <SUBSYS>DUMPER.SAV` SUCCEEDS `[New file]` and `DIRECTORY
    <SUBSYS>` lists it → **the directory really exists and is writable.**
  - Root cause (jsys.mac ~1521-1824): `DIRLUU`→`CRDIRA`→`MAKNFD` creates & COMMITS
    the dir and sets the password (CRDIR3), then errors LATER on the documented
    MESSAGE.TXT step (CRDIR4/CRDIR5) and takes the +1 return. DLUSER prints "CAN'T
    CREATE" but the user dir + password are fine. The `1B6` auto-assign patch
    (dluser.sav byte 2200, 367740→363740) was applied+verified but is IRRELEVANT
    (same PC/instr-count, dirs created either way) — left in, harmless.
  - **Working driver `runtime/build-tenex-bringup.do`:** boot→clobber Y→mini-exec→
    GET EXEC.SAV+START→ENABLE→SSAVE EXEC.SAV→RUN DLUSER (dirs created)→SSAVE
    <SUBSYS>DUMPER.SAV→RUN DUMPER restore system.tap (L/N/Y/0/N)→stable live `!`,
    `<SUBSYS>` fully populated (CCL/MACRO/TECO/LOADER/FAIL/PA1050/STENEX/RUNFIL/
    JOBDAT/DLUSER/DUMPER), NO BUGCHK loop. Installed-disk snapshots saved under
    `install/media/installed-verified-*` and `installed-snapshot-*`.
  - **Reboot still broken even with the fflush fix:** CLOBBER=N boot
    (`build-tenex-bootinstalled.do`) reaches `TENEX RESTARTING, WAIT...` then SPINS
    (CPU busy, zero disk I/O). Operational model stays: install-to-live in one pass,
    keep the sim alive.
  - **Login plumbing:** the DC terminal line (port 16945) connects at SIMH level but
    TENEX does NOT service it as a login line (no echo; "NO SYSJOB"; DTR/carrier/
    scanner config). The lab's real visitor path is ARPANET TELNET over NCP
    (`mini/dotelnet.sh`→`ncp-telnet ... 69`) into the IMP (`set imp enabled bbn`),
    NOT the DC line. Credential check being done on the CTY via wheel-disabled
    `CONNECT OPERATOR <pw>` (`build-tenex-credproof2.do`): CONNECT uses BARE dir
    names (DIRNAM+recognition), NOT `<...>` brackets (that prints `?`). users.txt:
    OPERATOR/OPERATOR (full privs #3=777777777777), PMFDIR0 & SUBSYS blank pw.
    LOGIN needs user+pw+ACCOUNT (`.LOGIN` x1cmd.mac:1473; SYSTEM uses acct 220100).
  - REMAINING for public @L 69: attach host69 IMP to ARPANET (IMP 05, host idx 1,
    ports 21051/21052), enable the route in `mini/arpanet`, verify ncp-telnet login.

- 2026-06-22: **Experiment A SUCCEEDED — the install-automation blocker is solved.**
  Ran Lars's verbatim post-boot `expect` block on the proven boot prefix, with all
  7 disk packs pre-sized. The full install ran UNATTENDED to completion for the
  first time ever: boot → `NO EXEC` → `^Z` mini-exec → `GET DTA0:EXEC.SAV` →
  `START.` → `SUMEX-AIM Tenex 1.31.82 EXEC 1.51` banner → date → `@ENABLE` →
  `MOUNT DTA0:` → `GET`+`SSAVE 0 777 EXEC.SAV [New file]` → `RUN DLUSER.SAV` →
  `DONE.` → `GET`+`SSAVE <SUBSYS>DUMPER.SAV [New file]`. Driver:
  `runtime/build-tenex-expA.do`. Transcript: `transcripts/expA.txt`.
- NEW FRONTIER (was not anticipated in detail): DLUSER hit Lars's documented open
  bug — `? CAN'T CREATE USER PMFDIR0/SUBSYS/OPERATOR AS DIRECTORY NUMBER 2/3/4,
  CONTINUING`. Directory 1 (SYSTEM) exists and received EXEC.SAV; dirs 2-4 (the
  login accounts + `<SUBSYS>`) were NOT created. This gates multi-user login and
  likely the `<SUBSYS>DUMPER.SAV` save. **This is now the main problem to solve
  (see Phase 2 below).**
- 2026-06-22: no-clobber validation boot (`runtime/build-tenex-bootinstalled.do`,
  answers CLOBBER `N`) **SPINS** in `TENEX RESTARTING, WAIT...` — CPU pegged, both
  read+write I/O flat, 15 min, no progress. Clean reboot of the installed disk does
  not come up. Matches Lars's other documented open bug ("Rebooting with
  SYSGO$G/SYSGO1$G doesn't work"). (Caveat: my do-file did `load tenex.sav; go 100`
  right after the `N`, which may have collided with SYSLOD's own restart — a cleaner
  no-clobber boot is worth one more try, but reboot is upstream-fragile regardless.)
- **REFRAME — operational model:** do NOT rely on "install once, then fast-reboot the
  installed disk." Instead, the install pass (Experiment A) itself lands at a LIVE
  running EXEC at the `@`/`!` prompt in one go. The host should be brought up by
  running the install-to-live sequence and KEEPING the sim alive there (don't let the
  do-file EOF/exit). A disk snapshot for fast restart is a later optimization.
- Therefore the two things between here and a logged-in TENEX: (1) solve/bypass the
  DLUSER directory bug so login accounts exist (Phase 2); (2) make the install
  do-file end in a persistent live EXEC instead of exiting.
- 2026-06-22: **Experiment A+ BREAKTHROUGH — DUMPER restore of `system.tap` works.**
  Driver `runtime/build-tenex-expApulus.do`; transcript `transcripts/expAplus.txt`.
  After the install, ran `RUN DTA0:DUMPER.SAV` (identifies as `MINI-DUMPER 13 APRIL
  71`) → `L / N / Y / 0` → restore completed → `DONE.` `!DIRECTORY` shows **`<SUBSYS>`
  now exists and is fully populated**: CCL, DLUSER, DUMPER, FAIL, JOBDAT, LOADER,
  MACRO, PA1050, RUNFIL, STENEX, TECO. KEY: `<SUBSYS>` = directory 3, the exact dir
  DLUSER's `CRDIR` could NOT create — so **directory creation works via DUMPER's
  path; the disk is fine; DLUSER's `CRDIR` call (or its timing) is the specific bug.**
  Remaining issues seen: `SYSTAT` → `ILLEG INSTRUCTION TRAP IN EXEC PC 26332` +
  `CANNOT FIND ERROR MESSAGE FILE` (EXEC missing a support file / unstable); the
  `OPERATOR` login dir (4) still absent (not on `system.tap`).
- 2026-06-22: **Experiment A++ (DLUSER re-run after restore) — ordering hypothesis
  DISPROVEN.** Second DLUSER (after `<SUBSYS>`/`<SYSTEM>` populated) failed
  identically (`CAN'T CREATE USER ... DIRECTORY NUMBER 2/3/4`). So DLUSER's `CRDIR`
  is genuinely broken regardless of timing. BUT confirmed `<SYSTEM>` restore now
  carries `BUGTABLE.SUMEX-AIM` + `BUGSTRINGS.SUMEX-AIM` (the BUGCHK fix) plus
  `EXEC.SAV`, `DIRECTORY.`, `DSKBTTBL.`, `INDEX.`, `JOBPMF.`. Driver
  `runtime/build-tenex-expApp.do`; transcript `transcripts/expApp.txt`.
- 2026-06-22: **Stability wall found.** `SYSTAT` → `ILLEG INSTRUCTION TRAP IN EXEC
  PC 26332` + `CANNOT FIND ERROR MESSAGE FILE` (error-message file is NOT in the
  restored `<SYSTEM>`). Connecting to the Tymnet line (16946) → `BUGHLT AT 114527`
  loop (monitor crash). So the installed system runs but is unstable.

## Phase 3: Stability + login route (current real frontier)

Two distinct blockers remain between "installed" and "visitor logs in":

1. **No login directory.** DLUSER/`CRDIR` can't create user dirs (confirmed not a
   timing issue). LEVER: DUMPER *can* create dirs (it built `<SUBSYS>`/`<SYSTEM>`),
   so bypass DLUSER — get a real user login directory onto disk via a DUMPER
   saveset. Candidates: the IMSSS real-TENEX tapes (`kit-cache/imsss/*.tap`) may
   contain real login dirs; or build one with the host `mini-dumper` tool.
2. **EXEC/monitor instability.** `SYSTAT` illegal-instruction trap + missing
   error-message file + Tymnet `BUGHLT`. NOTE: host #69 is an ARPANET host —
   visitors arrive via the **IMP/NCP** line, NOT Tymnet — so the TYM `BUGHLT` may
   be irrelevant to the real use case. The illegal-instruction trap may be
   SYSTAT-specific or a JSYS gap; LOGIN/DIR may still work. Need to (a) locate/build
   the EXEC error-message file, (b) test LOGIN + DIR specifically (not SYSTAT),
   (c) test the IMP path rather than TYM.

Honest status: install is solved and we're ahead of any prior attempt, but a stable
login-capable TENEX requires clearing monitor/EXEC bugs the upstream author left
unsolved. Depth is uncertain.

### IMSSS tape lead (chosen direction: hunt a real login directory)

The `kit-cache/imsss/` repo holds two DUMPER tapes from the real Stanford IMSSS
PDP-10 ("To Sweden from IMSSS Stanford - TENEX 1.31", 1985), recovered by ICM.
Contents (from `listing-1/2.txt`, already extracted to `imsss/files/`):
- `<SYSTEM>` (56 files incl. real `EXEC.SAV;30`, `CHECKDSK.SAV`, **`ERROR.MNEMONICS`**
  — likely the EXEC error-message file ours is missing), `<SUBSYS>` (228),
  `<MON>` (238), `<SOURCES>` (91), `<EXEC>` (39).
- **Real user login dirs `<RON>` (212 files, = ROBERTS, RONALD G.) and `<NOR>`
  (190).** `<SYSTEM>NAMES.TXT` also lists a `GUEST` account marked "FOR TESTING,
  CAN BE CHANGED LATER" (but no `<GUEST>` dir is on these tapes).
- **Tape format is byte-compatible** with our working `system.tap` (identical
  `1e0a 0000 … 0000 0100 … ffff ffff 0f00` framing), so our in-TENEX
  `MINI-DUMPER` should be able to read these 1985 tapes.

Open uncertainties: (1) does our 1971 MINI-DUMPER actually read the 1985 tape
(testing now via a non-destructive `CHECK` — `runtime/build-tenex-imsss-check.do`);
(2) does a MINI-DUMPER restore recreate a directory as LOGIN-capable WITH its
password — and we don't know the cleartext passwords for RON/NOR (would need to
reset as wheel after restore, or hope for blank). Plan: CHECK → restore a user dir
→ verify it's login-able → set a known password as wheel → LOGIN test (via the
IMP/NCP path, the real ARPANET route).

### 2026-06-22 results on the IMSSS lead

- **GATE 1 PASSED: our 1971 MINI-DUMPER reads the 1985 IMSSS tape.** A non-destructive
  DUMPER `CHECK` (`runtime/build-tenex-imsss-check.do`, transcript
  `transcripts/imsss-check.txt`) enumerated the entire real `<SYSTEM>`
  (`EXEC.SAV;30`, `ERROR.MNEMONICS`, `NAMES.TXT`, `SEXEC.SAV;190`, PUP-network…)
  with no tape/parity errors. The real-accounts restore path is open.
- **Root cause of the DLUSER bug FOUND (source-level).** DUMPER restore creates
  directories with the SAME `CRDIR` JSYS that DLUSER fails on (`dumper.fai:1306`
  vs `dluser.mac:308`). DUMPER calls `CRDIR` with `[XWD 367740,BUFF]` where BUFF =
  the directory's parameter block READ FROM THE TAPE (real attributes incl.
  password); DLUSER fills the block from `users.txt` with an explicit directory
  NUMBER (`#6=2/3/4`) — the explicit/duplicate dir-number request is almost
  certainly why DLUSER's `CRDIR` is rejected while DUMPER's succeeds. Implication:
  restoring a user dir recreates it WITH its original login attributes/password.
- Live-console driving over the DC telnet socket is unreliable (no clean echo);
  drive everything via SIMH `expect` do-files.
- RUNNING NOW: `runtime/build-tenex-imsss-ron.do` — install EXEC → restore `<RON>`
  (SPECIFIC USERS? Y → USERS: RON) → `DIRECTORY <RON>` → `CONNECT RON`. Tests
  whether the restore creates a real, accessible user directory. Password (unknown
  cleartext) to be handled next: reset as wheel, or decode the CRDIR arg difference
  to mint a fresh known-password `<GUEST>`.

## Objective & definition of done

A visitor can `@L 69`, reach a real TENEX EXEC `@` prompt, log in, and run a
basic command (`SYSTAT`/`DIR`/`LOGOUT`) — reproducibly, **unattended**. Four
gates (already encoded in `mini/host69-bbn-tenexctl.sh`):
`syslod-boot` ✅ → `install-files` ❌ → `login` ❌ → scenario ❌.

## What is actually true (grounded)

- Boot to `TENEX IN OPERATION` is reliable via `verify-build-tenex-syslod-boot`
  (file-redirected console, DC/TYM on 16945/16946).
- Every boot shows `NO EXEC` because every run answers the CLOBBER prompt `Y` —
  it re-initializes (wipes) the disk, so EXEC is never present.
- EXEC genuinely works: manually, from the mini-exec `.` prompt,
  `GET FILE DTA0:EXEC.SAV` + `START.` produces the real
  `SUMEX-AIM Tenex 1.31.82, EXEC 1.51` banner and `@ENABLE` succeeds. The only
  blocker is automating the post-`NO EXEC` keystrokes.
- `BUGCHK ... FAILED TO OPEN BUGTABLE FILE` is NOT fatal — the monitor
  logs-and-proceeds (verified vs `POSTLD.MAC`); it clears once system
  directories exist (DLUSER creates them).
- Booting Lars's prebuilt packs / `simh/run.do` is a DEAD END (comes up
  `NO EXEC`; his install never completed). It only becomes a working shortcut
  AFTER we complete the install once. See memory `host69-tenex-runphd-deadend`.

## Root cause of the automation failure

The controller's install driver (`write_build_tenex_install_files_do`,
host69-bbn-tenexctl.sh:276-381) diverged from Lars's canonical recipe into a
fragile `noexpect` + 12-chained-step-file design with `send -t delay=...` that
consumes prompts out of order. Lars's `install/simh/syslod.do` instead uses one
clean ordered block of `expect "X" send "Y"; continue` rules after `go 100`.
That block was never run verbatim on top of the proven boot prefix.

## Strategy: three experiments, in confidence order

Each runs nice'd, console redirected to a file, observed live via `nc` on the
DC port. Never kill for slowness — only on positive-hang evidence
(`pgrep -x pdp10-ki` ~0% CPU + flat `/proc/<pid>/io` write_bytes + no DC output,
sustained).

### Experiment A — Lars's canonical install block, verbatim, on the proven prefix
One do-file = proven `write_build_tenex_syslod_do` boot (reaches
`TENEX IN OPERATION`) + Lars's exact post-`go 100` lines from `syslod.do`:
`^Z` → `G` → `GET DTA0:EXEC.SAV` → `START.` → date → `ENABLE` →
`MOUNT DTA0:` → `GET`/`SSAVE 0 777 EXEC.SAV` → `RUN DLUSER.SAV` (load
`USERS.TXT`) → `GET`/`SSAVE <SUBSYS>DUMPER.SAV`. Replaces the controller's
`install-files` machine. Watch DC:16945 for the banner, `@`, `!`, `[New file]`,
`DONE.`

### Experiment B — rigorous phase barriers (if A's rules still collide)
Use SIMH's no-`continue` expect as a true barrier: register only disk-init
rules → run → on `[Confirm]` the CPU halts and control returns to the do-file →
`load`/`go 100` → register only the post-boot rules → `continue`. Guarantees
boot output cannot match install rules.

### Experiment C — drive the install over the DC TCP socket, teletype-slow (fallback)
Let SIMH own the boot to `NO EXEC` (proven, file-redirected), then send the
install keystrokes into the DC port (16945) at ~60 ms/char (extra after ESC),
mirroring the human who succeeded manually, avoiding the PTY path that wedges
re-init.

## Phase 2: The DLUSER directory-creation problem (NEW — current frontier)

Login needs user directories 2-4 (`PMFDIR0`, `SUBSYS`, `OPERATOR`). DLUSER fails
to create them (`CAN'T CREATE USER ... AS DIRECTORY NUMBER n, CONTINUING`) — Lars
Brinkhoff's own documented unsolved bug. Concrete, untried angles, in order:

1. **Diagnose, don't guess.** Read `install/sources/dluser.mac` and the disassembled
   monitor to find the exact JSYS/error path that fails on directory creation
   (bit-table state, directory-number allocation, MOUNT/connected-dir, or a
   protection/account check). Add a SIMH breakpoint if needed.
2. **Bypass DLUSER via DUMPER restore.** `system.tap` is a DUMPER saveset from a
   real installed TENEX (`<SYSTEM>`/`<SUBSYS>`). Restoring it with DUMPER
   (`DUMP, LOAD, CHECK, OR SINGLE? L` ...) may populate the directory structure
   directly, sidestepping the buggy creation path. This also lands BUGTABLE and
   the subsystem set.
3. **Lean on real artifacts.** The `imsss` repo (`kit-cache/imsss`) holds real
   TENEX disk/tape artifacts and directory structures to model or graft.
4. **Order-of-operations.** Try `RUN DLUSER` BEFORE saving EXEC, or create the
   system directories before MOUNT, in case the connected-directory/bit-table
   state at save time is what blocks creation.
5. **Fallback for a usable host.** Login as `SYSTEM` (directory 1 — exists, has
   EXEC) may already give a usable EXEC `@` prompt for a scenario, even before
   accounts 2-4 work. Acceptable interim for proving the route end-to-end.

Definition of progress here: at least one real account logs in and runs a basic
command, OR SYSTEM login gives a working `@` prompt and `NO EXEC`/BUGTABLE are gone.

## Persistence & validation (turns "boots once" into "up and running")

1. After a successful install, reboot WITHOUT clobber: cold-start from the
   SYSLOD DECtape but answer CLOBBER `N` (avoid `SYSGO$G`, documented-broken).
   Confirm the disk comes up WITH EXEC → `@` prompt; `NO EXEC`/BUGTABLE gone.
2. Run `verify-build-tenex-login`: log in with a `users.txt` account
   (`OPERATOR`/`OPERATOR`) and run a basic command.
3. Snapshot the installed `tenex*.rp03` packs as the canonical fast-boot image
   so future starts skip the install.

## Safety & environment

- 2 cores at load ~11.5 with 5 live sims (host70/126/134/11, sigma01) — never
  disturb them; host69 stays nice'd and slow.
- Before any clobber, back up the working `tenex*.rp03`; they are also
  recoverable via `git -C kit-cache/build-tenex restore media/`.
- All work private; `@L 69` disabled until all gates pass unattended.

## Rollout (only after gates pass)

Snapshot image → add a fast "boot installed disk" path to
`host69-bbn-tenexctl.sh` → wire `@L 69` + host card + a real 1972-era scenario
→ commit.

### 2026-06-22 — DLUSER bug ROOT-CAUSED + data-only fix (running)

- Full IMSSS restore (SPECIFIC USERS? N) FAILED: ~50 min then CPU-pegged, zero
  read+write I/O, `KILLED JOB`. Restoring foreign IMSSS <SYSTEM> over the running
  SUMEX monitor destabilized it. Too slow + fragile. (Selective SPECIFIC USERS? Y
  can't create non-existent dirs: `NO SUCH USER, TRY AGAIN`.)
- ROOT CAUSE (jsys.mac): CRDIR new-dir path → MAKNFD(1775). If users.txt supplies a
  dir number (#6, flag 1B6, which DLUSER always sets) → FNN01(1910): number must be
  in range AND HSHLUK-available, else FNN05 = "Number unavailable" = CAN'T CREATE.
  SYSLOD reserves the LOW dir numbers, so #6=2/3/4 are unavailable. DUMPER works
  because it uses higher tape numbers.
- FIX (data-only): users.txt #6=2/3/4 -> 20/21/22 (octal), rebuild syslod.dta via
  tools/tendmp. OPERATOR then created with its KNOWN password OPERATOR.
  (boot/users.txt.orig preserves original.) Driver: runtime/build-tenex-dluserfix.do.
