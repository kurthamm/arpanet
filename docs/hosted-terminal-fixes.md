# Hosted Terminal Operation

This fork supports the hosted browser terminal for the ARPANET simulation and, when configured locally, an external PiDP-10 host at ARPANET host `41` / octal `051`.

## Browser Commands

Use the hosted terminal page and type one of these commands at the TIP prompt:

```text
@L 6
@L 70
@L 126
@L 41
```

Expected routing:

| Command | Target | Notes |
| --- | --- | --- |
| `@L 6` | host `006` | MIT ITS host. |
| `@L 70` | host `106` | MIT Dynamic Modelling PDP-10; uses old TELNET mode automatically. |
| `@L 126` | host `176` | ITS host. |
| `@L 41` | host `051` | External PiDP-10, if the site-local IMP41 link is configured. |
| `@L 051` | host `051` | Accepted spelling for the same PiDP-10 host. |

Some ITS hosts may display `Unknown ITS PDP-10` and `It's a lovely day to be a turist!`. That text is an ITS/TELSER banner and does not by itself indicate wrong routing. Use the `TELNET to host ...` line and NCP tests for routing verification.

## PiDP-10 Host 41 Routing

The browser launcher treats host `41` specially:

- `@L 41` and `@L 051` are routed through source NCP `ncp31`.
- `41` / `051` use old TELNET mode (`-o`) automatically.
- Users should not need to type `@O 41` for the hosted page.

The site-local IMP41 link is intentionally not committed as a generic upstream setting. Keep deployment-specific IMP41/Tailscale details in the companion repository:

```text
https://github.com/kurthamm/pidp10-arpanet-node
```

## Direct Validation

From `mini/`, verify the hosted hosts and PiDP host path:

```sh
NCP=ncp31 ./ncp-ping -c1 6
NCP=ncp31 ./ncp-ping -c1 70
NCP=ncp31 ./ncp-ping -c1 126
NCP=ncp31 ./ncp-ping -c1 41
```

Check the launcher path without using the browser:

```sh
printf '@L 41\r\n' | SESSION_NUMBER=0 ../do.sh
printf '@L 051\r\n' | SESSION_NUMBER=0 ../do.sh
```

Both commands should attempt `TELNET to host 051.`

## Relay Session Diagnostics

If the hosted browser terminal hangs after an `@L` command, check relay-owned TELNET children before restarting hosts or IMPs:

```sh
ps -eo pid,ppid,pgid,sid,stat,args | grep '[n]cp-telnet'
pgrep -af simh_server.py
```

A stale `ncp-telnet` whose parent is the running `simh_server.py` belongs to the browser relay. Clean that relay session/process group; do not restart hosted ITS hosts unless direct `ncp-ping` fails.

## Hosted Host Operations

Use `mini/hostctl.sh` for hosted ITS hosts `6`, `70`, and `126`:

```sh
mini/hostctl.sh status all
mini/hostctl.sh verify all
mini/hostctl.sh restart 70
```

Do not use raw `screen -X quit` plus manual `screen -dmS` for these hosts. See `docs/host-lifecycle.md`.
