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
