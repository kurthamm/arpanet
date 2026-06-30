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

### Network seam — how each host actually reaches visitors (the honesty that matters)
Running a real OS is *not* the same as being an authentic ARPANET host. By integration method:
- **Native period NCP** (the host's own OS speaks 1822/NCP on its IMP — the authentic path):
  **ITS** (#6/70/134/198/126) and **BBN-TENEX** (#69 — login done + hardened + deployed).
- **NCP bridge** (a Linux NCP daemon stands in for the host's network stack): **WAITS** (#11)
  via `waitsconnect`.
- **Terminal / front-door bridge** (real OS, but reached through the web terminal or a shim —
  **not** a native ARPANET NCP host): **Sigma 7 / CP-V** (#1) via `local-host-terminal.py`
  (its own README: *"not attached to IMP #1 as a working NCP host yet"*); **Multics** (#6) via
  the TCP-6180 terminal; **OS/360 MVT** (#65) via `ccn_frontdoor.py` + `s3270`.
- **No real OS** — the ~18 `ncpdov` map stubs.

So our work splits cleanly: ITS and **TENEX (#69)** we **activated as native NCP** (host69 login
proven + hardened + deployed); Sigma/Multics/OS-360 are **authentic OSes wired in via bridges**, with
native-NCP attach still future work. Don't let "it runs `@L 1`" be read as "it's an authentic NCP host."

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
- [ ] **host69 go-live** (`docs/host69-go-live-plan.md`): Phase 1d reboot-survival test → Phase 2 the
      four 1972 BBN booklet scenarios (#3 Tenex / #11 LIFE / #15 Chess / #18 DOCTOR, `arpa/scenarios.pdf`)
      → Phase 3 website wiring → Phase 4 deploy.
- [ ] **Lab mesh robustness** (project-wide): routing to a host **islands under connection/ping load** +
      heavy restart churn (recover-in-place sometimes won't reconverge → reboot resets it). The deeper
      follow-up before advertising multi-user load.
- [ ] **Land the `kx10_imp.c` host69 emulator fixes in tracked `src/sims/`** (currently a patch in
      `netser-build/emulator-fork/` + the gitignored build cache).
