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
