# host69 emulator fork — authentic 1822-over-UDP NCP for BBN-TENEX

**This is the crown-jewel emulator work that makes host69 connect to the ARPANET at all, and it
lived ONLY in a gitignored build cache** (`mini/host69-bbn-tenex/kit-cache/rcornwell-sims`,
which is a clone of `github.com/rcornwell/sims`). Preserved here in tracked form so a fresh
clone can rebuild it. **`src/sims` is an upstream submodule, so we cannot commit into it; this
patch/bundle is the durable record until/unless we publish a proper `rcornwell/sims` fork.**

## What it is
Adds `set imp ncp` (`UNIT_NCP`) — an **authentic 1822 host-IMP interface over UDP** for a BBN
host (TENEX) talking to an H316 IMP (`imp05` `hi2`): the TENEX-faithful BBN `CONI`/`CONO` bit
layout (decoded against `impdv.mac`), the host-ready line gating, the IMP PI-channel /
interrupt handling, the input-armed (`STRIN`) delivery model, and the `FORCEDOWN` diagnostic
lever. Design rationale and the full investigation: `docs/host69-ncp-login-investigation.md`.

## Base & provenance
- **Base:** rcornwell/sims commit **`9510a91`** ("KA10: Fixed DP seek done…", 2026-03-08).
- **Our 8 commits on top** (the journey) — see `COMMITS.txt`. Summary, oldest→newest:
  `fa21f3b` add 1822-over-UDP `set imp ncp` → `9eaf68f` gate inbound input until host drives →
  `a438d50` drive the host↔IMP 1822 handshake → `877cde5` single-PI-channel output-done →
  `33f226e` TENEX-faithful BBN CONI/CONO → `2ee4d76` keep UDP polling + surface IMP-ready →
  `a483514` recv/gate diagnostics → `842109e` FORCEDOWN lever (preservation snapshot).

## Files changed (signal vs noise)
- **`PDP10/kx10_imp.c`** (+371) — the NCP host-interface core. **The signal.**
- **`PDP10/imp_udp.h`** (new, +28) — the 1822-over-UDP transport header.
- **`PDP10/kx10_cpu.c`** — ~65 *real* lines (IMP interrupt / PI-channel) but the file diff is
  huge because it was also re-saved with changed line-endings (whitespace noise). View the real
  lines with `git diff -w`, or see `host69-ncp-CORE-readable.patch`.
- `kx10_dt.c` (+150, DECtape for the build tapes), `kx10_cty.c`/`kx10_tym.c` (console/TYM draining),
  `kx10_disk.c`, `scp.c`, `makefile` — small supporting changes.

## Artifacts here
- **`rcornwell-sims-host69-ncp.bundle`** — *primary, complete*: all 8 commits with history/messages.
- `host69-ncp-1822-over-udp.FULL.patch` — complete applyable diff (bloated by the cpu whitespace).
- `host69-ncp-CORE-readable.patch` — human-readable: imp device + udp header + cpu real lines (`-w`).
- `COMMITS.txt` — the commit log.

## Reproduce
```sh
git clone https://github.com/rcornwell/sims && cd sims
git checkout 9510a91
# preferred — restore our exact commits with history:
git bundle unbundle /path/to/rcornwell-sims-host69-ncp.bundle
git checkout 842109e        # our HEAD
# OR apply the flat patch instead of the bundle:
#   git checkout 9510a91 && git apply /path/to/host69-ncp-1822-over-udp.FULL.patch
make pdp10-ki               # needs SDL2/pcap/zlib/edit; sanity check must print "Good Registers"
```
The resulting `BIN/pdp10-ki` is what `run-loginbuild.sh` uses to boot host69.

## TODO (ideal end state)
Publish a `kurthamm/sims` fork with these commits and point the `src/sims` submodule at it, so
the buildable emulator is a first-class tracked dependency rather than a preserved patch.
