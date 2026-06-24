# BBN-TENEX Host #69 Bring-Up Plan

## Summary

BBN-TENEX is the right next historically significant host to pursue, but it
must not be exposed publicly until a real TENEX system boots and accepts a
real login.

The historical ARPANET identity is:

- Site: BBN
- IMP: `05`
- Host index: `1`
- ARPANET host: `#69`
- Octal host: `105`
- Topology ports already reserved: `21051/21052`

The 1972 ICCC booklet makes BBN-TENEX one of the richest possible hosts. It
documents the plain TENEX login scenario and several application scenarios on
host `#69`: RJS, LIFE, SCHOLAR, CHESS, and DOCTOR.

## Current Evidence

### Local Project Topology

`mini/arpanet-topology.conf` already contains the BBN host identity:

```text
IMP 05 #BBN
  host1 1 BBN-TENEX #69
...
IMP 05 #BBN
  hi2 21051 21052 host1 BBN-TENEX
```

`mini/arpanet` currently keeps this route disabled:

```text
#  "05:1:69:21051:21052:BBN-TENEX"
```

That is correct until the backend is real.

### 1972 Scenario Targets

The ICCC booklet documents these BBN-TENEX scenarios:

- `BBN TENEX === HOST #69`
- `REMOTE JOB SERVICE === HOSTS #69 AND #65`
- `BBN LIFE === HOST #69`
- `SCHOLAR === HOST #69`
- `BBN Chess === HOST #69`
- `BBN DOCTOR === HOST #69`

The basic TENEX scenario expects a connection to host `69` and a banner like:

```text
BBN-TENEX 1.29.6, SYSTEM-A EXEC 1.43
```

The later BBN scenarios use real TENEX commands such as:

```text
login iccc iccc 11514
run <hacks>life
run <warnock>scholar
run <hacks>chess
run <hacks>doctor
```

Those application directories and runnable files are rollout gates, not text
to fake.

### Public TENEX Material

The public `PDP-10/tenex` repository contains real TENEX source and system
material, including:

- TENEX 1.28, 1.33, 1.34, and 1.35 source trees
- `TENEX.SAV`, `TENDMP.10X`, `EDDT.10X`, and monitor load command files
- TENEX EXEC sources
- TECO sources
- DEC FORTRAN/F40 and LOADER material
- LISP material with DOCTOR/CHESS-adjacent references
- SUMEX/BBN documentation for TENEX disk layout, BOOTS, and operations

This is real material, but it is not yet a proven bootable BBN #69 disk pack.

`PDP-10/tenex` issue 18, "Installation media", documents the likely install
path: a bootable DECtape containing `TENEX.SAV` and `TENEX.SWP`; from the
mini-exec, run `SYSLOD$G`, initialize the disk, then load `DLUSER.SAV`,
`USERS.TXT`, `DUMPER.SAV`, and a Dumper saveset.

The public `PDP-10/imsss` repository adds important recovered TENEX system
files from Stanford IMSSS. The host69 lab survey finds local copies of:

- `DLUSER.SAV`
- `DUMPER.SAV`
- `EXEC.SAV`
- `SYSJOB.SAV`
- `CHECKDSK.SAV`
- `MDDT*.SAV`
- `MACRO.SAV`
- `LOADER.SAV`
- `LINK*.SAV`
- `TECO.SAV`
- `SOS.SAV`
- `READMAIL.SAV`
- monitor `AMON` files
- `RLRMON` files

The survey does not find `TENEX.SWP` or `USERS.TXT` locally. The IMSSS files
are recovered TENEX files, not direct SIMH `LOAD` inputs.

### Emulator Path

The existing project SIMH PDP-10 binary is the best first path. It already
supports the hardware features TENEX needs:

```text
set CPU BBN      ; Paging hardware for TENEX
set PMP ENABLE   ; P. Petit's IBM channel
set PMP0 TYPE=3330-2
set IMP BBN      ; BBN-style IMP interface
```

This is a better historical fit than stock KLH10 for this project because
the repo simulator directly models the BBN pager, 3330-style disk path, and
BBN IMP interface used by TENEX.

KLH10 was also tested in `/tmp` and builds successfully, but its standard
KL build is TOPS-20 oriented and its own documentation treats TENEX as a
bring-up task requiring BBN pager work.

## Hard Blocker

The blocker is not the web route or the active host card. The blocker is a
real TENEX boot/install medium and disk image / file system.

We need one of these:

1. A recovered bootable TENEX disk image compatible with SIMH KA/KI BBN mode.
2. A restorable TENEX backup tape/dump that can create a working file system.
3. A reproducible build path that creates a TENEX disk image from the public
   monitor, EXEC, system files, account files, and subsystems.
4. A bootable DECtape/read-in path that reaches the mini-exec `SYSLOD$G`
   installation dialogue using recovered `TENEX.SAV` plus the required
   support files.

Until one of those exists, `@L 69` must remain disabled or marked planned.

## Implementation Plan

### Phase 1: Isolated Lab

Create an isolated `mini/host69-bbn-tenex/` workspace with ignored runtime
storage:

- `kit-cache/`
- `runtime/`
- `logs/`
- `transcripts/`

No public route changes.

### Phase 2: SIMH Hardware Configuration

Create a SIMH config for BBN-TENEX lab use:

```text
set cpu 512k
set cpu bbn
set pmp enable
set pmp0 type=3330-2
set imp enable
set imp bbn
```

Then test whether TENEX bootstrap artifacts can be loaded far enough to reach
BOOTS/TENDMP behavior.

Status: complete for the hardware probe. `mini/host69-bbn-tenexctl.sh
probe-config` confirms the project SIMH PDP-10 accepts BBN pager mode, PMP
3330-2 disk configuration, and BBN IMP mode.

Direct SIMH `LOAD` tests against the public kit artifacts did not boot TENEX:

- `133-tenex/eddt.10x`
- `133-tenex/lod10x.run`
- `133-tenex/tendmp.10x`
- `134-tenex/EDDT.10X`
- `134-tenex/LOD10X.RUN`
- `134-tenex/TENDMP.10X`
- `134-tenex/TENEX.SAV`

Each direct-load attempt produced `Format error` / `Can't determine load file
format` and no TENEX banner. Transcripts are written under the ignored
`mini/host69-bbn-tenex/transcripts/` directory.

The kit documentation confirms that normal TENEX startup uses GETBTS/BOOTS and
a 3330-style TENEX disk file system. BOOTS is loaded from the last sectors of
the disk system or by read-in media, then loads monitor files such as
`DSK:<MON>AMON.SAV;0,G`. The public files are therefore not enough by
themselves as direct SIMH `LOAD` inputs.

Additional DTBOOT testing moved the blocker forward:

- The correct simulator device for the recovered TENEX DTBOOT code is `DT`,
  not SIMH `DTC`; DTBOOT uses device codes `DTC==320` and `DTS==324`, which
  line up with SIMH `DT`.
- A DECtape built from `134-tenex/TENEX.SAV` lists correctly as `TENEX.SAV`
  under DTBOOT.
- The raw `TENEX.SAV` file is not itself a DTBOOT SAVE stream. A generated
  chunked SAVE stream plus a small trampoline is required so DTBOOT can load
  the resident monitor without clobbering its own AC registers before the
  final transfer.
- That tape reaches the real monitor entry at PC `000066` under BBN CPU mode,
  and also with PMP and IMP enabled.
- After transfer, the monitor calls `TENDMP` to load the swappable monitor and
  then returns to DTBOOT because the matching `TENEX.SWP` file is absent.

The current hard gate is therefore specific: the BBN 134 public material has
`TENEX.SAV` but no matching `TENEX.SWP` / bootable TENEX disk state.

### Phase 3: Media Construction Or Restore

Investigate the public TENEX tree in this order:

1. Determine whether existing `TENEX.SAV`, `TENDMP.10X`, and `LOD10X.RUN`
   can produce a bootable monitor under SIMH BBN mode.
   - Result: direct SIMH `LOAD` does not work. These files need the TENEX
     bootstrap/file-system path, not generic SIMH loader input.
   - Result: DTBOOT can load a generated resident-monitor DECtape stream and
     transfer to PC `000066`, but startup cannot continue without the matching
     swappable monitor image (`TENEX.SWP`) or a complete TENEX disk build.
2. Determine whether BOOTS/GETBTS, BSYS, or other restore utilities can create a
   TENEX file system from public files.
   - Current evidence: `PDP-10/imsss` supplies many required files and two
     `.tap` images, while `PDP-10/bsys` supplies a BSYS tape reader. The old
     BSYS reader does not directly list the IMSSS `.tap` images in the lab yet,
     but the IMSSS repo already includes extracted files.
3. Build a minimal disk image with:
   - monitor
   - EXEC
   - `<SYSTEM>` files
   - `ICCC` login/account
   - TECO
   - FORTRAN/F40/LOADER
   - LISP
4. Only after a shell login works, load scenario application files.

Current reproducible private checks:

- `mini/host69-bbn-tenexctl.sh verify-cornwell-patches` confirms the local
  Cornwell checkout carries the BBN/TENEX fixes for JSYS PC handling, BBN page
  faults, and the TYM queue guard. The earlier PI-hold change is excluded
  because it was traced to the `JSYS IN PI ROUTINE` bug-halt path.
- `mini/host69-bbn-tenexctl.sh verify-build-tenex-media` confirms Lars'
  generated `syslod.dta` contains `TENEX.SWP`, `TENEX.SAV`, `DLUSER.SAV`,
  `USERS.TXT`, `DUMPER.SAV`, and `EXEC.SAV`.

June 21, 2026 live blocker update:

- The current best lead is no longer the public BBN 134 raw `TENEX.SAV`
  direct-load path. That path lacks a matching `TENEX.SWP`.
- The active path is Lars Brinkhoff's `build-tenex` harness run exactly from
  `mini/host69-bbn-tenex/kit-cache/build-tenex/install` with Cornwell
  `pdp10-ki` on `PATH`.
- DDT's `$G` notation is printed notation for ESC/Altmode plus `G`. Literal
  `SYSGO$G` and literal `113471$G` are rejected by the DDT prompt; sending
  `113471` followed by ESC and `G` is accepted.
- A live run of `pdp10-ki simh/install.do` reached `SYSLOD$G`. It appeared to
  sit at `PC 477641 (CONSO 324,1)`, but the TENEX/SYSLOD prompt later surfaced.
  Operator text intended for SIMH inspection was accidentally consumed by
  SYSLOD until a final `Y` answered the disk reinitialization prompt. The run
  then reached:

  ```text
  OK, YOU ASKED FOR IT.
  TENEX RESTARTING, WAIT... NO CHECKDSK
  ```

- Next work item: continue from the `NO CHECKDSK` dialogue using the exact
  responses from Lars' `install/simh/syslod.do` (`I`, `.`, `TTY:`, confirm),
  then determine whether it reaches mini-exec / `DTA0:EXEC.SAV`.
- Follow-up: after answering the disk reinitialization prompt, output appeared
  on the TYM listener (`nc 127.0.0.1 12346`), not the simulator console:

  ```text
  Connected to the KI-10 simulator TYM device, line 0

  TENEX RESTARTING, WAIT...
  ```

  Therefore the next diagnostic must check the TYM line before interrupting a
  seemingly silent simulator console. Sending `I` on TYM echoed the character
  but did not immediately advance, so the remaining question is whether the
  monitor is waiting for TYM input, console input, or a DECtape/status event.
- Boot milestone from the same live run: the DC listener on TCP port `12345`
  showed that TENEX continued through startup and reached operation:

  ```text
  RUNNING DDMP
  LOGIN JOB 0, USER SYSTEM, ACCT 220100, TTY 100
  DETACHED JOB 0, USER SYSTEM, ACCT 220100, TTY 100
  NO SYSJOB
  LOGIN JOB 1, USER SYSTEM, ACCT 220100, TTY 100
  *****BUGCHK AT 117441 F - (FAILED TO GTJFN/OPEN BUGTABLE FILE)
  DETACHED JOB 1, USER SYSTEM, ACCT 220100, TTY 100
  NO AUTOJOBS FILE
  TENEX IN OPERATION
  ```

  This moves host69 past the previous boot blocker. The current blocker is
  now interactive access: prove that a TYM/DC line can reach real EXEC/login,
  then create a reproducible validation script. `@L 69` remains disabled until
  that transcript exists.
- `mini/host69-bbn-tenexctl.sh verify-build-tenex-syslod` runs the private
  Lars SYSLOD harness with host69-specific terminal ports and records a
  transcript without starting any public route.

Current result: the media is present and the local simulator has now reached
`TENEX IN OPERATION` through the Lars/Cornwell SYSLOD path. The earlier
TENDMP/DECtape and `exbugh` traces are still useful history, but they are no
longer the current stopping point. The current stopping point is interactive
access:

Checkpoint rule: every time the blocker moves, update this file and
`mini/host69-bbn-tenex/README.md` before starting the next long experiment.
The update must include the transcript milestone, the process/port cleanup
state, and the current public-exposure decision. Until real EXEC/login is
validated, `@L 69`, the active host card, and any 2026 scenario stay disabled.

- Fresh TYM connections still show stale `TENEX RESTARTING, WAIT...` text and
  close after Return.
- DC shows detached SYSTEM jobs and monitor BUGCHK diagnostics.
- Pressing Return on DC produced:

  ```text
  BUGCHK AT 402542 - (FAILED TO GTJFN/OPEN BUGTABLE FILE)
  ```

The next technical target is therefore the TENEX support-file/login path:
identify and install or expose the expected BUGTABLE file and determine why
TYM line startup is not reaching a usable EXEC/login. This is still backend
work, not browser routing or ARPANET topology.

Follow-up test: the non-destructive Lars `simh/run.do` path was tried after
clearing stale host69 processes. It did not reach TENEX text on DC or TYM.
Interrupting to SIMH showed the machine in the DECtape bootstrap area
(`PC 777430`, then `EX PC` displayed `777400`). Treat the generated disk
`run.do` path as unproven; the SYSLOD/install path remains the only path that
has reached `TENEX IN OPERATION` in this workspace.

Support-file experiment: real IMSSS TENEX `BUGTABLE` and `BUGSTRINGS` files
were staged under the expected SUMEX-AIM filenames in the ignored Lars install
tree and `system.tap` was rebuilt. The tape now lists
`<SYSTEM>BUGTABLE.SUMEX-AIM` and `<SYSTEM>BUGSTRINGS.SUMEX-AIM`. A first
private `runtime/build-tenex-syslod-dumper-load.do` run was not a valid
install, because the SIMH `expect` ordering let TENEX reach `TENEX IN
OPERATION` and `NO EXEC` before the later SYSLOD inputs were consumed. The
next blocker is a correctly ordered SYSLOD/mini-EXEC driver; the BUGTABLE fix
is staged but not validated.

Follow-up driver tests:

- Adding `continue` after the badspots `[Confirm]` response did not fix the
  plain-SIMH script; it hung after `TENEX RESTARTING, WAIT... NO CHECKDSK`,
  with TYM showing only the restart banner and DC showing only the device
  banner.
- A pexpect/PTTY driver changed the timing enough to be misleading. Sending
  `SYSLOD<ESC>G` after `go 100` produced a bell, while issuing SIMH `send`
  from `sim>` only echoed `SYSLOD$G`. The original Lars timing depends on
  SIMH `expect` injecting the string while `go 100` is running.
- Current process state after these tests: no host69 simulator or netcat
  listener remains on `16945/16946` or `12345/12346`.

Controller gate update, June 21, 2026:

- Added explicit private gates:
  `verify-build-tenex-syslod-boot`,
  `verify-build-tenex-install-files`, and `verify-build-tenex-login`.
- `verify` now remains closed until login is proven; `@L 69` remains disabled.
- `verify-build-tenex-system-tape` passed. The private `system.tap` lists
  `<SYSTEM>BUGTABLE.SUMEX-AIM`, `<SYSTEM>BUGSTRINGS.SUMEX-AIM`,
  `<SYSTEM>EXEC.SAV`, and `<SUBSYS>DUMPER.SAV`.
- `verify-build-tenex-syslod-boot` now passes and captures the DC listener as
  part of the gate. It reaches `TENEX IN OPERATION`, but still shows `NO EXEC`
  and `FAILED TO GTJFN/OPEN BUGTABLE FILE`. Current transcripts:
  `build-tenex-syslod.txt`, `build-tenex-syslod-dc.txt`, and
  `build-tenex-syslod-tym.txt`.
- `verify-build-tenex-install-files` was rerun after removing the invalid
  `Ctrl-Z` sends. That removed the `.^Z ?` errors, but did not complete the
  install. The gate stops after
  `READ BADSPOTS FROM FILE: TTY: [Confirm]`; DC still reaches
  `TENEX IN OPERATION`, `NO EXEC`, and the BUGTABLE GTJFN failure.
- Driver conclusion: one queued SIMH `expect` script is not reliable for the
  full install path because repeated prompt strings collide before `go 100`.
  Next implementation should split the install into smaller gates or switch to
  a terminal-driven control path after the boot milestone.

Manual-console checkpoint, June 21, 2026:

- Added `mini/host69-bbn-tenexctl.sh manual-install-console` as the safer
  operator path for the current blocker. It runs the Lars/Cornwell simulator
  in the foreground and keeps `@L 69` disabled.
- Address distinction:
  - Mini-exec install work is on the foreground SIMH console.
  - DC observation port while the manual console is running:
    `127.0.0.1:16945`.
  - TYM observation port while the manual console is running:
    `127.0.0.1:16946`.
  - These TCP ports are private diagnostics, not the public ARPANET host.
- Current evidence from `verify-build-tenex-install-files`:
  - TENEX reaches `TENEX IN OPERATION`.
  - `^Z` reaches the mini-exec dot prompt.
  - `G` invokes `GET FILE`.
  - Automation is still garbling `DTA0:EXEC.SAV` at the filename prompt, so
    hand-driving the console may get past this faster than more scripted
    pacing experiments.
- The next manual command sequence to validate is:

  ```text
  ^Z
  G
  DTA0:EXEC.SAV
  ```

  If this succeeds, continue with the Lars flow (`S`, start EXEC, then install
  users/DUMPER). Capture screenshots/transcripts before changing public
  routing.

Manual-console progress checkpoint, June 21, 2026, later pass:

- The hand-driven foreground SIMH console got further than the current
  automation. Treat the manual transcript as the best evidence for the next
  pass.
- Confirmed manual path:

  ```text
  READ BADSPOTS FROM FILE: TTY: [Confirm]
  [Return]
  ^E
  sim> send "\032"
  sim> continue
  ^Z
  .GET FILE DTA0:EXEC.SAV [Confirm]
  [Return]
  .
  .START
    ?
  .START.

   SUMEX-AIM Tenex 1.31.82, SUMEX-AIM EXEC 1.51
   ENTER DATE AND TIME AS MM/DD/YY HH:MM -- 06/21/28 00:00
   PLEASE RECONFIRM: THURSDAY, JUNE 21, 1928 00:00:00
  @ENABLE
  !
  !MOUNT DTA0:
  !
  ```

- This proves the real SUMEX-AIM TENEX EXEC can be loaded from `DTA0` and
  started from the mini-exec path. It also proves `ENABLE` reaches the EXEC
  privileged `!` prompt and `MOUNT DTA0:` returns to `!`.
- The manual session later became nonresponsive after additional file work.
  Interrupting showed `PC: 105056`. Do not treat that as a failed EXEC load;
  the earlier `@` and `!` prompts are real progress.
- The current automation still only reaches:

  ```text
  .GET FILE DTA0:EXEC.SAV [Confirm]
  ```

  and then times out. Latest private transcript:
  `mini/host69-bbn-tenex/transcripts/build-tenex-install-files.txt`.
  The failure is the SIMH scripted input/control path at the confirmation
  prompt, not the TENEX media itself.
- Clean state after stopping the run: no `pdp10-ki`, no host69 controller
  process, and no listeners on `16945`, `16946`, `12345`, `12346`, `16969`,
  or `10569`.
- Tomorrow's best path is manual continuation from:

  ```sh
  cd /home/deltaprism/arpanet
  ./mini/host69-bbn-tenexctl.sh manual-install-console
  ```

  Then use the proven sequence above. After reaching `!`, skip any extra
  `GET DTA0:EXEC.SAV` / `SSAVE` attempt until the exact Lars flow is re-read.
  The next target is `RUN DTA0:DLUSER.SAV`, loading users from
  `DTA0:USERS.TXT`, and capturing the exact errors or success.
- `@L 69` remains disabled. No public host card or scenario should be added
  until a real EXEC/login transcript is captured.

### Phase 4: Scenario Gates

Expose only scenarios that run on the real booted host:

- Gate 1: basic `BBN TENEX === HOST #69`
- Gate 2: FORTRAN/TECO if compiler flow works
- Gate 3: `BBN LIFE` only if real LIFE runs
- Gate 4: `SCHOLAR` only if real SCHOLAR files are installed and run
- Gate 5: `BBN Chess` only if real CHESS runs
- Gate 6: `BBN DOCTOR` only if real DOCTOR runs on BBN-TENEX
- Gate 7: RJS only after both BBN #69 and UCLA-CCN #65 have real cooperating
  services

## Rollout Rules

- Do not add an active host card for `#69` until TENEX boots and login works.
- Do not add a 2026 scenario for `#69` until its commands have been run and
  transcript-validated.
- Do not claim recovered BBN disk media unless a source image or archive is
  actually found.
- Do not route `@L 69` to TOPS-20, ITS, or a fake TENEX shell.

## Acceptance Test

Minimum public-ready validation:

```text
@L 69
BBN-TENEX ...
@ login iccc ...
@ systat
@ dir
@ logout
```

Scenario-ready validation additionally requires the exact scenario command
transcript for each published scenario.
