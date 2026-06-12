# Hosted Host Lifecycle

Use `mini/hostctl.sh` to manage the hosted ITS PDP-10 hosts (`6`, `70`, and `126`).
Use `mini/host11ctl.sh` to manage Stanford/SU-AI host `11`, which is a separate
WAITS/SAIL lane and is not part of the MIT ITS trio.

The older `mini/host06.sh`, `mini/host70.sh`, and `mini/host126.sh` entrypoints are now compatibility shims around `hostctl.sh`. Use `hostctl.sh` for operational work.

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
```

Valid host targets are `6`, `70`, `126`, or `all`.
For `host11ctl.sh`, the only valid host target is `11`.

## What The Tool Guarantees

- Stops the named `screen` session.
- Finds PDP-10 simulator owners of that host's terminal and IMP ports.
- Terminates the owning process group, not just the screen wrapper.
- Waits for that host's ports to clear before starting.
- Refuses to start if ports are still owned.
- Restores clean `rp03.*` packs from the tracked host subdirectory before start.
- Backs up previous mutable packs under `$HOME/arpanet-runtime-backups`.
- Verifies the host with `NCP=ncp31 ./ncp-ping` after restart.

For Stanford/SU-AI, `host11ctl.sh`:

- Manages the `host11` WAITS SIMH screen and the `waitsconnect` bridge screen.
- Builds `mini/src/waits-ncpd/waitsconnect` when the source is newer than the binary.
- Downloads the WAITS archive only if required disk files are missing.
- Backs up `SYS000.ckd`, `SYS001.ckd`, and `SYS002.ckd` once under
  `$HOME/arpanet-runtime-backups/host11-initial`.
- Owns only the Stanford ports: TCP `1025`, TCP `2040-2043`, and UDP `20112`.
- Verifies host `11` with `NCP=ncp16 ./ncp-ping`, because the live Stanford
  NCP echo path answers from AMES NCP16 and does not answer from CCA NCP31.

## Host Port Map

| Host | Screen | Directory | Clean packs | IMP host port |
| --- | --- | --- | --- | --- |
| `6` | `host06` | `mini/host06` | `mini/host06/006` | UDP `20062` |
| `70` | `host70` | `mini/host70` | `mini/host70/106` | UDP `21062` |
| `126` | `host126` | `mini/host126` | `mini/host126/126` | UDP `21622` |
| `11` | `host11` + `waitsconnect` | `mini/host11` | WAITS `SYS*.ckd` | UDP `20112` |

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
