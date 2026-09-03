# MIT Multics — Host #6

Real **Multics MR12.8** running under the **DPS8M** simulator. This is an authentic Multics
OS using public release media; it is **not** recovered MIT-Multics storage and must not be
described that way.

Current implementation:
- Emulator: **DPS8M** (`gitlab.com/dps8m/dps8m`, tag `R3.1.0`), fetched/built by
  `../host06-multicsctl.sh`.
- OS / media: **MR12.8 QuickStart** (`QuickStart_MR12.8.zip`).
- Terminal path: DPS8M HSLA console on **TCP 6180** (the ctl script verifies the
  `Multics MR12.8: MIT Project MAC Multics` salutation there).
- Visitor path: `@L 6` reaches Multics **through the web terminal / TCP-6180 bridge** —
  this is a **terminal/front-door bridge, not a native ARPANET NCP attach.** Multics does not
  (yet) speak its own NCP on IMP #6; native-NCP integration is future work.
- Lifecycle: managed by `../host06-multicsctl.sh` (`prepare` / `start` / `stop` / `verify`),
  driven in order by `../arpanet-recover.sh`.

Note: upstream `obsolescence/arpanet` had **no Multics** — its `host06` dir is MIT *ITS*.
Multics (#6) is one of the machines we added (it was only a "longer-term hope" upstream).

See the project journal index `docs/journal/README.md` for how this fits the host roster and
the native-NCP vs bridge authenticity classification.
