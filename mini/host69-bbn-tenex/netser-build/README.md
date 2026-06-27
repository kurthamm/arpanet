# Host #69 BBN-TENEX — NETSER (network login server) build effort

Goal: authentic 1972 experience — `@L 69` → `BBN-TENEX` herald → `@LOGIN` → run a scenario.
The one missing piece is **NETSER**, the userland ARPANET logger that listens on ICP socket 1,
sends `<SYSTEM>NETWORK-LOGINMESSAGE` as the herald, and runs `<SYSTEM>EXEC.SAV`. Without it the
live monitor answers but **refuses socket 1** (`ncp-telnet 69` → "Open refused").

This dir preserves the build effort so it isn't re-derived. Full narrative + exact addresses are
in memory `host69-netser-build-attempt.md` and `docs/host69-tenex-ncp-imp-turnover-2026-06-26-v2.md`.

## State of play (2026-06-27)
- **Transport SOLVED:** get files onto the live TENEX disk via a TENEX DECtape made with
  `kit-cache/build-tenex/install/tools/tendmp -T -L TENEX -b boot/dtboot.bin -c out.dta <files>`
  (host dir name → TENEX `<DIR>`), attach as `dt1`, then on TENEX `MOUNT DTA1:` +
  `COPY DTA1:X.SAV <SUBSYS>X.SAV`. DO NOT use DUMPER-LOAD (BUGHLT 140046) or GET/SSAVE of foreign
  saves (corrupts the EXEC). FAIL runs once `<SUBSYS>PA1050.SAV` (the real one,
  `imsss/files/subsys/pa1050.sav.20`) is present.
- **Assembler is THE blocker.** STALLM's macros need a FAIL with: `'` concat, `↑`/`↓` declare
  operators (= `^`/`?`), `IFAVL`, and correct `()`-in-macro-arg handling. The 4 on-box FAILs are
  all v10-era and each missing one feature (build-tenex/tnxfail: no `↑`/`↓` → die PAGE 2;
  imsss: no IFAVL + mangles `()` → furthest, PAGE 8-19; aifail: PAGE 7).
- **The fix = FAIL v11** (SAILDART `FAIL[CSP,SYS]`, 1976/77) — the only version with ALL features.
  `fail-v11-saildart.fai` here is the raw SAIL-charset source. `fail-v10-buildtenex.fai` is
  build-tenex's TENEX-charset v10 source (proves FAIL is buildable on this TENEX → `fail.sav`).

## SAIL → TENEX charset map (confirmed by diffing the two fail.fai)
`←` (U+2190) → `_` (0137) ;  `←←` → `__` ;  `↑` (U+2191) → `^` (0136) ;  `↓` (U+2193) = declare-op.
Math/Greek (≥⊂¬∧∃∨∂ε→≠↔⊗) appear in comments/SUBTTL — safe to map loosely. `⊗` = COMMENT delim.

## Files
- `fail-v11-saildart.fai`  — FAIL v11 source (SAIL charset, from saildart.org). The target build.
- `fail-v10-buildtenex.fai`— FAIL v10 source build-tenex builds (reference / diff base).
- `netser-ported.fai`, `stallm-ported.fai` — partial port to the imsss v10 FAIL (SETACA/IFAVL
  removed, 16 nested-LOAD args hoisted, `<<X>>`→`<X>`). Reached PAGE 8-19 before the `()` wall.
  Kept for reference; the v11 path uses the ORIGINAL kit sources instead.
- `build-tenex-restore-loginbuild.do` — restore snapshot + attach dt0=syslod (DUMPER), dt1=login.dta
  (tools), mta0=login.tap; ENTFLG=-1 deposit.
- `build-tenex-restore-entflg.do` — plain restore + ENTFLG=-1 (login-gate enabled).
- `say.sh` / `copyfile.sh` / `loadsav.sh` / `run-loginbuild.sh` — console-drive + DECtape-copy helpers.

## Build plan (FAIL v11 bootstrap)
1. Convert `fail-v11-saildart.fai` to TENEX charset; strip SAIL E-editor page directory.
2. DECtape it onto TENEX; assemble with the on-box (v10) FAIL → `<SUBSYS>FAIL.SAV` v11.
   Risk: v11 source uses `↓`; v10 may not grok it (self-hosting circularity) — fall back to porting
   just the `↑`/`↓`+IFAVL additions into the known-good `fail-v10-buildtenex.fai`.
3. With FAIL v11: `FAIL NETSER_STALLM,NETSER` → `NETSER.REL` → LINK10/LOADER → `<SYSTEM>NETSER.SAV`.
4. Create `<SYSTEM>NETWORK-LOGINMESSAGE` (BBN-TENEX herald); `ENTFLG=-1`; `@ENABLE` `RUN <SYSTEM>NETSER.SAV`.
5. Test `ncp-telnet 69` / `@L 69` → herald → login; SIMH SAVE a new snapshot (captures running NETSER).
