# Repository Split

The work is split into two public repositories for maintainability.

## ARPANET fork

Repository:

```text
https://github.com/kurthamm/arpanet
```

Purpose:

- Hosted ARPANET simulation fixes.
- Web terminal scenario behavior.
- General routing/session cleanup work.
- Upstream-friendly changes that could become pull requests to `obsolescence/arpanet`.

## PiDP-10 companion repository

Repository:

```text
https://github.com/kurthamm/pidp10-arpanet-node
```

Purpose:

- Physical PiDP-10 replica integration.
- Pi-side IMP41 configuration.
- Tailscale or overlay-network setup notes.
- ARPA51 ITS boot profile and validation.

## Why this split matters

The ARPANET simulation is a general project. A home PiDP-10 integration is a hardware deployment. Keeping them separate lets upstream maintainers review general fixes without inheriting site-specific Pi configuration.
