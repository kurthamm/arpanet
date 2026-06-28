# Bootable-state provenance & vault status

The lab's **bootable binaries** — configured disk packs, booted-state snapshots, build tapes,
and compiled emulators — are too large for git and are **gitignored**. This documents *where
they are, which are irreplaceable, how to rebuild the rest, and their integrity checksums*, so
nothing critical silently lives on one disk with no record.

## Classes & inventory (droplet `~/arpanet`)
| Artifact | Path | Size | Class |
|---|---|---|---|
| host69 booted TENEX snapshot | `mini/host69-bbn-tenex/snap/host69-live.state` | 2.4M | **IRREPLACEABLE** (the SAVE/RESTORE breakthrough; droplet-only) |
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

## Risk & recommended vault (decision needed)
The irreplaceable, droplet-only items (host69 snapshot 2.4M; the configured packs) have **no
off-box durable copy**. Options, smallest-effort first:
1. **git-LFS** for the small-but-critical (`host69-live.state` 2.4M, the 12M build media) — cheap,
   versioned, off-box on push.
2. **Object storage / off-site backup** for the multi-GB per-host packs + a `SHA256SUMS` manifest
   in git.
3. At minimum, **mirror the host69 snapshot to a second machine** (it's only 2.4M) and add it to
   the timestamped backups.

No blobs were moved and the `.gitignore` policy was left unchanged — pick an option and I'll wire it up.
