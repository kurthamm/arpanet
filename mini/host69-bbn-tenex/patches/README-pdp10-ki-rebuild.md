# Rebuilding the host69 BBN-TENEX `pdp10-ki` emulator

The `pdp10-ki` that runs host69 (real BBN-TENEX, native NCP login) is a patched
build of Richard Cornwell's SIMH (`rcornwell/sims`). The patched **source** normally
lives only in the gitignored build cache
(`mini/host69-bbn-tenex/kit-cache/rcornwell-sims/`), so this directory captures the
complete patch so the emulator is reproducible from a clean clone.

## Authoritative patch
`host69-pdp10-ki-COMPLETE.patch` — the full diff from the pristine upstream baseline
to the exact working tree that built the running ki (all local commits
`fa21f3b`..`37744c0` **plus** the uncommitted `kx10_cpu.c`/`kx10_imp.c` work). It
touches 8 PDP10 sources and includes the critical host→IMP output-done fix
(`uptr->STATUS |= IMPOD`) that the older `investigation-2026-06-28/.../kx10_imp.c.patched`
copy was missing.

- **Upstream baseline commit:** `rcornwell/sims` @ `9510a91f4c7cb001293a57682de62102d6b07437`

## Rebuild from a clean clone
```sh
git clone https://github.com/rcornwell/sims.git rcornwell-sims
cd rcornwell-sims
git checkout 9510a91f4c7cb001293a57682de62102d6b07437
git apply /path/to/host69-pdp10-ki-COMPLETE.patch
make pdp10-ki           # -> BIN/pdp10-ki
```
The resulting `BIN/pdp10-ki` is what `host69ctl.sh`/`arpanet-host69.service` run to
restore the golden TENEX snapshot.

## Note
This supersedes the stale `investigation-2026-06-28/emulator-patch/kx10_imp.c.patched`
(kept for history). If you further patch the ki, regenerate this file with:
`git -C kit-cache/rcornwell-sims diff 9510a91f4c7cb001293a57682de62102d6b07437 -- PDP10/ sim_*.c sim_*.h > host69-pdp10-ki-COMPLETE.patch`.
