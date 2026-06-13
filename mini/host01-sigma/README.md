# Host 01 Sigma Workspace

This workspace is for a real SDS/XDS Sigma 7 emulator path using SIMH Sigma and
public CP-V kit media. It is not a Python service and it does not invent host
behavior.

Current implementation:

- CPU/emulator: SIMH Sigma, built from `src/linux-ncp/test/simh`.
- OS/media: CP-V F00 RAD system from `kenrector/sigma-cpv-kit`.
- Terminal path: SIMH COC/mux TCP port `4003`.
- Public browser path: `@L 1` / `@L 001` through `mini/local-host-terminal.py`.
- ARPANET status: not attached to IMP #1 as a working NCP host yet.
- Visitor capacity: eight usable CP-V terminal lines are exposed. The bridge
  closes line 8 and above with a busy message instead of leaving visitors on a
  non-login terminal line.
- Visitor scenarios: CP-V BASIC `BA:TREK` and CP-V `ADV` are real programs
  present in the live CP-V environment. They are documented in the 2026 scenario
  tab as supplemental host #1 experiences, not as recovered UCLA-NMC/SEX
  software.

Use:

```sh
mini/host01-sigma/host01-sigmactl.sh prepare
mini/host01-sigma/host01-sigmactl.sh start
mini/host01-sigma/host01-sigmactl.sh status
mini/host01-sigma/host01-sigmactl.sh console
mini/host01-sigma/host01-sigmactl.sh stop
```

The CP-V kit documentation says F00 terminals are non-hardwired and present a
logon salutation on connection after the operator enables timesharing users. If
the system is up but users cannot log on, attach to the simulator console and
use the CP-V operator interface to enable online users, for example `ON 107`.

This path is a browser terminal route to the real SIMH Sigma/CP-V mux. It is
not yet a working UCLA-NMC NCP/IMP host attachment.

Historical boundary: UCLA-NMC was host #1 on IMP #1 and ran UCLA SEX on an
SDS/XDS Sigma 7. No original UCLA-NMC/SEX disk or tape image is currently
present here. This workspace preserves the historically correct machine class
and address slot while using recovered public CP-V media.
