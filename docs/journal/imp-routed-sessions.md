# IMP-routed sessions — put every visitor session back through the IMP network

**Effort:** `feature/imp-routed-sessions`. **State: ✅ core done** (all hosts route through the
IMPs; emulator restart-fragility fixed at the root). Prompted by Oscar Vermeulen's 2026-08-29
email (full text in `docs/superpowers/2026-09-03-turnover.md` §1).

## Why this exists
During the 2026-06 DigitalOcean migration (`do.sh`, commit 110ac57) `@L` to most hosts was wired
**straight to each simulator's terminal-line TCP port** via `local-host-terminal.py` — the IMP
network was up but **user session data no longer flowed through it**. Only Stanford WAITS (#11)
still went through the IMPs. Oscar (rightly) flagged this as losing the whole point. Kurt's call:
put every host back on IMP-routed sessions and remove the bypass entirely.

Two routes, both through the IMPs (no third "bypass" option):
- **Native period NCP** — the host's own OS speaks 1822/NCP on its IMP (the golden route): the
  ITS machines (#70/126/134/198).
- **FEP** (Oscar's own period-correct method) — a Linux front-end (`ncpdov` + `ncp-telnet -s --
  fep-line.py`) bridges a host that has no working NCP: UCLA Sigma #1, MIT Multics #6, UCLA-CCN
  OS/360 #65.

> Scope note (Kurt, 2026-09-03): take **only the engineering** from Oscar's mail. Do **not**
> rebrand to his project name / credits / links; this implementation stays clearly Kurt's. See
> the `kurt-keep-project-his-own` memory.

## What we did (2026-09-03/04, all on `feature/imp-routed-sessions`)
- **Merged** `origin/host69-tenex-ncp-imp` (the droplet's production branch, incl. the host69
  BBN-TENEX node) into this branch so restoring IMP routing didn't drop host69. Both NCP-startup
  fixes compose: `run()` starts NCPs before IMPs (H316 `hi_link_error` avoidance) **and**
  `_on_imp_state_change` fires the idempotent per-IMP NCP start as a backstop.
- **Task 5b — TIP source rotation restored.** `do.sh` rotates browser sessions over the 8 TIP
  sources again; the two dead ones (LL-TX2 #74 on imp10:1, CMU-10A #78 on imp14:1) were
  NCPS-commented while their IMP host ports were attached — uncommented + `dotelnet.sh` FULLHOST
  map fix. Verified: all 8 sources reach `@L 1` through the IMPs.
- **Task 7 — ITS native NCP on all four** (#70/126/134/198). These were already `pdp10-ka-fixed`
  (Lars's KAIMP fix) except **#198 (MIT-ML), which `hostctl.sh` special-cased onto the unfixed
  `./pdp10-ka`** → it never answered `@L`. Removed the special-case; 198 now native like the
  rest. (The H316 port-3/4 device fix it also needs — Lars's `c26fd74` — was already built into
  `h316ov`.) 12/12 native logins across 3 sources.
- **host 65 (OS/360) brought online.** The turnover (written on the old Civitae box) said
  "hercules not installed"; **stale** — Hercules is here, host 65 runs, and `@L 65` now reaches
  "UCLA CCN 360/91 SERVER TELNET" through the IMPs. (See `turnover-blocked-status-stale` memory.)
- **Task 4b — FEPs under systemd.** `deploy/systemd/arpanet-fep.service` +
  `mini/fep-wait-and-start.sh` (bounded wait for the FEP NCP sockets, then `fepctl start all`).
  `fepctl` now *skips* (not fatal) a host whose backing simulator isn't up, so the unit comes up
  clean with whatever hosts are present.
- **Task 8 — restart policy.** The plan's coupled restart (stop ITS hosts → restart their IMP →
  start hosts) is the exact recipe that trips `hi_link_error`: restarting a live IMP while a host
  interface has no peer **crashed** the fresh IMP (reproduced repeatedly on imp62) and islanded
  it from the mesh ~1 min. So `hostctl restart <its-host>` is kept as the **reliable ITS-only
  reboot into the live IMP** (the supported direction; ~15× clean this session). IMP-level
  recovery stays the coordinated `arpanet-recover.sh`.
- **Emulator resilience (the root fix).** `src/simh-REUSE/H316/h316_hi.c` `hi_link_error()` no
  longer permanently detaches on a transient UDP peer loss — it logs once, resets the line once,
  and keeps the interface attached so it auto-recovers when the peer returns (`hi_poll_rx` clears
  the flag on the next good packet). This removes the restart fragility at the source: an IMP now
  survives a host being down, and ITS can reboot and re-marry without an IMP restart. Rebuilt
  `h316ov` (`-Werror` clean); validated (new binary runs imp62 with its host DOWN for 20s+ with
  no crash/detach; old binary would detach). Deployed to `mini/h316ov` (atomic `mv`; old kept as
  `mini/h316ov.bak-predetachfix`). **Fleet-wide activation = next restart of each IMP** (one
  coordinated `arpanet-recover.sh` in a maintenance window).

## 2026-09-04 — reboot recovery + reliability hardening (all 7 hosts durable)
A full reboot exposed how fragile recovery was; hardened it end-to-end (host-side only).
Root causes and fixes:
- **`arpanet-host@6` was the ITS KA template, but host 6 is MIT-MULTICS (DPS8M).** It died on an
  unbound `$dest` and spun every 5s holding the *single global* `flock`, starving the real ITS
  hosts (70/126) so they timed out and stayed `failed`. Fix: **per-host locks**
  (`/tmp/arpanet-hostctl-%i.lock`) so hosts start in parallel and can't starve each other; host 6
  gets its own `arpanet-host06-multics.service`; `arpanet-host@6` masked.
- **The unit ran `verify` (240s loop) *before* starting a down host** → 4 min wasted per cold host.
  Fix: fast `isup` probe (single ping) to adopt an already-up host; the long `verify` runs only
  after a real start.
- **imp06 (busiest IMP — all four MIT hosts hi1-4 = MULTICS/DMS/AI/ML) lost the boot-race attaching
  hi4**, so host 198 booted fine but could never marry. The IMP-side UDP socket was simply absent.
  Fix: **`arpanet-recover.sh reconcile`** self-heal — for a down host, if the IMP interface is up it
  fresh-boots the host; if the interface detached it restarts the IMP *with all host peers present*
  (crash-safe) then re-marries. `arpanet-reconcile.service` runs it once at boot; a healthy boot is
  a fast no-op. Verified live: no-op and light (fresh-boot) paths.
- Diagnosis lesson: **`ncp-ping` conflates OS-down / IMP-link-dead / IMP-unreachable**; a console
  "IN OPERATION" ≠ on-the-net. Ground truth for the host↔IMP link is `sudo ss -unap` (UDP, both
  ends must be ESTAB). See the `arpanet-recovery-fragility` / `imp06-hi4-boot-race` memories.

Result: hosts 6, 11, 69, 70, 126, 134, 198 all NCP-UP, systemd `active` + `enabled`. Residual:
the imp06 hi4 cold-boot race can still recur, but `arpanet-reconcile.service` now auto-heals it.

## 2026-09-04 (pause) — HANDOFF: FEP @L login layer is broken (6 + 11)

Paused mid-fix at Kurt's call. Read this before resuming.

### Solid (do not re-litigate)
- **Core NCP mesh: all 7 hosts `ncp-ping` UP** — 6, 11, 69, 70, 126, 134, 198.
- **ITS hosts (70/126/134/198) + TENEX (69) route end-to-end** through the IMPs; `@L` works.
  systemd `active`+`enabled`; per-host locks + `isup` + `arpanet-reconcile` self-heal in place.
- MIT-MULTICS **OS** is up (6180 LISTEN, salutation verified).

### Broken: the FEP `@L` *login* path (distinct from ncp-ping!)
`ncp-ping <h>` UP does NOT mean `@L <h>` works for FEP hosts — ping is answered by the ncpdov;
`@L` needs the `ncp-telnet -s` bridge to accept an RFC. Current `ncp-telnet -o` results:
- **host 6 (Multics): `Open refused`.** `fep6` bridge is running again, but its listener isn't
  being accepted through the freshly-restarted imp06/ncp06. I restarted imp06 earlier (to attach
  hi4 for host 198); that killed `fep6`, and neither an `arpanet-fep` restart nor a `fepctl
  stop/start 6` restored `@L`.
- **host 11 (WAITS): `Open refused`.** Regression from this session: the running host 11 predates
  the FEP-migration commit (4880782), so it does NOT expose simulator line port 1025; `fep11` fails
  to start ("line port 1025 not listening"). Its old `waitsconnect` bridge is now gone. So host 11
  `@L` is currently down until WAITS is rebooted with the new config.
- **hosts 1 (Sigma), 65 (OS/360): `Open refused`** — expected/pre-existing: their backing
  simulators aren't running on this box (ports 4003/16515 down). Separate bring-up task.
- `make check` / `mini/verify-imp-routing.sh` reflects this: 6 pass / 3 fail (the FEP hosts).

### What I caused vs pre-existing
The imp06 restart (needed to marry host 198) knocked out `fep6`; the `arpanet-fep` restart during
debugging brought host 11's half-migrated FEP config into play while `waitsconnect` was gone. The
ITS/TENEX layer and the ncp-ping mesh were NOT disturbed.

### What I want to try next (in priority order)
1. **Coordinated `mini/arpanet-recover.sh recover`** in a window — the designed path: it restarts
   hosts in order (FEP hosts, incl. WAITS with the new line-1025 config, before the IMP farm; ITS
   after) and re-registers the FEP login bridges on healthy NCP/IMP. Most likely one-shot fix for
   both 6 and 11. Cost: cycles everything (~10 min), briefly drops the working ITS hosts.
2. If targeting instead of full recover:
   - host 11: `host11ctl.sh stop 11 && host11ctl.sh start 11` (reboots WAITS exposing line 1025),
     then `fepctl.sh start 11`; verify `ncp-telnet -o 11`.
   - host 6: find why `fep6`'s `ncp-telnet -s` listen isn't accepted on `ncp06` after the imp06
     restart — likely the `ncp06` daemon needs a restart via noc (not just the fep screen). Compare
     against a known-good FEP host once one exists.
3. **Extend `arpanet-recover.sh reconcile`** to cover FEP hosts: it currently checks ITS via
   ncp-ping and Multics via the 6180 salutation, but NOT the `@L` login bridge. It should verify
   `ncp-telnet -o <h>` for FEP hosts and, on failure, restart the fep bridge (and reboot the host if
   its line port isn't listening). This is the gap that let host 6/11 `@L` break silently.

## Accuracy line (Kurt's rule; congruent with Oscar/Lars)
Everything here is host-side: `do.sh`/`hostctl`/`fepctl`/systemd orchestration and the SIMH
**emulator** UDP bridge (`h316_hi.c`). The **guest** artifacts (ITS, IMP firmware, 1822/NCP) are
untouched. The `h316_hi.c` change is exactly the kind of emulator maintenance Lars does (he wrote
that UDP host interface and fixed its port-3/4 addressing); the guest sees unchanged — actually
more faithful — 1822 behavior. Patching ITS's broken reconnect code (the vintage guest) was
considered and **rejected** — Lars/Oscar themselves worked around it rather than modify ITS.

## Gotchas / lessons (cost real time)
- **Orphaned processes** repeatedly broke things: a stale `waitsconnect` (from the original boot)
  fighting the fresh one over ncp16; duplicate host emulators. Always hunt orphans first
  (`lab-duplicate-orphan-cleanup` memory). `pgrep -x` for true counts (an args-grep double-counts
  the `SCREEN -dmS …` wrapper line).
- **Zero-gap `impctl stop; start <imp>` crashes the IMP** (old UDP sockets not released); a spaced
  stop → ~12s → start is reliable. (The `h316_hi.c` fix reduces how often an IMP restart is
  needed at all.)
- **Restarting an IMP islands it from the mesh ~60s** until routing reconverges; `ncp-ping` reads
  "IMP cannot be reached" during that window — wait it out, don't re-restart.
- The live `simh-server` reads `do.sh` from the working tree, so a branch checkout changes routing
  behavior immediately — mind that on the production droplet.

## Status / remaining
- [x] Merge; Task 5b (8 sources); Task 7 (ITS native ×4); host 65 online; Task 4b (FEP systemd);
      Task 8 (reliable ITS-only restart); `h316_hi.c` peer-loss resilience (built/validated/deployed).
- [ ] **Fleet-wide `h316ov` activation** — coordinated `arpanet-recover.sh` in a window so every IMP
      picks up the resilient binary; then confirm an IMP survives a host-down restart end-to-end.
- [x] **Task 6** — WAITS (#11) folded into the generic FEP (`fep-line.py` gains `--delay` /
      `--send-after-connect` / `--logout-on-close`; `fep-hosts.conf` adds `11:ncp11:1025`); the
      bespoke `waitsconnect` is retired (commit 4880782). No one-off bridges remain.
- [ ] **Task 9** — host 41 (PiDP-10) native NCP.
- [ ] **Task 10** — `make check` / `mini/verify-imp-routing.sh` (assert no bypass; every host routes).
- [ ] **noc per-IMP restart flakiness** — `impctl restart <imp>` is less reliable than a manual
      spaced stop/start; worth hardening in `noc-server.py`/`impctl` (separate from the emulator fix).
