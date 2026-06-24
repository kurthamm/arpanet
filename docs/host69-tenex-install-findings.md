# BBN-TENEX Host #69 — Install Bring-Up Findings

Working log of everything learned while trying to drive the Lars Brinkhoff
`build-tenex` SYSLOD install to a reproducible, logged-in TENEX on the
rcornwell `pdp10-ki` simulator. Updated 2026-06-22.

Scope: this is the *private lab only*. `@L 69` stays disabled until a real
login transcript exists. Nothing here enables a public route.

## Goal

Drive `build-tenex/install` from media to a booted TENEX with EXEC installed,
a working login, and basic commands (SYSTAT/DIR/LOGOUT) — reproducibly — then
make a fast "boot the installed disk" path and wire it into
`host69-bbn-tenexctl.sh`.

## What reliably works (proven, repeatable)

- **Boot to `TENEX IN OPERATION`** via the controller gate
  `./mini/host69-bbn-tenexctl.sh verify-build-tenex-syslod-boot`.
  Confirmed twice (`controller rc=0`), console shows:
  `SYSLOD$G → CLOBBER? Y → TENEX RESTARTING, WAIT... NO CHECKDSK →
  TENEX IN OPERATION → NO EXEC → .INIT BIT TABLE. → READ BADSPOTS ... [Confirm]`.
  This path uses SIMH's own `expect`/`send` and a **file-redirected** console
  (`pdp10-ki simh.do > out 2>&1`), DC/TYM on ports 16945/16946.
- The boot still prints `*****BUGCHK ... FAILED TO GTJFN/OPEN BUGTABLE FILE`
  and `NO EXEC` — i.e. it reaches the monitor but EXEC/BUGTABLE are not yet on
  the disk. Installing them is the remaining work.

## Root causes found (with evidence)

### 1. `SYSLOD<ESC>G` typed via pexpect only rings DDT's bell
Typing the DDT go-command directly into the console after `go 100` does not
start SYSLOD (bell only). SIMH's own `expect "\n" ... ; send "SYSLOD\033G"`
injection *during* `go 100` is reliable. **Let the SIMH do-file own that
keystroke.**

### 2. Answering the CLOBBER prompt via pexpect wedges the monitor
A/B proven: with the disk-init driven by SIMH `expect ... send "Y"; continue`,
the monitor boots cleanly to `TENEX IN OPERATION`. With the same do-file but the
clobber answered by pexpect on a free-running console, the monitor sticks in
`TENEX RESTARTING, WAIT...` forever. **The SYSLOD disk dialogue must be SIMH-
driven, not pexpect-driven.**

### 3. An interactive PTY console wedges the re-init; a file-redirect console does not
Same do-file, same binary, same disks:
- `pdp10-ki simh.do > file 2>&1` (file redirect) → reaches `TENEX IN OPERATION`.
- pexpect spawn (PTY console) → sticks at `TENEX RESTARTING, WAIT...`.
So the boot/install must run with the console redirected to a **file**, not a
PTY. (The manual foreground console a human used is also a tty and reportedly
got further, so the exact PTY trigger isn't fully characterized — but the
file-redirect path is the one that demonstrably works here.)

### 4. SIMH `expect` rules must be registered in PHASES, not all before one `go`
SIMH `expect` rules are one-shot and **all active rules are matched against
console output while the CPU runs**. If the EXEC-install rules (`\n.`,
`[Confirm]`, `\n!`, ...) are registered before the disk-init `go 100`, their
patterns match disk-init output and inject stray keystrokes that wedge the
re-init. Lars's canonical `simh/syslod.do` avoids this by phasing: register
disk-init rules → `go` (a no-`continue` expect stops the CPU) → register the
EXEC-install rules → bare `continue` resumes. Each phase only has its own rules
live. Replicate that structure exactly.

### 5. MONITORING PITFALL: `pgrep -f pdp10-ki` matches the `timeout` wrapper
Running under `timeout 2400 pdp10-ki ...` creates a parent `timeout` process
whose command line *contains* "pdp10-ki". `pgrep -f 'pdp10-ki' | head -1`
returns that parent, which sleeps in `wchan=do_wait` at 0% CPU. Reading its
stats produced repeated **false "0% CPU / hung" conclusions** and drove
premature kills. **Always select the real sim with `pgrep -x pdp10-ki`** (exact
comm match). Confirmed: the real sim was state `R`, ~36 ticks/s = computing,
while the wrapper showed 0%.

### 6. File-redirected console output is BLOCK-buffered → stale view
With stdout to a file, libc block-buffers the console, so the transcript (and
any `tail -f`) lags far behind reality and looks "stuck." Mitigations:
- `stdbuf -oL -eL pdp10-ki ...` forces line buffering → real-time transcript.
- Tap the DC/TYM TCP lines (`nc 127.0.0.1 <port>`) for the true, unbuffered
  console-2 state. This is how the controller detects `TENEX IN OPERATION`.

### 7. Disk-image sizing matters, but is not the whole story
- All-zero (`: > tenexN.rp03`, 0 bytes) disk images: the re-init spins (no disk
  I/O, CPU burning) and never reaches `TENEX IN OPERATION`.
- A run that leaves at least one drive sized (e.g. `tenex6.rp03` ~49 MB) was the
  state on which the controller boot **succeeded**.
- HOWEVER: re-running the full install on that same sized-`tenex6` shape still
  spun at `NO CHECKDSK`, so sizing alone does not explain the controller-vs-
  full-install difference. **Open question.**

## Decisive open problem (next to solve)

`full-install.do` (file-redirect, phased, ports 12345/12346) **spins at the
re-init** (`NO CHECKDSK`, CPU computing, no disk I/O, never reaches
`TENEX IN OPERATION`), while the controller's `verify-build-tenex-syslod-boot`
(file-redirect, ports 16945/16946, regenerated `build-tenex-syslod.do`) reaches
`TENEX IN OPERATION` on the same disk shape. During the re-init the only active
difference is the hardware include (ports) — DC/TYM bound fine (confirmed
listening), so ports per se look innocent.

Candidate differences not yet ruled out:
- The controller runs `verify_build_tenex_media` (rebuilds `syslod.dta` /
  `system.tap`) immediately before booting; `full-install.do` reuses existing
  media.
- Disk-image *content* left by the prior partial run may differ from the
  content the controller booted on.
- The controller invokes `pdp10-ki simh.do > out &` directly; `full-install.do`
  runs under `timeout ... stdbuf ...`.

Recommended next experiment: take the EXACT do-file the controller generates
(`runtime/build-tenex-syslod.do`, which is proven to reach `TENEX IN
OPERATION`), append the phase-2/3 EXEC-install rules to it verbatim, and run it
the controller's way (no `timeout`, regenerate media first). That isolates the
boot to a byte-identical known-good prefix and tests only the appended install
rules.

## The proven manual EXEC-install dialogue (what to automate after boot)

From the prior hand-driven session (recorded in
`docs/host69-bbn-tenex-plan.md`). At the no-EXEC mini-exec `.` prompt:
```
.G                       ; GET FILE
DTA0:EXEC.SAV [Confirm]  ; <return>
.S                       ; START — NOTE: "START" + <return> gives "?";
.START.                  ; the trailing "." is what executes it
 SUMEX-AIM Tenex 1.31.82, SUMEX-AIM EXEC 1.51
 ENTER DATE AND TIME AS MM/DD/YY HH:MM -- 06/21/26 12:00:00
@ENABLE
!MOUNT DTA0:
!GET DTA0:EXEC.SAV
!SSAVE 0 777 EXEC.SAV          [New file] <return>
!RUN DTA0:DLUSER.SAV  → DUMP OR LOAD? L → FILE: DTA0:USERS.TXT → [Old file] <ret> → DONE.
!GET DTA0:DUMPER.SAV
!SSAVE 0 777 <SUBSYS>DUMPER.SAV  [New file] <return>
```
Accounts in `install/boot/users.txt`: `PMFDIR0`, `SUBSYS`, `OPERATOR`
(password `OPERATOR`). BUGTABLE/BUGSTRINGS and the full subsystem set live on
`system.tap` and would be restored with DUMPER to clear the BUGCHK and populate
`<SYSTEM>`/`<SUBSYS>`.

## Environment constraints (explain the slowness)

- Host is **2 cores at load ~12** — six PDP-10 sims share it (host69 plus the
  five live ARPANET hosts host70/126/134/11/198). The host69 sim runs at
  **nice 10** (deprioritized) and gets ~20–40% CPU, so the disk re-init that
  takes ~200 s on the controller can take many minutes here.
- Non-root: cannot raise the sim's priority. Do **not** deprioritize/pause the
  live hosts without the operator's say-so.
- Pacing: send keystrokes teletype-slow if ever driving the console by hand/
  pexpect (~60 ms/char, extra after ESC).

## Discipline (lesson learned the hard way)

Do **not** kill a run for being "slow." Kill only on positive hang evidence:
real sim (`pgrep -x pdp10-ki`) at ~0% CPU **and** flat `/proc/<pid>/io`
`write_bytes` **and** no DC/TYM output, sustained. Otherwise wait — the box is
just overloaded.

## Artifacts created

- `mini/host69-bbn-tenex/drive-tenex.py` — pexpect driver (install/run/full).
  Superseded for the boot/install by the file-redirect path because of finding
  #3, but documents the slow-send + phased approach.
- `mini/host69-bbn-tenex/full-install.do` — single phased SIMH expect script for
  the full unattended install (disk-init + EXEC/users/DUMPER). Boots reliably
  in theory but currently hits the open re-init spin above; see next experiment.
- Reliable boot today: `host69-bbn-tenexctl.sh verify-build-tenex-syslod-boot`.

## Useful commands

```sh
# Reliable boot to TENEX IN OPERATION (proven):
BUILD_TENEX_BOOT_WAIT_SECS=200 ./mini/host69-bbn-tenexctl.sh verify-build-tenex-syslod-boot

# Find the REAL sim (not the timeout wrapper):
pgrep -x pdp10-ki

# Is it computing? (delta > 0 over the interval)
awk '{print $14+$15}' /proc/$(pgrep -x pdp10-ki)/stat   # sample twice

# Is it doing disk I/O? (write_bytes climbing = formatting/writing)
grep write_bytes /proc/$(pgrep -x pdp10-ki)/io

# Real-time console-2 state (unbuffered):
nc 127.0.0.1 16945     # DC   (controller ports)
nc 127.0.0.1 16946     # TYM
```
