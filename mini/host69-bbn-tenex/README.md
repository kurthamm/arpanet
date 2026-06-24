# BBN-TENEX Host #69 Lab

This directory is the isolated bring-up workspace for BBN-TENEX at ARPANET
host `#69` / octal `105`, attached to BBN IMP `05`, host index `1`.

This is not a public live host yet. The route remains disabled until a real
TENEX system boots and accepts real logins.

## Historical Identity

- IMP: `05`
- Host index: `1`
- Host number: `69`
- Octal: `105`
- Host name: `BBN-TENEX`
- Topology ports: `21051/21052`

## Emulator Direction

Use the project SIMH PDP-10 KA/KI path first. It supports the required TENEX
hardware features:

```text
set cpu 512k
set cpu bbn
set pmp enable
set pmp0 type=3330-2
set imp enable
set imp bbn
```

The primary unresolved problem is constructing or restoring a bootable TENEX
disk image, not browser routing.

## Public Rollout Gate

Do not connect this directory to `mini/arpanet`, the browser terminal, the
active host cards, or 2026 scenarios until validation proves:

1. TENEX boots.
2. A real EXEC prompt is reached.
3. A real user login works.
4. At least the basic 1972 BBN-TENEX scenario transcript works.

See `docs/host69-bbn-tenex-plan.md` for the evidence and full plan.

## Lab Controller

Use the private controller from the repository root:

```sh
./mini/host69-bbn-tenexctl.sh prepare
./mini/host69-bbn-tenexctl.sh probe-config
./mini/host69-bbn-tenexctl.sh probe-load
```

The controller uses ignored directories only for external kit files, runtime
input files, and transcripts. It does not start a public `@L 69` route.

## First Probe Result

The SIMH hardware profile is valid. `probe-config` confirms that the project
PDP-10 simulator accepts:

```text
CPU     512KW, BBN
PMP0    203MB, not attached, TYPE=3330-2
IMP     ... BBN
```

The public TENEX artifacts currently in the `PDP-10/tenex` kit are not direct
SIMH `LOAD` images. Direct probes of `EDDT.10X`, `LOD10X.RUN`, `TENDMP.10X`,
and `TENEX.SAV` all report `Format error` / `Can't determine load file
format`, and none reaches a TENEX banner.

That means the next blocker is the real TENEX bootstrap/media path: construct
or restore a 3330-style TENEX disk image with BOOTS/GETBTS and a usable TENEX
file system. This lab should stay private until that succeeds.

## DTBOOT Result

The lab now proves the DECtape loader path, but not a full TENEX boot.

Confirmed:

- SIMH device `DT`, not `DTC`, matches the TENEX DTBOOT device codes used by
  the recovered loader.
- A DECtape built from `134-tenex/TENEX.SAV` can be listed by DTBOOT as
  `TENEX.SAV`.
- A chunked DTBOOT stream with a small high-memory trampoline reaches the
  real monitor entry at PC `000066` under SIMH BBN mode.
- The same result holds with PMP and IMP enabled.

Current failure:

- After transfer, the monitor calls `TENDMP` to load the swappable monitor.
- The local BBN 134 media has `TENEX.SAV` but no `TENEX.SWP`.
- DTBOOT/TENDMP returns to the loader command loop at `777012/777013`.

So the hard gate is now specific: find or build the matching `TENEX.SWP`
swappable-monitor image, or build a complete TENEX monitor/disk image from
the recovered sources. Do not expose `@L 69` while this remains true.

## Install Media Survey

Run:

```sh
./mini/host69-bbn-tenexctl.sh survey-install-media
```

The survey pulls the public `PDP-10/bsys` and `PDP-10/imsss` repositories into
ignored cache and writes `transcripts/install-media-survey.txt`.

The current evidence is better than source-only:

- `PDP-10/tenex` issue 18 documents the intended install path: boot a DECtape
  with `TENEX.SAV` and `TENEX.SWP`, enter mini-exec `SYSLOD$G`, then load
  `DLUSER.SAV`, `USERS.TXT`, `DUMPER.SAV`, and a Dumper saveset.
- `PDP-10/imsss` contains recovered TENEX files from Stanford IMSSS, including
  `DLUSER.SAV`, `DUMPER.SAV`, `EXEC.SAV`, `SYSJOB.SAV`, `CHECKDSK.SAV`,
  `MDDT*.SAV`, `MACRO.SAV`, `LOADER.SAV`, `LINK*.SAV`, `TECO.SAV`, `SOS.SAV`,
  `READMAIL.SAV`, monitor `AMON` files, and `RLRMON` files.

The remaining hard gate is still bootstrapping: no `TENEX.SWP` or ready
bootable TENEX install DECtape/disk image has been found locally yet, and the
IMSSS extracted `.SAV`/monitor files are not direct SIMH `LOAD` images.

## Build-TENEX Lead

A deeper forum/documentation pass found the strongest available public lead:

- Retrocomputing Forum thread: `TENEX coming back to life`
- Repository: `https://github.com/larsbrinkhoff/build-tenex`
- Authors named in the thread: Lars Brinkhoff and Richard Cornwell

This is not recovered BBN-TENEX host `#69` media. It is a SUMEX-AIM TENEX
1.31.82 build/boot lab. It is still historically useful because it contains
the missing class of artifact the public `PDP-10/tenex` kit lacks:

- `install/boot/tenex.sav`
- `install/boot/tenex.swp`
- `install/boot/users.txt`
- `install/subsys/dluser.sav`
- `install/subsys/dumper.sav`
- `install/system/exec.sav`
- generated `syslod.dta` with the above files
- prebuilt RP03 disk images under `media/`

The `build-tenex` README says the monitor was assembled and linked, the
resident monitor can run, the swappable monitor loads from DECtape, mini-exec
works, and `EXEC.SAV` can be loaded and run from DECtape. It also says the full
install is not complete: `DLUSER` has directory-creation errors, mini-DUMPER
tape handling is incomplete, and rebooting with `SYSGO$G`/`SYSGO1$G` does not
work.

Local test result:

- Cornwell `pdp10-ki` from `https://github.com/rcornwell/sims` builds cleanly
  in ignored cache and passes its register sanity check.
- The generated `syslod.dta` lists as a TENEX DECtape containing
  `TENEX.SWP`, `TENEX.SAV`, `DLUSER.SAV`, `USERS.TXT`, `DUMPER.SAV`, and
  `EXEC.SAV`.
- The current project `pdp10-ka` is not the right binary for this lab; it lacks
  Cornwell KI/TYM/DF10 pieces used by the SUMEX monitor.
- A first private boot probe with Cornwell `pdp10-ki` reaches the DTBOOT
  command loop / monitor load path but did not yet produce a usable TENEX EXEC
  login on the probed DC/TYM lines.

This changes the host69 path from "find a `TENEX.SWP`" to "adapt and stabilize
the `build-tenex` SUMEX-AIM lab, then decide whether to use it as a TENEX-class
stand-in while continuing the separate search for BBN 1.29/1.34 media."

## Reproducible Build-TENEX Checks

The host69 controller now keeps the Lars/Cornwell path reproducible without
turning it into a public host:

```sh
./mini/host69-bbn-tenexctl.sh verify-cornwell-patches
./mini/host69-bbn-tenexctl.sh build-cornwell
./mini/host69-bbn-tenexctl.sh verify-build-tenex-media
./mini/host69-bbn-tenexctl.sh verify-build-tenex-syslod
```

Current verified result:

- The Cornwell simulator checkout has the local BBN/TENEX fixes for BBN page
  faults, JSYS PC handling, and the TYM zero-size queue guard. A previous
  PI-hold change (`pi_enable || QBBN`) is deliberately not part of the patch:
  tracing showed it drives the monitor into the `JSYS IN PI ROUTINE` bug-halt
  path.
- The Lars `syslod.dta` media lists correctly and contains `TENEX.SWP`,
  `TENEX.SAV`, `DLUSER.SAV`, `USERS.TXT`, `DUMPER.SAV`, and `EXEC.SAV`.
- The private SYSLOD harness sends `SYSLOD$G`.
- The run still does not reach the disk-initialization question or EXEC login.
  One traced path shows TENDMP looping in its DECtape status/data-ready polling
  while trying to load `TENEX.SWP`; the clean private harness later stops in
  the TENEX monitor bug-halt path (`exbugh`, PC `401006`).

That means the current blocker has narrowed again: media inventory is good,
but the Lars/Cornwell SYSLOD/TENEX boot path has not yet reproduced Lars'
reported mini-exec/EXEC result locally. `@L 69` remains disabled.

## Live Debug Log - Current Blocker

Checkpoint rule for this host: whenever the blocker changes, update this
section and `docs/host69-bbn-tenex-plan.md` before starting the next long
experiment. Record the exact transcript milestone, the exact process/port
state, and whether `@L 69` remains disabled. This prevents compaction or
interrupted sessions from hiding what was already learned.

Current live finding, June 21, 2026:

- Do not keep retrying the public `PDP-10/tenex` raw `TENEX.SAV` direct-load
  path. That path lacks a matching `TENEX.SWP` and is not the current best
  lead.
- The active lead is Lars Brinkhoff's `build-tenex` harness in ignored cache:
  `mini/host69-bbn-tenex/kit-cache/build-tenex`.
- Run it from its own `install/` directory with Cornwell `pdp10-ki` on `PATH`,
  matching Lars' scripts:

  ```sh
  cd mini/host69-bbn-tenex/kit-cache/build-tenex/install
  PATH=/home/deltaprism/arpanet/mini/host69-bbn-tenex/kit-cache/rcornwell-sims/BIN:$PATH \
    pdp10-ki simh/install.do
  ```

- DDT command notation matters. Existing scripts write `SYSLOD\033G`, which
  DDT displays as `SYSLOD$G`. A literal dollar sign is wrong at the console.
  Use ESC/Altmode before `G`, not the `$` key.
- In one live run, the harness printed `SYSLOD$G` and appeared stuck at
  `PC 477641 (CONSO 324,1)`. Interrupting with the simulator escape did not
  actually reach the simulator prompt; the running TENEX/SYSLOD prompt later
  appeared. Text intended for SIMH inspection was therefore typed into SYSLOD.
  The final `Y` answered:

  ```text
  DO YOU REALLY WANT TO CLOBBER THE DISC BY RE-INITIALIZING?
  ```

  and the run advanced to:

  ```text
  OK, YOU ASKED FOR IT.
  TENEX RESTARTING, WAIT... NO CHECKDSK
  ```

- The immediate next step is to continue from the live `NO CHECKDSK` state and
  feed the documented script responses (`I`, `.`, `TTY:`, confirm), while
  avoiding simulator-inspection commands unless the SIMH `sim>` prompt is
  definitely visible.
- Follow-up from the same run: after the disk reinitialization answer, visible
  output moved to the TYM listener on TCP port `12346`, not the simulator
  console. A passive `nc 127.0.0.1 12346` connection showed:

  ```text
  Connected to the KI-10 simulator TYM device, line 0

  TENEX RESTARTING, WAIT...
  ```

  This means a silent simulator console is not proof of a dead run. Check the
  TYM line before interrupting. Sending `I` on the TYM line echoed the
  character but did not immediately advance the dialogue, so the next
  diagnostic is to inspect whether TENEX is waiting for TYM input, console
  input, or a DECtape/status event.
- Boot milestone from the same run: the DC listener on TCP port `12345` showed
  the system continued through startup and reached operation:

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

  This is further than the previous documented blocker. The current blocker is
  no longer "TENEX will not boot"; it is now "TENEX is in operation, but a
  usable interactive EXEC/login on the public TYM line still has to be reached
  and validated."
- Interactive follow-up:
  - Fresh TYM connections still show the stale `TENEX RESTARTING, WAIT...`
    text and close after Return, so the TYM visitor path is not usable yet.
  - A DC connection after TYM disconnect reports:

    ```text
    JOB 1, USER SYSTEM, ACCT 220100, DETACHED
    ****
    ```

  - Pressing Return on an interactive DC connection produces another monitor
    diagnostic:

    ```text
    BUGCHK AT 402542 - (FAILED TO GTJFN/OPEN BUGTABLE FILE)
    ```

  The next concrete blocker is therefore missing or inaccessible BUGTABLE
  support data during monitor diagnostic handling, plus TYM line startup not
  reaching EXEC/login.
- Clean non-destructive `simh/run.do` test after clearing stale ports:
  - Started Cornwell `pdp10-ki simh/run.do` from `build-tenex/install`.
  - Passive DC probe printed only the simulator DC device banner.
  - Passive TYM probe printed no TENEX text.
  - SIMH WRU (`Ctrl-\`) stopped the simulator at `PC 777430`; `EX PC`
    showed `777400`, with no current DC/TYM connections.
  - Conclusion: the checked-in generated disk/run path is not currently a
    public-ready boot shortcut in this workspace. The only path that has
    reached `TENEX IN OPERATION` remains the SYSLOD/install harness.
- Private SYSLOD + DUMPER-load experiment:
  - Staged real IMSSS TENEX support files into the ignored Lars install tree
    as `install/system/bugtable.sumex-aim.13182` and
    `install/system/bugstrings.sumex-aim.13182`, then rebuilt
    `install/media/system.tap`.
  - The tape listing showed `<SYSTEM>BUGTABLE.SUMEX-AIM` and
    `<SYSTEM>BUGSTRINGS.SUMEX-AIM`.
  - A first automated script,
    `runtime/build-tenex-syslod-dumper-load.do`, proved the current SIMH
    `expect` ordering is wrong: the transcript reached `TENEX IN OPERATION`
    and `NO EXEC` before the later `INIT BIT TABLE`/badspots responses were
    applied. That script is not a valid installer yet.
  - A follow-up plain-SIMH variant added `continue` after the badspots
    `[Confirm]` response. That did not reproduce the prior `TENEX IN
    OPERATION` milestone; it hung after `TENEX RESTARTING, WAIT... NO
    CHECKDSK`, with TYM still showing only the restart banner and DC showing
    only the device banner. The process was stopped and ports were clean.
  - A pexpect/PTTY driver was also tested. It changed the initial timing:
    sending `SYSLOD<ESC>G` after `go 100` produced a bell/invalid command,
    and trying SIMH `send` from `sim>` only echoed `SYSLOD$G`. Do not use the
    pexpect/PTTY path as evidence of TENEX behavior without solving that
    timing difference.
  - Updated current blocker: write a correctly ordered driver for SYSLOD and
    the mini-EXEC setup. Do not treat the staged BUGTABLE test as validated
    until a boot reaches EXEC/login without the BUGTABLE GTJFN failure.
- Controller gate update, June 21, 2026:
  - Added explicit private gates:
    `verify-build-tenex-syslod-boot`,
    `verify-build-tenex-install-files`, and `verify-build-tenex-login`.
  - `verify` now remains closed until all three gates pass; `@L 69` is still
    disabled.
  - `verify-build-tenex-system-tape` passed. The private `system.tap` lists
    `<SYSTEM>BUGTABLE.SUMEX-AIM`, `<SYSTEM>BUGSTRINGS.SUMEX-AIM`,
    `<SYSTEM>EXEC.SAV`, and `<SUBSYS>DUMPER.SAV`.
  - `verify-build-tenex-syslod-boot` now passes and captures DC output
    alongside the simulator transcript. The boot reaches `TENEX IN
    OPERATION`, but still prints `NO EXEC` and
    `FAILED TO GTJFN/OPEN BUGTABLE FILE`. Current transcript paths:
    `transcripts/build-tenex-syslod.txt`,
    `transcripts/build-tenex-syslod-dc.txt`, and
    `transcripts/build-tenex-syslod-tym.txt`.
  - `verify-build-tenex-install-files` was rerun after removing the invalid
    mini-EXEC `Ctrl-Z` sends. This removed the `.^Z ?` errors, but the gate
    still failed. The transcript stops after
    `READ BADSPOTS FROM FILE: TTY: [Confirm]`; DC still reaches
    `TENEX IN OPERATION`, `NO EXEC`, and the BUGTABLE GTJFN failure.
  - Current driver conclusion: a single queued SIMH `expect` script is not a
    reliable abstraction for the whole install flow. SIMH queues all expects
    before `go 100`, so repeated prompt strings such as `[Confirm]` and
    `\n.` are ambiguous. The next pass must split install into smaller gates
    or use a terminal-driven control path after the first boot milestone.
- Manual-console checkpoint, June 21, 2026:
  - Added `mini/host69-bbn-tenexctl.sh manual-install-console` for a
    foreground SIMH session. This is the path to use for hand-driving the
    mini-exec install prompt; the DC/TYM TCP ports are observation lines, not
    the place where the current mini-exec `GET FILE` prompt is being answered.
  - Current private ports when the manual console is running:
    `127.0.0.1:16945` for DC observation and `127.0.0.1:16946` for TYM
    observation. These are not public ARPANET/TIP routes.
  - The verifier now reaches mini-exec `GET FILE`, but automated filename
    delivery is still unreliable. Latest evidence showed `G` invoked
    `GET FILE`, but the intended `DTA0:EXEC.SAV` response arrived garbled
    (`SDTA0:` / split dot-prompt commands). This is an input pacing/control
    problem, not proof that `EXEC.SAV` is absent.
  - If hand-driving the foreground console, the next commands to try after
    the mini-exec dot prompt are:

    ```text
    ^Z
    G
    DTA0:EXEC.SAV
    ```

    If the console is at SIMH `sim>` rather than the TENEX dot prompt, use
    SIMH `send` commands, then `continue`; do not use public `@L 69`.

## Manual EXEC Progress Checkpoint

June 21, 2026 later pass: the foreground manual console got further than the
scripted installer.

Manual evidence:

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

This proves the real DECtape `EXEC.SAV` can be loaded and started. It also
proves the EXEC reaches `@`, accepts `ENABLE`, and returns the privileged `!`
prompt.

Current automation limitation:

```text
.GET FILE DTA0:EXEC.SAV [Confirm]
```

The scripted path still times out at that confirmation prompt. Do not spend
time treating this as missing media; it is currently a SIMH input-control
problem. The latest transcript is
`transcripts/build-tenex-install-files.txt`.

For the next manual pass:

```sh
cd /home/deltaprism/arpanet
./mini/host69-bbn-tenexctl.sh manual-install-console
```

Use the proven manual sequence above. After reaching `!`, do not retry
`GET DTA0:EXEC.SAV` / `SSAVE` until the exact Lars install flow is checked.
The next useful target is to run `DTA0:DLUSER.SAV`, point it at
`DTA0:USERS.TXT`, and capture the exact success or error text.

Current clean-state note: after the stopped run, no `pdp10-ki`, host69
controller, or host69 private listener was running on `16945`, `16946`,
`12345`, `12346`, `16969`, or `10569`.

Public state remains unchanged: `@L 69` is disabled until real EXEC/login is
validated.
