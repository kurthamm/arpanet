# Hosted Terminal Operation

This fork supports the hosted browser terminal for the ARPANET simulation, Stanford/SU-AI host `11` / octal `013`, and, when configured locally, an external PiDP-10 host at ARPANET host `41` / octal `051`.

## Browser Commands

Use the hosted terminal page and type one of these commands at the TIP prompt:

```text
@L 6
@L 70
@L 126
@L 11
@L 41
```

Expected routing:

| Command | Target | Notes |
| --- | --- | --- |
| `@L 6` | host `006` | Hosted MIT ITS simulator, reached through a localhost-only simulator terminal line. |
| `@L 70` | host `106` | Hosted MIT Dynamic Modelling PDP-10, reached through a localhost-only simulator terminal line. |
| `@L 126` | host `176` | Hosted ITS simulator, reached through a localhost-only simulator terminal line. |
| `@L 11` | host `013` | Hosted Stanford/SU-AI WAITS PDP-10, reached through a localhost-only WAITS DCS terminal line. |
| `@L 013` | host `013` | Accepted octal spelling for the same Stanford host. |
| `@L 41` | host `051` | External PiDP-10, reached through its Pi-side SIMH terminal line over Tailscale. |
| `@L 051` | host `051` | Accepted spelling for the same PiDP-10 host. |

Some ITS hosts may display `Unknown ITS PDP-10` and `It's a lovely day to be a turist!`. That text is an ITS/TELSER banner and does not by itself indicate wrong routing. Use the `TELNET to host ...` line and NCP tests for routing verification.

## Hosted Browser Routing

The browser terminal path is intentionally separate from the ARPANET health path:

- `@L 6`, `@L 70`, and `@L 126` run `mini/local-host-terminal.py` and connect to localhost-only SIMH terminal lines (`16015`, `17015`, and `10015`).
- `@L 11` and `@L 013` run `mini/local-host-terminal.py` against the Stanford WAITS DCS line on `2040`.
- `@L 41` and `@L 051` use the same helper to connect to the PiDP-10 MTY line at the Pi's Tailscale address.
- This does not open public emulator ports; the browser still reaches the relay only through Cloudflare Tunnel.
- ARPANET connectivity for the MIT hosts and PiDP host is validated with `NCP=ncp31 ./ncp-ping`. Stanford/SU-AI is validated with `NCP=ncp16 ./ncp-ping`.

This split keeps the hosted machines usable while preserving NCP reachability checks separately. In the DigitalOcean runtime, `ncp31` is the only reliable application NCP source, and the MIT hosted images may reject ARPANET TELNET from host `037` even while NCP echo works.

## PiDP-10 Host 41 Routing

The browser launcher treats host `41` specially:

- `@L 41` and `@L 051` route to host label `051`.
- The relay attaches to the PiDP-10 SIMH MTY line over Tailscale.
- Users should not need to type `@O 41` for the hosted page.

The site-local IMP41 link is intentionally not committed as a generic upstream setting. Keep deployment-specific IMP41/Tailscale details in the companion repository:

```text
https://github.com/kurthamm/pidp10-arpanet-node
```

On the DigitalOcean droplet, the main fork will also honor an ignored local override file:

```text
mini/imp62.local.simh
```

That keeps the PiDP/Tailscale wiring out of the tracked `imp62.simh` while still allowing the live deployment to enable host `41` when the local file exists.

## Direct Validation

From `mini/`, verify the hosted hosts and PiDP host path:

```sh
NCP=ncp31 ./ncp-ping -c1 6
NCP=ncp31 ./ncp-ping -c1 70
NCP=ncp31 ./ncp-ping -c1 126
NCP=ncp31 ./ncp-ping -c1 41
NCP=ncp16 ./ncp-ping -c1 11
```

Check the launcher path without using the browser for the localhost and PiDP terminal-line routes:

```sh
printf '@L 6\r\n' | SESSION_NUMBER=0 ../do.sh
printf '@L 70\r\n' | SESSION_NUMBER=0 ../do.sh
printf '@L 126\r\n' | SESSION_NUMBER=0 ../do.sh
printf '@L 41\r\n' | SESSION_NUMBER=0 ../do.sh
printf '@L 051\r\n' | SESSION_NUMBER=0 ../do.sh
```

Those commands should print the matching `TELNET to host ...` line and a banner from the target simulator terminal.

For Stanford, keep the test process open long enough for WAITS to print the DCS line prompt. A simple pipe closes stdin immediately and can make a healthy session appear to drop:

```sh
printf '@L 11\r\n' | SESSION_NUMBER=0 ../do.sh
```

## Relay Session Diagnostics

If the hosted browser terminal hangs after an `@L` command, check relay-owned TELNET children before restarting hosts or IMPs:

```sh
ps -eo pid,ppid,pgid,sid,stat,args | grep '[n]cp-telnet'
ps -eo pid,ppid,pgid,sid,stat,args | grep '[l]ocal-host-terminal'
pgrep -af simh_server.py
```

A stale `ncp-telnet` or `local-host-terminal.py` whose parent is the running `simh_server.py` belongs to the browser relay. Clean that relay session/process group; do not restart hosted ITS hosts unless direct `ncp-ping` fails.

## Hosted Host Operations

Use `mini/hostctl.sh` for hosted ITS hosts `6`, `70`, and `126`:

```sh
mini/hostctl.sh status all
mini/hostctl.sh verify all
mini/hostctl.sh restart 70
```

Do not use raw `screen -X quit` plus manual `screen -dmS` for these hosts. See `docs/host-lifecycle.md`.

Use `mini/host11ctl.sh` for Stanford/SU-AI host `11`:

```sh
mini/host11ctl.sh status 11
mini/host11ctl.sh verify 11
mini/host11ctl.sh restart 11
```
