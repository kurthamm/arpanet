# Bootable-state provenance & vault status

The lab's **bootable binaries** — configured disk packs, booted-state snapshots, build tapes,
and compiled emulators — are too large for git and are **gitignored**. This documents *where
they are, which are irreplaceable, how to rebuild the rest, and their integrity checksums*, so
nothing critical silently lives on one disk with no record.

## Classes & inventory (droplet `~/arpanet`)
| Artifact | Path | Size | Class |
|---|---|---|---|
| host69 booted TENEX snapshot | `mini/host69-bbn-tenex/snap/host69-live.state` | 2.4M | **IRREPLACEABLE** — the SAVE/RESTORE breakthrough; **now committed to git ✅** (`.gitignore` exception) |
| host69 TENEX packs/tapes | `mini/host69-bbn-tenex/kit-cache/build-tenex/install/media/` | 12M (sparse) | configured (rebuild = long install) |
| Sigma 7 CP-V runtime | `mini/host01-sigma/` | 412M | configured (kit: `kenrector/sigma-cpv-kit`) |
| Multics runtime | `mini/host06-multics/` | 900M | configured (kit: DPS8M `QuickStart_MR12.8`) |
| OS/360 MVT runtime | `mini/host65-ucla-ccn/` | 635M | configured (kit: `cbttape.org` TURNKEY MVT) |
| ITS hosts (70/126/134/198) | `mini/host70,126,134,198/` | ~626M each | configured ITS packs |
| WAITS / PARRY | `mini/host11*/` | 1.3G | configured + PARRY restoration |
| `pdp10-ka-fixed` (KAIMP fix) | `mini/pdp10-ka-fixed` | 1.5M | **tracked in git** ✅ |
| host69 emulator (`pdp10-ki` NCP) | build cache (gitignored) | — | **rebuildable** from `netser-build/emulator-fork/` (patch+bundle, tracked) |

## Integrity checksums (the critical small artifacts)
```
0e0b689e36dac18397429e4a89fe7cf2eb8fb234f7036226295c307c006d0055  mini/host69-bbn-tenex/snap/host69-live.state
554e19e81e1379991fe73cbd036404fd81e1b667a06046c08a28d03105acb5c0  mini/pdp10-ka-fixed
```
TODO: a full `SHA256SUMS` manifest over every pack/snapshot/tape (so a recovered copy can be verified).

## Where copies exist
- **Droplet** (`arpanet-do`, this box) — primary/live.
- **`~/arpanet-runtime-backups`** (droplet, **25G**) — timestamped pack backups, but *same machine*
  (not disaster-durable).
- **Civitae** (old server, Tailscale `100.120.170.123`) — a cold copy of the **upstream + ITS-line**
  packs. **Does NOT have host69** (host69 is post-migration droplet work) — so the host69
  snapshot/packs are **single-machine**.

## Rebuild recipes (what's recoverable without the blobs)
Each host `*ctl.sh` fetches its **public OS kit** and can rebuild the *base* system:
`host01-sigma` (sigma-cpv-kit), `host06-multics` (DPS8M MR12.8 QuickStart),
`host65-ucla-ccn` (cbttape OS/360 MVT). The emulator (`pdp10-ki`) rebuilds from
`netser-build/emulator-fork/`. **What is NOT auto-rebuildable** is the *configured/installed*
state on top of each base — especially the **host69 booted-TENEX snapshot**, which required the
manual SAVE/RESTORE install documented in `docs/host69-tenex-install-findings.md`.

## Distribution policy (resolved)
- **The crown jewel — the host69 booted-TENEX snapshot (2.4M) — is now committed to git** and
  rides to GitHub, so the single most irreplaceable, hardest-won artifact is durable and
  versioned off-box. (A `.gitignore` exception keeps the rest of `snap/` ignored.)
- **The large per-host disk images (~6G) are NOT distributed in this repo** — too big, and they
  contain configured/installed state. They live on the droplet (+ `~/arpanet-runtime-backups`
  25G, + a Civitae cold copy for the upstream/ITS-line packs). **To obtain them, contact the
  maintainer** (Kurt Hamm — `kurthamm` on GitHub, or `kurt@hamm.me`).
- The base OSes are rebuildable from public kits via each host's `*ctl.sh` (see Rebuild recipes
  above); only the *post-install configured* state requires the maintainer's copy.
