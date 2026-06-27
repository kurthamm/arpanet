# What I learned researching the NETSER / FAIL build (2026-06-27)

Deep research into FAIL, build-tenex, SAILDART, bitsavers, and the FAIL v11 source itself.
This is the authoritative understanding — stop guessing the operator semantics.

## 1. FAIL operator semantics — DEFINITIVE (from FAIL v11 source flag table, lines 693-720)
```
LACF   ← OR :            (left-arrow = assignment, like = )      → ASCII _  (0137)
DBLF   DOUBLE ← (←←)     (stronger/permanent define)            → ASCII __
UPARF  UP ARROW (↑)      (symbol attribute; ↑ OR ~ tilde)       → ASCII ^  (0136)
DAF    DOWN ARROW (↓)    (symbol attribute; "↓ OR ?", src:5089) → ASCII ?  (077)
        ↔ = "DOUBLE ARROW. SIMULATE CRLF" (src:3883) = statement separator
GLOBF/INTF = global/internal symbol flags
```
So the SAIL→TENEX charset map I used (←→_, ←←→__, ↑→^, ↓→?) is CORRECT. The cusp sources
(STALLM/NETSER) and FAIL's own source all use these. They are STANDARD FAIL operators.

## 2. The modern reconstruction (build-tenex) NEVER builds network login
- build-tenex deliberately builds a MINIMAL TENEX: monitor + EXEC + a few subsys (MACRO, LOADER,
  FAIL, CCL, DLUSER, PAT, TECO, DUMPER via `install/simh/build.do`). NETSER / the FAIL cusps are
  OUT OF SCOPE — `build.do` doesn't build them, and `install.do` even comments out `build.do`.
- So **TENEX ARPANET network login has never been rebuilt in the modern PDP-10 preservation
  effort.** This is a genuine open frontier, not merely a local failure.
- build-tenex README confirms our other findings as KNOWN issues: "MINI-DUMPER can't read or
  write tapes properly" (= our DUMPER BUGHLT 140046) and "Rebooting ... doesn't work" (= CHKBT wedge).

## 3. Why each on-box FAIL fails — they are different INCOMPLETE versions
A complete FAIL needs: `'` (macro concat), `←←`/`__`, `↑`/`^`, `↓`/`?`, `IFAVL`, and correct
`()`-in-macro-arg handling. The on-box FAILs each lack a different piece:
- build-tenex `fail.sav` (v10, TOPS-20-bootstrapped, committed binary): dies PAGE 2 (STALLM
  FORWARD) — `'`/`^`/`?` concat incomplete. Its OWN source uses ^/? 209x though.
- imsss `fail.sav.1` (SUMEX): furthest on NETSER (PAGE 8-19) — has `'`,`^`,`?`; but rejects
  `__` at top level and mangles `()` in deep macro args.
- imsss `tnxfail.sav.7` (TENEX FAIL): runs; dies PAGE 2 like build-tenex.
- imsss `aifail.sav.5` (Stanford AI FAIL): dies PAGE 7 (no `'` concat → NOT IDENT AFTER IFDEF).
The ONLY fully-capable one is **SAILDART FAIL v11** (`FAIL[CSP,SYS]`, VFAIL←←11, 1976) — single
file, TENEX conditional, all operators. But it's WAITS-side source; bootstrapping it on bare
TENEX is circular (its source uses the very operators a lesser FAIL lacks: imsss chokes on its
`__`, build-tenex would choke on its `?`).

## 4. The real bootstrap vector = TOPS-20 V3A (already in build-tenex/t20v3)
build-tenex bootstrapped its toolchain by running a COMPLETE DEC system: `t20v3/run_a.ini` boots
TOPS-20 V3A (KL10, RP06 `dsk/kla_psv3_0.rp06`). A full TOPS-20 has DEC's complete MACRO/FAIL.
**This is the promising path to a complete FAIL:** boot TOPS-20 V3A, build FAIL v11 there (it has
the TENEX conditional via `IFDEF JSYS`), transfer the FAIL-v11 binary to our TENEX, then build
NETSER. This mirrors exactly how build-tenex made its FAIL. (Caveat: must confirm TOPS-20 V3A's
on-disk FAIL/MACRO assembles the v11 source — itself a real test.)

## 5. No prebuilt NETSER / complete FAIL binary exists in the archives
bitsavers `/bits/BBN/Tenex/` = source only; PDP-10/tenex GitHub = source; SAILDART = WAITS .DMP
binaries (wrong platform for TENEX); no community BBN-TENEX disk image ships built cusps.

## Bottom line
Authentic `@L 69` login needs NETSER, which needs a complete FAIL. The fully-capable FAIL exists
only as source (SAILDART v11). The realistic route is the **TOPS-20 V3A bootstrap** of FAIL v11
(the same vector build-tenex used), OR recovering a real SUMEX/BBN `<SUBSYS>` dump containing a
built FAIL or NETSER. Everything downstream (transport via DECtape+COPY, link, herald, ENTFLG,
snapshot) is already solved and proven.
