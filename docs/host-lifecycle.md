# Hosted Host Lifecycle

Use `mini/hostctl.sh` to manage the active hosted ITS PDP-10 hosts (`70`, `126`, `134`, and `198`).
Use `mini/host11ctl.sh` to manage Stanford/SU-AI host `11`, which is a separate
WAITS/SAIL lane and is not part of the MIT ITS trio.
Use `mini/host01-sigma/host01-sigmactl.sh` to manage UCLA-NMC host `1`, which is
a SIMH Sigma 7 CP-V system exposed through the browser terminal path.
Use `mini/host06-multicsctl.sh` to manage MIT-MULTICS host `6`, which is a
DPS8M/MR12.8 Multics system exposed through the browser terminal path.

The older `mini/host70.sh`, `mini/host126.sh`, `mini/host134.sh`, and `mini/host198.sh` entrypoints are compatibility shims around `hostctl.sh`. `mini/host06.sh` intentionally refuses to start MIT-AI because host `6` is MIT-MULTICS. Use the host-specific controllers for operational work.

## Commands

From the repository root:

```sh
mini/hostctl.sh status all
mini/hostctl.sh verify all
mini/hostctl.sh restart 70
mini/hostctl.sh stop 70
mini/hostctl.sh start 70
mini/host11ctl.sh status 11
mini/host11ctl.sh verify 11
mini/host11ctl.sh restart 11
mini/host01-sigma/host01-sigmactl.sh status
mini/host01-sigma/host01-sigmactl.sh verify
mini/host01-sigma/host01-sigmactl.sh restart
mini/host06-multicsctl.sh status
mini/host06-multicsctl.sh verify
mini/host06-multicsctl.sh restart
```

Valid active ITS host targets are `70`, `126`, `134`, `198`, or `all`. Host `126` is HILTON-KA1 at IMP `62`, host index `1`, octal `176`. MIT-MULTICS host `6` is managed separately by `host06-multicsctl.sh`.
For `host11ctl.sh`, the only valid host target is `11`.
The Sigma host controller does not take a host number because it owns only host
`1`.

## What The Tool Guarantees

- Stops the named `screen` session.
- Finds PDP-10 simulator owners of that host's terminal and IMP ports.
- Terminates the owning process group, not just the screen wrapper.
- Waits for that host's ports to clear before starting.
- Refuses to start if ports are still owned.
- Restores clean `rp03.*` packs from the tracked host subdirectory before start.
- Backs up previous mutable packs under `$HOME/arpanet-runtime-backups`.
- Attempts direct `NCP=ncp31 ./ncp-ping` verification after restart. Browser
  terminal usability is validated separately through `do.sh` and the
  localhost-only simulator terminal lines.

For Stanford/SU-AI, `host11ctl.sh`:

- Manages the `host11` WAITS SIMH screen and the `waitsconnect` bridge screen.
- Builds `mini/src/waits-ncpd/waitsconnect` when the source is newer than the binary.
- Downloads the WAITS archive only if required disk files are missing.
- Backs up `SYS000.ckd`, `SYS001.ckd`, and `SYS002.ckd` once under
  `$HOME/arpanet-runtime-backups/host11-initial`.
- Owns only the Stanford ports: TCP `1025`, TCP `2040-2043`, and UDP `20112`.
- Verifies host `11` with `NCP=ncp16 ./ncp-ping`, because the live Stanford
  NCP echo path answers from AMES NCP16 and does not answer from CCA NCP31.

Stanford/SU-AI PARRY is intentionally reproducible. If the WAITS packs need to
be restored to the tested PARRY-capable image, use:

```sh
mini/host11-restore-parry.sh --restart
```

That script pins Lars Brinkhoff's `sailing-on-arpanet` restoration to commit
`c5e29a27a4dd8db03a8b2dbc79082f2612ae30ee`, backs up the current packs, restores
`SYS000.ckd`, `SYS001.ckd`, and `SYS002.ckd`, then restarts host `11`.

For UCLA-NMC host `1`, `host01-sigmactl.sh`:

- Builds SIMH Sigma from `src/linux-ncp/test/simh` if needed.
- Fetches public CP-V F00 RAD media from `kenrector/sigma-cpv-kit`.
- Starts a SIMH Sigma 7 using `mini/host01-sigma/f00rad.simh`.
- Exposes the CP-V mux on localhost TCP `4003` for the browser terminal route.
- Enables the first eight CP-V user lines during the automated boot sequence.
- Does not claim recovered UCLA-NMC SEX media and does not yet provide a working
  UCLA-NMC NCP/IMP attachment.

For MIT-MULTICS host `6`, `host06-multicsctl.sh`:

- Builds DPS8M from the pinned `R3.1.0` source if needed.
- Fetches public MR12.8 QuickStart media.
- Performs a one-time site setup creating the public `Iccc` account if the
  configured runtime disk is missing.
- Starts DPS8M with MR12.8 and exposes the HSLA terminal service on TCP `6180`.
- Does not claim recovered 1972 MIT H645 `Multics 17.6b` media.

## Host Port Map

| Host | Screen | Directory | Clean packs | IMP host port |
| --- | --- | --- | --- | --- |
| `70` | `host70` | `mini/host70` | `mini/host70/106` | UDP `21062` |
| `126` | `host126` | `mini/host126` | `mini/host126/126` | UDP `21622` |
| `134` | `host134` | `mini/host134` | `mini/host134/134` | UDP `22062` |
| `198` | `host198` | `mini/host198` | `mini/host198/306` | UDP `23062` |
| `11` | `host11` + `waitsconnect` | `mini/host11` | WAITS `SYS*.ckd` | UDP `20112` |
| `1` | `sigma01-cpv` | `mini/host01-sigma` | CP-V F00 RAD runtime | browser mux TCP `4003` |
| `6` | `host06-multics` | `mini/host06-multics` | MR12.8 `root.dsk` runtime | browser HSLA TCP `6180` |

Host `126` is HILTON-KA1 at the Washington Hilton conference-site IMP, not
MIT-ML. Its browser route uses terminal line `10015`.

Host `198` is MIT-ML at IMP `06`, host index `3`, octal `306`. It uses the
local `mini/host198/pdp10-ka` simulator binary with terminal line `19015` for
the browser route.

## Safety Rule

Do not restart these hosts with raw `screen -X quit` followed by `screen -dmS ...`. That can leave orphan PDP-10 simulators running and cause the next start to fail with `Address already in use` or `Host is not up`.

## Full Health Audit

Before changing runtime state, run the read-only full-system audit:

```sh
mini/arpanet-health.sh
```

The audit checks hosted ITS hosts, direct NCP reachability, browser relay sessions, stale `ncp-telnet` or local hosted terminal processes, IMP62/IMP41 sockets, and the PiDP-side screens when SSH is available. It reports `OK`, `WARN`, and `FAIL` without restarting or killing anything.

If the Pi cannot be reached from the current shell, skip only that portion with:

```sh
ARPANET_CHECK_PI=0 mini/arpanet-health.sh
```
