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
real TENEX disk image / file system.

We need one of these:

1. A recovered bootable TENEX disk image compatible with SIMH KA/KI BBN mode.
2. A restorable TENEX backup tape/dump that can create a working file system.
3. A reproducible build path that creates a TENEX disk image from the public
   monitor, EXEC, system files, account files, and subsystems.

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

### Phase 3: Media Construction Or Restore

Investigate the public TENEX tree in this order:

1. Determine whether existing `TENEX.SAV`, `TENDMP.10X`, and `LOD10X.RUN`
   can produce a bootable monitor under SIMH BBN mode.
2. Determine whether BSYS or other backup/restore utilities can create a
   TENEX file system from public files.
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

