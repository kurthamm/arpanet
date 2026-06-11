# Hosted ITS Host Lifecycle

Use `mini/hostctl.sh` to manage the hosted ITS PDP-10 hosts (`6`, `70`, and `126`).

The older `mini/host06.sh`, `mini/host70.sh`, and `mini/host126.sh` scripts only start screens. They do not prove that old simulator children exited, so they can leave orphan `pdp10-ka-fixed` processes holding terminal and IMP ports. Use `hostctl.sh` for operational work.

## Commands

From the repository root:

```sh
mini/hostctl.sh status all
mini/hostctl.sh verify all
mini/hostctl.sh restart 70
mini/hostctl.sh stop 70
mini/hostctl.sh start 70
```

Valid host targets are `6`, `70`, `126`, or `all`.

## What The Tool Guarantees

- Stops the named `screen` session.
- Finds PDP-10 simulator owners of that host's terminal and IMP ports.
- Terminates the owning process group, not just the screen wrapper.
- Waits for that host's ports to clear before starting.
- Refuses to start if ports are still owned.
- Restores clean `rp03.*` packs from the tracked host subdirectory before start.
- Backs up previous mutable packs under `$HOME/arpanet-runtime-backups`.
- Verifies the host with `NCP=ncp31 ./ncp-ping` after restart.

## Host Port Map

| Host | Screen | Directory | Clean packs | IMP host port |
| --- | --- | --- | --- | --- |
| `6` | `host06` | `mini/host06` | `mini/host06/006` | UDP `20062` |
| `70` | `host70` | `mini/host70` | `mini/host70/106` | UDP `21062` |
| `126` | `host126` | `mini/host126` | `mini/host126/126` | UDP `21622` |

## Safety Rule

Do not restart these hosts with raw `screen -X quit` followed by `screen -dmS ...`. That can leave orphan PDP-10 simulators running and cause the next start to fail with `Address already in use` or `Host is not up`.
