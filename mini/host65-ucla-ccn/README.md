# UCLA-CCN Host #65 Runtime

This directory contains the local runtime support for UCLA-CCN, ARPANET host
`#65` / octal `101`, attached to UCLA IMP `01`, host index `1`.

The implementation uses public OS/360 MVT 21.8f materials under Hercules as
the practical IBM 360 path. It is not recovered UCLA-CCN storage, and it must
not be described that way.

The visitor-facing plan is line-at-a-time:

- `@L 65` / `@L 101` reaches the UCLA-CCN front door.
- `HELP` and `BBOARD` are the documented CCN access-menu style commands.
- `TSO` hands the browser line-mode session to a real backend OS/360
  MVT/TCAM/TSO terminal through `s3270` control.
- The public FORTRAN path is real TSO foreground work: `EDIT` creates source,
  `ALLOC` connects compiler/runtime files, `CALL 'SYS1.LINKLIB(IEYFORT)'`
  invokes the installed FORTRAN IV G compiler, and `LOADGO` runs the object
  program. The public MVT image does not include UCLA's exact `FORTG`/`GOFORT`
  command processors; do not describe those as recovered.
- SPEAKEASY stays disabled until runnable SPEAKEASY software is recovered or
  legally obtained.

The Jay Maynard OS/360 turnkey MVT package documents TSO/TCAM through local
3270 devices in Hercules. Using `s3270` is acceptable as an operator/backend
validation tool; the public browser experience should remain line-mode.

## Current Validation State

Validated locally:

- The public OS/360 turnkey MVT archive downloads and extracts.
- Hercules starts with writable DASD after `host65-ucla-ccnctl.sh prepare`.
- The runtime config remaps Hercules operator ports away from shared defaults:
  `3271` for the Hercules 3270 console and `8651` for Hercules HTTP.
- The UCLA-CCN line-mode front door answers `HELP`, `BBOARD`, and `LOGOFF`.
- MVT IPL is automated through backend `s3270` on console device `00C0`.
- The host-specific MVT config uses `MAINSIZE 8`; MVT TSO logon fails with
  `IKJ56452I LOGON TERMINATED. SYSTEM ERROR` at the inherited 16 MB setting.
- The controller answers the MVT dump prompt with `R 00,'NO'`, then performs the
  documented first-IPL queue reply and job-queue reply.
- `INIT`, `WTR`, `RDR`, `TCAM`, and `TSO` are started from the live MVT console.
- `verify-tso` captures a real backend login transcript with `IKJ54012A ENTER
  LOGON -`, `LOGON IBMUSER`, `NO BROADCAST MESSAGES`, and `READY`.
- `verify-public-tso` proves the public line-mode bridge reaches real TSO.
- `verify-tso-fortran` proves a real interactive TSO compile/load/run path:
  source is saved as `H.FORT`, object output is written to `H.OBJ`, FORTRAN
  unit 6 is allocated to the terminal as `FT06F001`, and the loaded program
  prints `HELLO FORT`.
- `verify-card-reader` is a separate backend diagnostic for the virtual 2501
  reader. It is not part of the public visitor workflow.
- `host65-ucla-ccnctl.sh verify` requires the front door, public TSO bridge,
  and interactive TSO/FORTRAN validation.

Current rollout rule:

- Do not present UCLA-CCN as having a working public FORTRAN scenario unless
  `host65-ucla-ccnctl.sh verify-tso-fortran` or the full `verify` path passes.
  `runtime/FORTRAN_READY` represents real TSO/FORTRAN validation, not scripted
  text.

Operational notes:

- Do not create `runtime/TSO_READY` manually; it represents a real validated
  MVT/TCAM/TSO transcript.
- Do not create `runtime/FORTRAN_READY` manually; it represents a real
  interactive TSO/FORTRAN transcript.
- The backend 3270 client is only for operator setup/validation.
