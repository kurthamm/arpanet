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
