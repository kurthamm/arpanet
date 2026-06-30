# Changelog

## 2026-06-09

### Fixed: IMP host interface IPv4/IPv6 mismatch (silent connection failure)

**Problem:** NCP daemons (`ncpdov`) bind to IPv4 (`0.0.0.0`). On this system,
`localhost` resolves to `::1` (IPv6). The `attach -u hi*` lines in 18 IMP
`.simh` configs used `localhost` as the target address, causing the IMP host
interface to close immediately with `HI - UNRECOVERABLE I/O ERROR`. NCP
connections appeared to send but the packet never left the source IMP.

**Fix:** Changed `localhost` → `127.0.0.1` in `attach -u hi*` lines in all
NCP-backed IMP configs: `imp01`, `imp02`, `imp03`, `imp04`, `imp07`, `imp08`,
`imp09`, `imp10`, `imp12`, `imp13`, `imp14`, `imp16`, `imp19`, `imp23`,
`imp28`, `imp31`, `imp32`, `imp35`.

Note: `imp06.simh` (MIT IMP 6) was left unchanged — MIT hosts (70, 134, 198)
run ITS with its own internal NCP stack and connect via a separate mechanism.

### Fixed: `@O` command in do.sh / dotelnet.sh ignored `-o` (old Telnet) flag

**Problem:** `do.sh` parsed `@O <host>` but did not distinguish it from `@L`.
`dotelnet.sh` never received the command type, so `ncp-telnet` always opened
new Telnet (socket 23) even when the user typed `@O`.

**Fix:** `do.sh` now captures the command letter (`@L` vs `@O`) and passes it
as a 4th argument to `dotelnet.sh`. `dotelnet.sh` passes `-o` to `ncp-telnet`
when the command is `O` or `o`, selecting old Telnet socket 1.

### Removed: systemd service installed outside the project directory

`/etc/systemd/system/arpanet.service` and its `multi-user.target.wants`
symlink were removed. The service was set to auto-start on boot. All arpanet
processes must now be started manually via `./mini/arpanet start` or the
individual host scripts.

---

## Current status (2026-06-09)

**What works:**
- ARPANET IMP routing: all 36 IMP simulators route correctly after IPv4 fix.
- NCP connections from non-MIT hosts reach MIT IMP 6 and get RFNM + RRP.
- `@O` now correctly selects old Telnet socket 1.

**Remaining blocker:**
- ITS on hosts 70, 134, and 198 does not answer NCP Telnet RFCs on socket 23
  (new Telnet) or socket 1 (old Telnet). Connections reach MIT IMP 6, get
  delivered to ITS, but ITS sends CLS ("Open refused").
- Root cause is inside ITS: the TELSER/NCP service listener is not accepting
  incoming RFC requests. This requires investigation of the ITS kernel NCP
  configuration — specifically why `NUJBST` (which loads `SYS;ATSIGN NETRFC`)
  fails, or whether the ITS build for these hosts has Telnet service enabled.

**All processes stopped. No external services running.**

---

## 2026-06-10

### Fixed: ITS kernel panic-halt on first NCP connection (Chaosnet device missing)

**Problem:** KA ITS 1652 (hosts 06, 70, 126, 134, 198) is built with
`CH10P==1` (Chaosnet interface at device 0470) and `NLPTP==1` (ODEC printer
at 0464). The `mini-run` configs disable Chaosnet (`set ch dis`). When the
first NCP connection opens, the kernel's PI-1 device poll loop reads the
missing device, gets a floating status (600777), and executes a deliberate
`JRST 4,` panic: `HALT instruction, PC: 172104`. Reproducible with
`:TELNET 176` from a local terminal.

**Fix:** In `mini/host126/mini-run`: `set ch dis` → `set ch enabled` +
`set ch node=177002`. Verified: no more halts on connection open. The same
change applies to the other ITS hosts' mini-run files (06, 70, 134, 198).

### Isolated (not yet fixed): incoming NCP telnet RFC never spawns TELSER

Traced with kernel symbol table extracted from `@ ITS` on disk
(rp03.2, squoze pairs) and SIMH memory examination:

- Incoming RTS reaches kernel `IMPRFQ` (060322) with correct values
  (local socket 23 = new Telnet, `NETUSW`=0 = logins allowed).
- Kernel correctly queues a demon-start request `-1,,NTRFCL` (start
  `SYS;ATSIGN NETRFC`) in the `UTTYS` ring buffer.
- The ring entry is NEVER consumed: `UTTYCT` stays 1, `UTTYO` parked.
  `USTART` (the consumer, called from the slow clock behind `TREESW`,
  which is -1 = unlocked) fails or is never reached.
- Side effect: once an entry is stuck, `^Z` console logins also stop
  working (same ring) — terminals appear dead after network activity.
- The on-disk server chain is complete and correct:
  `SYS;ATSIGN NETRFC` → `DEVICE;LBSIGN RFC027` → `SYSBIN;TELSER BIN`.
- Reference: PDP-10/its PR #2348 documents this mechanism working on
  KA ITS 1653; these disks run 1652.

**Next step:** sample `NETCL1` (100165) across seconds after an RFC to
determine whether `NETCLK` (slow net clock, runs before the `USTART`
dispatch) wedges, or whether `USTRA` (job slot creation) fails each tick.

Key kernel addresses (KA ITS 1652, host126 build): IMPRFC=60201
IMPRFQ=60322 NTRFCL=55721 NUJBST=146165 NETUSW=210033 TREESW=210060
UTTYS=207155 UTTYI=207162 UTTYO=207163 UTTYCT=207164 NETCL1=100165

### Fixed: emulator IMP interrupt bug — ITS now ANSWERS network logins

The bundled `pdp10-ka` (built Dec 2024 from rcornwell/sims b45fedc0) is
missing the KAIMP fix from larsbrinkhoff/ka10-simh `lars/ncp` commit
a7c902ff (2026-01-10), which resolves PDP-10/its issue #2376
("LOCK NET hangs ITS"):

1. CONO with IMPIR clear must clear IMPIC — otherwise interrupt-on-IMP-
   ready stays latched, the IMP interrupt fires forever, IMPOST never
   returns, and the clock level is starved. This was the cause of the
   stuck UTTYS ring (no NETRFC spawn) and of terminals dying after
   network activity.
2. `STATUS &= IMPR` typo (missing `~`) corrupted device status on
   incoming packets without the ready flag.

Rebuilt `pdp10-ka` from larsbrinkhoff/ka10-simh @ lars/ncp (a7c902ff)
as `mini/host126/pdp10-ka-fixed`. Result: with this binary plus the
Chaosnet fix, an incoming `ncp-telnet -c 126` from IMP 31 received the
ITS TELSER login banner ("It's a lovely day to be a turist!") — the
first successful network login answer from host126.

Remaining flakiness: acceptance is intermittent across boots
("Open refused" CLS on some attempts); the pathological self-telnet
(:TELNET 176 to self) breaks RFNM accounting ("IMP: neg RFNM-wait cnt")
and should be avoided. Note: open-simh PR #522 (H316 host port 3/4
device address swap) is also needed for hosts on IMP ports 3-4
(MIT-AI 134, MIT-ML 198); host126 (port 2) is unaffected.

## 2026-06 — ARPANET infrastructure & BBN-TENEX host #69

Summary log for the larger efforts since 06-10; full detail in the per-effort
notebooks (`docs/journal/README.md` is the index).

### Added: event-driven per-IMP NCP startup (`mini/noc-server.py`)
Replaced a fixed 35 s `NCP_START_DELAY` timer that raced IMP boot speed on the
faster droplet (IMPs came up before 35 s and sat peerless). Each NCP now starts
the instant *its* IMP reaches RUNNING (old timer kept as a backstop). Also fixed
an `ncpdov` double-spawn (a PTY EOF mis-read as process death) by reaping any
stray daemon on the NCP's port pair before spawning (`noc/server/ncp.py`).

### Added: BBN-TENEX host #69 — native-NCP login (`@L 69`)
A real BBN-TENEX (SIMH `pdp10-ki`, built via Lars Brinkhoff's build-tenex) made
to answer `@L 69` with an authentic credentialed login. Highlights (full journal:
`docs/host69-ncp-login-investigation.md` §3–§10):
- **Persistence**: TENEX reboot-from-disk is upstream-unfinished, so we don't
  reboot — SIMH SAVE a fully-booted monitor and RESTORE forever.
- **1822 host-IMP emulator fidelity fixes** (`kx10_imp.c`): host-ready CONI gate +
  FORCEDOWN lever, IMP input re-arm, output-done (`IMPOB`). In
  `netser-build/emulator-fork/` (TODO: land in tracked `src/sims/`).
- **Login server = NETLIT** (we built it; real NETSER is bootstrap-blocked). The
  key insight: **`ATPTY` (JSYS 274)** hands the NCP connection to TENEX's own
  dial-up login path — no NETSER needed. `@L 69` → `BBN-TENEX … EXEC` →
  `LOGIN DEMO DEMO 1` → real session.

### Changed: NETLIT-1e — re-listen hardening
NETLIT-1d dropped to the `!` monitor EXEC after ~2 logins (a JFN leak in the
OPENF-retry loop → exhaustion → `HALTF`; contact socket closed without `RLJFN`).
NETLIT-1e adds a `CLRJ` close+release on every path, releases the listen JFN
before each retry, and removes all `HALTF` (matches real `netser.fai`). Re-listen
dropped from ~2.5 min to 0 s; survives unlimited sessions (5/5 gate).

### Added: golden-snapshot service (`arpanet-host69.service`, `host69ctl.sh`)
Login state (DEMO + NETLIT-1e LISTENING) baked into a SIMH SAVE snapshot; the
service just `restore -F`s it (no console "séance"). Phase 1 durability: daemon
waits for imp05+hi2 before host-ready (boot-ordering), sweeps stray `pdp10-ki`,
uses a per-boot marker (fixes a `Type=exec` stale-health-check race). Service
**enabled**. Reboot-survival test + the 1972-booklet scenarios are the remaining
go-live work (`docs/host69-go-live-plan.md`).

### Known issue: lab mesh routing islands under connection/ping load
Rapid `ncp-telnet`/`ncp-ping` and heavy restart churn degrade inter-IMP routing
(recover-in-place sometimes won't reconverge → reboot resets it). Recovery:
`mini/arpanet-recover.sh recover` then WAIT for convergence; never restart an IMP
to "nudge" it. The deeper robustness follow-up before advertising multi-user load.

## 2026-06-30 — host69 utilization + Phase 2 scenario sourcing

### Fixed: lab CPU utilization (the host69 ki + imp62 pegged the box)
Post-reboot the 4-vCPU box ran at load ~6-8. Recon found two unthrottled hogs we
had added (the upstream 35-IMP farm is throttled to 15% and was NOT the problem):
- **imp62** had `set nothrottle` (~92% of a core) → removed it so it inherits the
  farm's 15% (`mini/imp62.local.simh`). imp62 carries host126/HILTON-KA1 **and**
  the PiDP-10 (host41) Tailscale bridge — load-bearing, kept but throttled.
- **the host69 ki** busy-spun TENEX's idle loop at ~one core. `SET THROTTLE`
  self-disables on this host (documented); a deep `SET CPU IDLE` effort hit a wall
  (below). Pragmatic fix: a **systemd `CPUQuota=40%`** cgroup cap, applied by
  `host69ctl.sh` *after* host-ready (so the boot stays full-speed) — host-side, no
  effect on guest authenticity. ki dropped ~91%→~37%, load ~9.6→~7.0.

### Added (emulator, staged): TENEX idle support — `netser-build/emulator-fork/host69-tenex-idle.patch`
First-of-kind work: rcornwell's KI10 idle detector knew TOPS-10/ITS idle idioms but
**not TENEX**. Added a TENEX clause to `kx10_cpu.c` (TENEX idles in the scheduler
wait-list scan `SCHEDA`=0102713, derived from `build-tenex/tenex.dis`) + an adaptive
re-arm to `kx10_imp.c`'s UDP poll. Both **login-verified**, but did **not** drop CPU:
while the host-IMP link is up TENEX executes ~99% of the time (sim_idle sleeps <1% —
`TYM2`'s 1 ms re-arm + near-continuous execution dominate). Correct groundwork, but
idle doesn't bite yet → the `CPUQuota` cap is the shipping answer. Full notebook:
`docs/host69-tenex-idle-patch.md`. **Lesson logged:** probing against the live imp05
islanded the mesh and forced a full `arpanet-recover.sh recover`; future emulator
probing must use an isolated throwaway IMP pair, never the live mesh.

### Phase 2: exact scenario software identified + sourced (`docs/host69-go-live-plan.md`)
Read the 1972 booklet for the four BBN-TENEX #69 scenarios' exact programs:
- **#3 BBN Tenex** (EXEC/TECO/F40/SNDMSG/TELNET) — **all software in the kit**
  (prebuilt `f40.sav.3`/`sndmsg.sav.8` in `imsss/files/subsys/`, `telnet` in cusps,
  `teco` already on #69). **Buildable now** — the authentic anchor.
- **#11 BBN LIFE** = **Ray Tomlinson's** Conway Life; exact BBN source **lost**
  (only ITS MLIFE survives) → faithful FORTRAN-40 reconstruction (booklet specifies it).
- **#15 BBN Chess** = **Greenblatt's MacHack VI**; exact BBN binary **lost**, source
  survives as OCM `github.com/PDP-10/its:src/chprog/ocm.470` (MIDAS) → needs a TENEX port.
- **#18 BBN DOCTOR** = ELIZA; already covered by the 18A adaptation on MIT-AI #134.
