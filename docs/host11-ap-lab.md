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

Completed AP/APE test result:

- The AP Hotline / APE scenario is not ready for the public 2026 scenario list.
- In the private direct-DCS lab, `R HOT` and `R APE` start far enough to ask
  for `Project and Programmer name`, but the lab cannot use `1,REG` as a remote
  login there: WAITS reports `Remote login prohibited for that account`.
- Existing public-path transcripts from the real `@L 11` route show that after
  logging in as `1,REG`, `HOT.DMP[1,2]` exists and starts, but reports
  `SORRY -- CANNOT RUN HOT LINE NOW. HOT LINE IS DOWN.`
- Existing public-path transcripts also show that `APE.DMP[1,3]` exists and
  starts, but a query reaches `SUPER HORRENDOUS ERROR #8` instead of returning
  the 1972 booklet's AP news database results.

Conclusion: AP/APE software is present in part, but the 1972 AP Hotline
scenario is not currently runnable.  Do not add it to the 2026 scenarios until
the AP news feed/database support files are restored and `verify-ap` reaches
real `HOT` output or APE's `KEYWORD EXPRESSION:` query flow.

## Evidence lead

SAILDART has AP system material under `[AP,SYS]`, including `APE.DMP`, `APMESS`,
`DICT`, `HOT` sources, `INDEX`, `LINKS`, `NEWS`, and `WORDS`.  The next
restoration step is to load those real files into the lab packs, re-run
`verify-parry`, and only then attempt a full `verify-ap`.

No public host card or 2026 scenario should be added for AP/APE until both
checks pass in the lab.
