# Stanford/SU-AI PARRY Restoration

Host `11` / octal `013` is Stanford/SU-AI, the WAITS system used by the 1972
ICCC scenario booklet for PARRY.

## What Was Restored

The live WAITS image already contained `PARRY.DMP[1,3]`, but running `R PARRY`
failed because the support files PARRY opens at runtime were missing. The
missing files were restored from Lars Brinkhoff's WAITS/PARRY restoration:

```text
https://github.com/larsbrinkhoff/sailing-on-arpanet
commit c5e29a27a4dd8db03a8b2dbc79082f2612ae30ee
```

The required runtime files are present in that restoration as part of the
restored `SYS000.ckd`, `SYS001.ckd`, and `SYS002.ckd` packs.

## Reproduce The Restoration

From the repository root:

```sh
mini/host11-restore-parry.sh --restart
```

The script:

- Pins the restoration source to the commit above.
- Backs up current `mini/host11/SYS*.ckd` packs under
  `$HOME/arpanet-runtime-backups/host11-before-parry-<timestamp>`.
- Extracts the restored WAITS packs.
- Restarts host `11` only when `--restart` is supplied.

Without `--restart`, host `11` must already be stopped. This prevents replacing
disk packs underneath a running WAITS simulator.

## Visitor Scenario

Use the 2026 scenario entry:

```text
SCENARIO 19: SAIL PARRY === HOST #11
```

Minimal live test:

```text
@L 11
1,REG
R PARRY
N
MILD
N
N
HELLO.
PAT SMITH
BYE.
```

After `BYE.`, PARRY may print its emotion variables and report
`P.DMP NOT FOUND`. The conversation has already completed; use Ctrl-C if needed
to return to the WAITS executive prompt.
