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

---

## What we added (kurthamm fork — this repo)

The work spans two lines: the **droplet** (this repo, the most-evolved) and an earlier
**Civitae** line (`feature/its-ncp-debug`, the ITS login fixes + WIP), imported for backfill.

### New / brought-to-life hosts
| Host | Machine / OS | Was, upstream | State | Notebook |
|---|---|---|---|---|
| **#1 UCLA** | SDS **Sigma 7 / CP-V** | "planned soon" | ✅ running (`@L 1`, port 4003) | `mini/host01-sigma/` |
| **#6 MIT** | **Multics** (DPS8M MR12.8) | "longer-term hope" | ✅ running (`@L 6`, port 6180) | `mini/host06-multics/` |
| **#11 Stanford** | WAITS + **PARRY** / AP-lab | WAITS only (bridge) | ✅ WAITS login via `waitsconnect`; PARRY restored | `docs/host11-*.md`, `mini/host11-ap-lab/` |
| **#65 UCLA** | UCLA **CCN** | commented plan | 🟡 in repo | `mini/host65-ucla-ccn/` |
| **#69 BBN** | **BBN-TENEX** | not even planned | 🟧 **active** — host-ready solved; login blocked at NCP RFC dispatch | `docs/host69-ncp-login-investigation.md` |
| **#70/134/198 MIT** | ITS (PDP-10) | present but logins broken | ✅ network logins fixed | (ITS fixes below) |
| **#126 HILTON** | **KA-10 ITS** (HILTON-KA1) | commented plan | ✅ running (`@L 126`, port 10015) | `mini/host126/` |

### Subsystems & engineering we added
- **ITS network logins** (Civitae `feature/its-ncp-debug`): `pdp10-ka-fixed` (KAIMP interrupt
  fix, PDP-10/its #2376 — ITS now answers network logins), Chaosnet-enable (fixes KA ITS 1652
  panic on first NCP connection), `localhost`→`127.0.0.1` in IMP host-attach (silent-failure
  fix), `@O` old-Telnet (socket 1) plumbing through `do.sh`/`dotelnet.sh`. **+ uncommitted WIP
  on Civitae** (`mini/noc/server/ncp.py`, `mini/src/ncpd-ovREUSE/src/ncp.c`,
  `mini/src/waits-ncpd/waitsconnect.c`, `imp06.simh`) — preserved in the import (see below).
- **Event-driven per-IMP NCP startup** (`mini/noc-server.py`) — replaced a fixed 35 s timer
  that raced IMP boot speed on faster hardware and left host interfaces peerless.
- **1822 host-ready emulator gate + FORCEDOWN lever** (`kx10_imp.c`) — for host69; see its
  notebook. (Currently only in the gitignored build cache + the host69 artifacts — TODO: land
  in tracked `src/sims/`.)
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

## Backfill TODO (giving each added effort a real notebook)
- [ ] `journal/host01-sigma/` — CP-V bring-up notes (currently only ctl script + kit).
- [ ] `journal/host06-multics/` — DPS8M integration.
- [ ] `journal/host11-waits/` — WAITS + PARRY restoration (have `docs/host11-*.md` to fold in).
- [ ] `journal/host65-ucla-ccn/` — status/goal (least documented).
- [x] `journal/host69-bbn-tenex/` — done (`docs/host69-ncp-login-investigation.md` + artifacts).
- [ ] `journal/its-network-login/` — the `feature/its-ncp-debug` story + the Civitae WIP diff.
- [ ] Vault + `PROVENANCE.md` for the runtime packs/snapshots/tapes (DO droplet + Civitae).
- [ ] Land `kx10_imp.c` patches (host-ready gate + FORCEDOWN) in tracked `src/sims/`.
