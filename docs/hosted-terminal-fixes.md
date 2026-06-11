# Hosted Terminal Fixes

This document summarizes the ARPANET simulation work in this fork. It is separate from the physical PiDP-10 integration work, which lives in a companion repository.

## Scope

These changes belong to the ARPANET simulation and hosted terminal workflow:

- Repeated hosted terminal sessions should connect cleanly.
- `@L` and `@O` commands should route to the intended hosts.
- Session cleanup should avoid stale NCP TELNET state.
- Host banners should be interpreted correctly.

Physical PiDP-10 replica integration is documented separately:

- https://github.com/kurthamm/pidp10-arpanet-node

## User-facing behavior

From the hosted terminal page:

```text
@L 6
@L 70
@L 126
```

Expected behavior:

- `@L 6` reaches ARPANET host `006`.
- `@L 70` reaches ARPANET host `106` / octal `106` and identifies as `MIT Dynamic Modelling PDP-10`.
- `@L 126` reaches ARPANET host `176` / octal `176`.

Some hosts may display:

```text
Unknown ITS PDP-10
It's a lovely day to be a turist!
```

That greeting comes from ITS/TELSER for a generic ITS machine identity. It does not by itself prove incorrect routing. The stronger routing evidence is the `TELNET to host ...` line.

## Repeated connection cleanup

The hosted terminal must clean up the ITS/NCP session when a browser terminal disconnects. Otherwise later `@L` sessions can fail with symptoms such as:

```text
Open refused
```

or a stalled connection.

The fix is to close the local NCP TELNET process cleanly and allow ITS to release the server-side session.

## Testing

Recommended smoke tests from the hosted terminal:

```text
@L 6
```

Disconnect, reconnect, then:

```text
@L 70
```

Disconnect, reconnect, then:

```text
@L 126
```

The important check is that each session reaches a distinct host target and later sessions are not blocked by stale state from earlier sessions.

## External PiDP-10 host

This fork can also be used with an external PiDP-10 replica attached as host `41` / octal `051`, but that integration is intentionally documented outside this repository:

- https://github.com/kurthamm/pidp10-arpanet-node

Keep site-specific PiDP-10/Tailscale/IMP41 configuration out of this repository unless it becomes a generic upstream-supported scenario.
