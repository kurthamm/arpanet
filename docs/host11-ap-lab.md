# Host 11 AP/APE Restoration Lab

This is a private Stanford/SU-AI WAITS lab for testing the 1972 ICCC
`SAIL AP Hotline === HOST #11` scenario without touching the live host 11
disk packs or the working PARRY scenario.

## Safety rule

Do not restore AP files directly into `mini/host11/`.

Use `mini/host11-ap-labctl.sh prepare` to clone the current host 11 packs into
the ignored `mini/host11-ap-lab/` workspace, then test there first.  The lab
does not start `waitsconnect`, does not bind the public ARPANET host 11 route,
and uses private terminal ports only.

## Controller

```sh
mini/host11-ap-labctl.sh prepare
mini/host11-ap-labctl.sh start
mini/host11-ap-labctl.sh verify-parry
mini/host11-ap-labctl.sh verify-ap
mini/host11-ap-labctl.sh stop
```

Private ports:

- Console: `1125`
- WAITS DCS lines: `2140`-`2143`

## Current verified state

Verified in the lab clone:

- The live host 11 packs are copied into an isolated ignored workspace.
- The private WAITS simulator boots.
- `verify-parry` launches real PARRY from the lab clone and sees the Stanford
  WAITS job banner.
- Live `@L 11` remains separate and untouched.

Not yet validated:

- The AP Hotline / APE scenario is not ready for the public 2026 scenario list.
- `verify-ap` currently reaches real WAITS and `R HOT` starts far enough to ask
  for `Project and Programmer name`, but the full `HOT` and `APE` flow has not
  been validated.

## Evidence lead

SAILDART has AP system material under `[AP,SYS]`, including `APE.DMP`, `APMESS`,
`DICT`, `HOT` sources, `INDEX`, `LINKS`, `NEWS`, and `WORDS`.  The next
restoration step is to load those real files into the lab packs, re-run
`verify-parry`, and only then attempt a full `verify-ap`.

No public host card or 2026 scenario should be added for AP/APE until both
checks pass in the lab.
