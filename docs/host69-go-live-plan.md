# host69 BBN-TENEX — go-live plan (2026-06-30)

Sequenced plan to take host69 from "works, manually" to "public, durable." Supersedes the
2026-06-24 cutover notes in the `host69-production-cutover` memory (which predate the golden-snapshot
service and the NETLIT-1e hardening). Companion: `docs/host69-ncp-login-investigation.md` (§10.10–§10.13b).

## Current state (start of plan)
- host69 = **NETLIT-1e** (re-listen hardened, §10.13), baked into the golden snapshot
  `snap/host69-login.state`, served by **`arpanet-host69.service`** (restores the snapshot, FORCEDOWN
  host-ready, drainers). Reachable when the mesh is healthy; 5/5 service-restored logins proven.
- Service is **`disabled`** (no auto-start on boot).
- imp05↔host69 wiring: **already present** in `mini/imp05.local.simh` (hi2 enabled, `127.0.0.1`,
  21051↔21052) — and the noc uses the `.local` variant. (`mini/imp05.simh` still has hi2 commented;
  mirror it for hygiene.) NCP-list line `05:1:69` in `mini/arpanet` stays **commented** — host69 is a
  real monitor-NCP TENEX (like host70), not an `ncpdov` stub.
- Nothing public (not on the web terminal / scenario page).

## Mesh-stability ground rule (learned 2026-06-29/30, the hard way)
After any host69/imp05 change, **WAIT for convergence (minutes) and do NOT restart imp05 to "nudge" it**
— repeated imp05 restarts island the mesh. Recovery when islanded: `sudo mini/arpanet-recover.sh recover`
→ wait → bring host69 up after imp05 is fresh/stable. host69 only needs imp05 reachable, which converges
before the far mesh.

---

## Phase 1 — Make host69 durable & reboot-surviving  (1a/1b/1c DONE 2026-06-30; 1d pending)
Goal: after a cold reboot, host69 comes up reachable on its own (no babysitting).
- **1a. Permanent imp05 wiring** — ✅ already in `imp05.local.simh` (live); mirrored hi2 into
  `imp05.simh` (`127.0.0.1`) for hygiene; NCP-list `05:1:69` left commented (host69 = real monitor-NCP).
- **1b. Boot-ordering + robustness fix** — ✅ implemented in `host69ctl.sh` (option A, self-contained):
  - `cmd_daemon` waits (≤180s) for **imp05 + its hi2 (21051) up** (`imp05_ready`) before restore+FORCEDOWN,
    so host69 asserts host-ready to a READY imp05.
  - **Clean slate:** `cmd_daemon`/`do_stop` `pkill -9 -x pdp10-ki` + console-daemon/drain.py — a stray
    manual ki (`run-1c.do`) had been holding 2323/16945/21052 and segfaulting the service's bind.
  - **Per-boot id:** daemon writes `$SCR/host69.bootid` + the `.do` echoes `=== BOOT <id> ===`; `setup`
    anchors to it, fixing the stale-HOST-READY-DONE race (Type=exec runs ExecStartPost concurrently).
  - Unit: `TimeoutStartSec=600` (imp05-wait + host-ready can stack); repo copy `mini/arpanet-host69.service`
    re-synced to the live unit.
  - Validated: clean service start took 189s, **real** host-ready (not stale), reachable, one clean ki.
- **1c. Enable** — ✅ `systemctl enable arpanet-host69.service` (is-enabled: enabled).
- **1d. Reboot test** — ⏳ **Kurt triggers** (drops the on-box Claude session). After boot, confirm host69
  is `ncp-ping`-reachable + serves `@L 69` login with no manual step. A reboot also resets the whole mesh
  fresh — the cleanest validation.
- **GATE:** host69 survives a cold reboot reachable with no manual intervention.
- **Known caveat (separate from boot-ordering):** the lab mesh routing to host69 **islands under
  connection/ping load** (rapid `ncp-telnet`/`ncp-ping` during testing degrades routing; NETLIT stays
  alive). host69+service+snapshot are solid (5/5 logins proven on a healthy mesh); mesh-under-load
  robustness is the deeper follow-up. A fresh reboot avoids the accumulated-churn degradation.

## Phase 2 — 1972 booklet scenarios on #69
The ICCC '72 booklet (`arpa/scenarios.pdf`, NIC 11863) has **four BBN-TENEX (host #69) scenarios**.
Software sourcing resolved 2026-06-30 (booklet read for exact program identities + archive search):

- **#3 BBN Tenex** (booklet §"BBN TENEX HOST #69") — login + EXEC tour: `?`, `SYS`, `WHERE`, `LINK`, `DIR`,
  `DAY`, `TYPE`, `DELETE`, `LOGOUT`, plus `TECO` (editor), `F40`+`LOADER` (FORTRAN compile-and-run "HELLO
  ICCC"), `SNDMSG` (mail), `TELNET` (outbound). **✅ ALL SOFTWARE IN THE KIT — buildable now:** `teco.sav`
  already on #69; **prebuilt** `f40.sav.3` + `sndmsg.sav.8` in `kit-cache/imsss/files/subsys/`; TELNET =
  `kit-cache/tenex/cusps/telnet.run` + `telnet.mac`. Install path = DECtape COPY (proven). **Authentic
  anchor — do it first.**
- **#18 BBN DOCTOR** — Weizenbaum ELIZA (LISP). **Already covered** by the platform's 18A on MIT-AI #134
  (recovered ITS DOCTOR). Could restore to #69 via TENEX LISP (`imsss subsys/lisp.sav.5`) to reclaim the
  authentic slot, but **deprioritized** — we already have a working DOCTOR experience.
- **#11 BBN LIFE** — **Conway's Life, coded by Ray Tomlinson at BBN** (`@run <HACKS>LIFE`; 72×72 grid,
  asterisk/space input, ESC-terminated; pattern file `<HACKS>CORDERMAN.LIFE`). **Exact BBN source LOST** —
  not in `github.com/PDP-10/tenex`, our kit, or the web. Surviving Conway-Life source = **MLIFE** (Speciner),
  MIDAS: <https://github.com/PDP-10/its/blob/d4478b47b3eb593fdb862f4c12b2cde60c13d564/src/rwg/mlife.21>
  (+ Gosper `src/rwg/life.*`) — but that's ITS/MIDAS, not Tomlinson's. **Path: faithful reconstruction in
  FORTRAN-40** (booklet fully specifies rules + I/O) — small + tractable; MLIFE is the reference behaviour.
- **#15 BBN Chess** — **Richard Greenblatt's MacHack VI** ("Mac Hack Six"; `@run <HACKS>CHESS` =
  `<HACKS>CHESS.SAV`; standard algebraic notation, `BD`/`PW`/`PB`/`GB`/`M`/`U` commands). **Exact BBN binary
  LOST.** Same program's source SURVIVES (ITS/MIDAS, pinned at PDP-10/its `d4478b4`):
  - **OCM/MacHack main:** <https://github.com/PDP-10/its/blob/d4478b47b3eb593fdb862f4c12b2cde60c13d564/src/chprog/ocm.470>
  - **support:** `src/chprog/ocaux.224` and `src/chprog/ocdagb.31` (same tree)
  - **docs:** <https://github.com/PDP-10/its/blob/d4478b47b3eb593fdb862f4c12b2cde60c13d564/doc/games.md> (+ `doc/chprog/ocm.order`, `doc/ms/chess.memo`); alt **Tech II** (Baisley) `src/rg/chess2.614`.
  **Hardest** — needs a real MIDAS/ITS → TENEX port (JSYS + assembler differences) across `ocm`+`ocaux`+`ocdagb`.

Plan: ship **#3** now (fully sourced) → **#11 LIFE** via FORTRAN-40 reconstruction → **#15 CHESS** (MacHack
MIDAS→TENEX port) as a stretch; **#18** already covered. DECtape-COPY install path proven from NETLIT work.
Numbering follows the page's convention (original booklet number = authentic; `NNA` = adaptation).
Login over the net: `DEMO/DEMO/1` (the booklet used `iccc/iccc/11514`).

## Phase 3 — Website wiring
- `arpanet_terminal2.html`: add host69 to `activeHosts` (login `@LOGIN DEMO DEMO 1`); update intro/reachable lists.
- `arpa/arpanet-nodes.json`: set host 69 status to live/reachable.
- Map: `mini/topol/arpanet_network_interactive.html` + `arpa/arpanet-node-5-BBN.html`.
- `arpa/2026-scenarios.html`: add the working #69 scenarios (and promote DOCTOR 18A→18 if done).

## Phase 4 — Deploy
Publish (outward-facing — confirm with Kurt before anything goes live). See
`docs/digitalocean-migration.md`, `docs/cloudflare-tunnel-hosting.md`.
