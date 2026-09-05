# ARPANET lab — project journal & status index

This is the entry point to the lab's **knowledge spine**: what we started with (the upstream
project), **what we added**, the state of each effort, and where its lab-notebook lives. The
governing rule (see `docs/host69-ncp-login-investigation.md` for the prototype): *branches are
disposable; knowledge lives in a path that lands in `main`.* An abandoned effort is a row in
this table + a journal — never a forgotten branch.

> Convention: each effort gets `docs/journal/<effort>/` (README + notebook + artifacts +
> PROVENANCE). Large bootable binaries (snapshots/packs/tapes) are **not** in git — they live
> in a vault and are referenced by each effort's `PROVENANCE.md`.

---

## What we started with (upstream: `obsolescence/arpanet`)

The upstream project is a faithful 1972–73 ARPANET: a farm of SIMH **IMP routers** running
original firmware over simulated leased lines, plus a **web-terminal** front end. Its own README
states the real-host roster at the time we forked:

> *"Currently, there's just PDP-10s at MIT, typically hosts 70, 134 and 198, and host 11, the
> Stanford SAIL system running WAITS. ... UCLA's SDS Sigma 7 is planned soon. Longer term, the
> hope is for Multics, PDP-11s, and perhaps even IBM 360s. It is early days yet."*

So the baseline **real hosts** were:
- **MIT ITS PDP-10s** — hosts **6 / 70 / 134 / 198** (`@L 6` reached an MIT ITS system).
- **Stanford WAITS** — host **11** (SU-AI), via a Linux bridge, not its own NCP.

Everything else in `mini/arpanet`'s `NCPS` list was either a **commented-out plan** or a bare
**NCP echo stub** (the `ncpdov` daemons that answer `ncp-ping` but run no real OS). The IMP farm
itself was solid; real machines were "early days."

**But present ≠ active.** Even the listed real hosts were not reliably *network-active*
upstream: the IMP host-attach lines used `localhost` (silent IPv6 failure of the NCP host
interface), and the KA ITS shipped with a KAIMP interrupt bug so it **could not answer network
logins**. So upstream's working network was effectively *the IMP farm + the generic NCP stubs*;
the real machines booted, but `@L` login into them was incomplete. Closing that gap — making
hosts actually answer on the network — is a large part of what we added.

---

## What we added (kurthamm fork — this repo)

**Read this carefully — provenance was verified against the live `github.com/obsolescence/arpanet`
main (HEAD `78123c7`), not assumed.** The key distinction is **presence vs network-active**: a
host *directory* existing in upstream does NOT mean that host was active on the simulated
network. Upstream shipped several hosts that were present/bootable but whose NCP login did not
work (a `localhost`/IPv6 silent-failure bug in the IMP host-attach lines, and a KAIMP interrupt
bug that stopped ITS from answering network logins). The work spans two lines: the **droplet**
(this repo, most-evolved) and an earlier **Civitae** line (`feature/its-ncp-debug`).

### Host roster — presence vs network-active (honest)
| Host | OS / emulator | In upstream? | Network-active upstream? | Our contribution |
|---|---|---|---|---|
| ~18 map stubs (UCLA-NMC, SRI-ARC, RAND, …) | **generic `ncpdov`** (Lars Brinkhoff `linux-ncp`) | **yes (upstream's)** | yes, but broken by the `localhost`/IPv6 bug | fixed plumbing (`127.0.0.1`) so they actually route |
| **#70/134/198 MIT** | ITS / KA PDP-10 | yes (present, bootable) | **NO** — KAIMP bug, no `@L` login | **activated**: `pdp10-ka-fixed` (KAIMP) + Chaosnet |
| **#126 HILTON-KA1** | ITS / KA-10 | yes (present, bootable) | **NO** (not in upstream "working" set) | **activated/completed** (same KA fix) |
| **#11 Stanford** | WAITS (SIMH PDP-10) | yes — via Linux bridge, *not* own NCP | partial (bridge) | + **PARRY / AP-lab** (new) |
| **#1 UCLA** | **Sigma 7 / CP-V** (SIMH sigma) | **no dir** ("planned") | no | **built new** |
| **#6 MIT** | **Multics** (DPS8M MR12.8) | **no dir** ("hope"; upstream #6 was ITS) | no | **built new** |
| **#65 UCLA** | **OS/360 MVT** (Hercules) + `ccn_frontdoor.py` | **no dir** | no | **built new** |
| **#69 BBN** | **BBN-TENEX** (SIMH PDP-10 KI) | **no dir** (not even planned) | no | **NATIVE-NCP LOGIN DONE + HARDENED + DEPLOYED** — `@L 69` → real BBN-TENEX `@` EXEC, credentialed DEMO login via **`ATPTY`** (JSYS 274; NETSER not needed). Login server **NETLIT-1e** (re-listen hardened: 0 s, no crash; 5/5 gate). Baked into a **golden SIMH snapshot**; `arpanet-host69.service` restores it and is **enabled**. Going live in phases (`docs/host69-go-live-plan.md`); full journal `docs/host69-ncp-login-investigation.md` §10. |
| **#49 HAMM-KA0** | **ITS** (physical PiDP-10, KA10) | **no** (Kurt's hardware) | no | **built new + NATIVE-NCP DONE (2026-09-05)** — Kurt's home PiDP-10 over a Tailscale IMP62↔IMP49 trunk. Power-on auto-boots ITS; `@L 49` serves a full login through the IMPs. A deliberately *fictional* private node at an IMP number vacant in Dec 1973 (renumbered off host 41 = real NORSAR). See `docs/pidp10-host-identity.md`. |

### Network seam — how each host actually reaches visitors (the honesty that matters)
Running a real OS is *not* the same as being an authentic ARPANET host. **As of 2026-09-04
(`feature/imp-routed-sessions`) every visitor session flows THROUGH the IMP network — the
terminal-line bypass is gone** (`docs/journal/imp-routed-sessions.md`). By integration method:
- **Native period NCP** (the host's own OS speaks 1822/NCP on its IMP — the golden route):
  **ITS** (#70/134/198/126 — all four verified), **BBN-TENEX** (#69), and **HAMM-KA0** (#49 —
  Kurt's physical PiDP-10 KA10/ITS, reached over the Tailscale IMP62↔IMP49 trunk; `@L 49` verified).
- **FEP** (Oscar's period-correct front-end: a Linux `ncpdov` + `ncp-telnet -s -- fep-line.py`
  bridges the host onto its IMP port, so session data still crosses the IMPs): **Sigma 7 / CP-V**
  (#1), **Multics** (#6), **OS/360 MVT** (#65). Supervised by `arpanet-fep.service`.
- **NCP bridge (legacy one-off)** — **WAITS** (#11) via `waitsconnect`; to be folded into the
  generic FEP (Task 6).
- **No real OS** — the ~18 `ncpdov` map stubs.

Earlier this file said Sigma/Multics/OS-360 were reached "via terminal/front-door bridges, **not**
native ARPANET NCP hosts, native-NCP attach still future" — that was the pre-restoration bypass
state and is **superseded**: they now cross the IMPs via the FEP (the authentic period technique
for a host without its own NCP). The restart fragility that made this finicky is fixed at the root
in the emulator (`h316_hi.c` no longer permanently detaches on a transient host-link loss).

### Subsystems & engineering we added
- **ITS network logins** (Civitae `feature/its-ncp-debug`): `pdp10-ka-fixed` (KAIMP interrupt
  fix, PDP-10/its #2376 — ITS now answers network logins), Chaosnet-enable (fixes KA ITS 1652
  panic on first NCP connection), `localhost`→`127.0.0.1` in IMP host-attach (silent-failure
  fix), `@O` old-Telnet (socket 1) plumbing through `do.sh`/`dotelnet.sh`. **+ uncommitted WIP
  on Civitae** (`mini/noc/server/ncp.py`, `mini/src/ncpd-ovREUSE/src/ncp.c`,
  `mini/src/waits-ncpd/waitsconnect.c`, `imp06.simh`) — preserved in the import (see below).
- **Event-driven per-IMP NCP startup** (`mini/noc-server.py`) — replaced a fixed 35 s timer
  that raced IMP boot speed on faster hardware and left host interfaces peerless.
- **1822 host-IMP emulator fidelity fixes** (`kx10_imp.c`, rcornwell `pdp10-ki` fork) — for host69:
  the host-ready CONI gate + **FORCEDOWN lever**, the **IMP input re-arm** fix, and the **output-done
  (`IMPOB`)** fix (host69 notebook §3/§10.3/§10.6/§10.7). Preserved in `netser-build/emulator-fork/`
  (patch + git bundle). TODO: land in tracked `src/sims/` (publish a `kurthamm/sims` fork).
- **Host lifecycle & ops tooling** — `hostctl.sh`, per-host `*ctl.sh`, `arpanet-recover.sh`,
  `arpanet-health.sh` (`docs/host-lifecycle.md`).
- **Production deployment** — migration to this DigitalOcean droplet, Cloudflare-tunnel hosting,
  web-terminal hardening (`docs/digitalocean-migration.md`, `docs/cloudflare-tunnel-hosting.md`,
  `docs/hosted-terminal-fixes.md`).

---

## Source servers & the Civitae import

- **This box** = `arpanet-do` (DigitalOcean droplet, Tailscale `100.119.40.26`) — production +
  active development. Git remote `origin` = `github.com:kurthamm/arpanet` (our fork).
- **Civitae** = the *old* shared server (`Civitae-Server`, Tailscale `100.120.170.123`, public
  `165.245.140.51` but SSH is Tailscale-only). Read-only reference per the migration plan. Its
  `~/arpanet` carries the obsolescence upstream + our `feature/its-ncp-debug` + 6.4 G of
  configured runtime packs (the actual working ITS/Multics/Sigma disk images — vault material).
- A knowledge copy of Civitae `~/arpanet` (git history + source + WIP, binaries excluded by
  size) was pulled to `civitae-import/` (gitignored) for backfill review. The full tree
  including packs remains on Civitae; re-pull with `rsync … deltaprism@100.120.170.123:~/arpanet/`.

---

## Per-effort notebooks (status)
- [x] **host69-bbn-tenex** — `docs/host69-ncp-login-investigation.md` (full journal: §8 dead-ends, §9 gotchas)
      + `docs/host69-go-live-plan.md` (4-phase go-live) + `netser-build/` (NETLIT source, `emulator-fork/`,
      `investigation-2026-06-28/` artifacts). Login DONE + hardened + deployed; going live in phases.
- [x] **its-network-login** — `docs/journal/its-network-login.md` (the activation story for #70/134/198/126).
- [x] **imp-routed-sessions** — `docs/journal/imp-routed-sessions.md` (2026-09-04: every host put back
      THROUGH the IMPs — native NCP for ITS, FEP for Sigma/Multics/OS-360; bypass removed; source
      rotation restored; FEP under systemd; `h316_hi.c` peer-loss resilience. Prompted by Oscar's mail).
- [x] **host06-multics** — `mini/host06-multics/README.md` (was undocumented).
- [x] **host01-sigma** — `mini/host01-sigma/README.md` (honest: CP-V via terminal bridge, not yet native NCP).
- [x] **host65-ucla-ccn** — `mini/host65-ucla-ccn/README.md` (OS/360 MVT via front-door bridge).
- [x] **host11-waits/PARRY** — `docs/host11-ap-lab.md`, `docs/host11-parry-restoration.md`.

## Remaining catch-up TODO
- [x] Emulator fork preserved out of the gitignored build cache → `netser-build/emulator-fork/`
      (patch + git bundle + README). *Future:* publish a `kurthamm/sims` fork and point the
      `src/sims` submodule at it (so it's a first-class tracked dependency, not a patch).
- [x] `docs/journal/PROVENANCE.md` — bootable-binary inventory, checksums, rebuild recipes, and
      vault recommendation. *Decision needed:* actually vault the irreplaceable blobs (the
      droplet-only host69 snapshot + the configured packs) — git-LFS / object store / mirror.
- [x] host69 NCP frontier — **SOLVED**: RFC now dispatched, full credentialed login proven, NETLIT-1e
      re-listen hardened, golden-snapshot service enabled (host69 notebook §10.3–§10.13b).
- [ ] **host69 go-live** (`docs/host69-go-live-plan.md`): Phase 1 done + **Phase 1d reboot-survival passed**
      (session-start reboot auto-brought-up #69, login works). **Phase 2 software SOURCED (2026-06-30):**
      **#3 Tenex** (EXEC/TECO/F40/SNDMSG/TELNET) — all software in the kit, **buildable now**; **#11 LIFE**
      (Tomlinson) + **#15 Chess** (Greenblatt MacHack) — exact BBN originals lost, reconstruct/port (LIFE in
      F40; CHESS from `PDP-10/its` OCM MIDAS); **#18 DOCTOR** already covered (18A). Next = build #3 → #11 →
      #15. → Phase 3 website wiring → Phase 4 deploy.
- [ ] **Lab mesh robustness** (project-wide): routing to a host **islands under connection/ping load** +
      heavy restart churn (recover-in-place sometimes won't reconverge → reboot resets it). The deeper
      follow-up before advertising multi-user load. (2026-06-30: emulator-idle probing against the live
      imp05 re-triggered this — see the idle notebook's lesson; use an isolated throwaway IMP rig instead.)
- [ ] **Land the `kx10_imp.c` host69 emulator fixes in tracked `src/sims/`** (currently a patch in
      `netser-build/emulator-fork/` + the gitignored build cache; now includes `host69-tenex-idle.patch`).
- [x] **host69 lab CPU utilization** — **RESOLVED 2026-06-30** via host-side caps (no guest impact):
      removed imp62's `set nothrottle` (→15%) and a systemd **`CPUQuota=40%`** on the ki applied post-boot
      by `host69ctl.sh` (ki ~91→37%, load ~9.6→7.0). The "pure" `SET CPU IDLE` route is **staged but inert**
      (`docs/host69-tenex-idle-patch.md`): the `kx10_cpu.c` SCHEDA detector + `kx10_imp.c` adaptive poll are
      correct + login-verified, but TENEX executes ~99% of the time while the IMP link is up (sim_idle sleeps
      <1%; `TYM2`'s 1 ms re-arm dominates), so idle doesn't bite — `CPUQuota` is the shipping answer.
      *(Earlier "IMP isn't `UNIT_IDLE`" note was wrong — all device units have it; corrected.)*
