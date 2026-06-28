# Investigation raw artifacts — 2026-06-27/28

The **raw scripts, logs, and patched emulator source** behind the narrative in
`docs/host69-ncp-login-investigation.md`. These were in gitignored (`runtime/`, `logs/`) or
ephemeral (`/tmp` scratchpad) locations and would have been lost; preserved here so the
investigation is fully reproducible/auditable, not just summarized.

Paths in the `.do`/`.sh` files are absolute and session-specific (snapshot + scratch paths) —
they are a **record of what was run**, not turn-key scripts. The full turn-by-turn transcript
lives outside the repo at `~/.claude/projects/-home-deltaprism-arpanet/ef23d23f-….jsonl`
(not copied here; ask if a redacted copy is wanted).

## emulator-patch/
- `kx10_imp.c.patched` — the patched rcornwell IMP device. Contains BOTH emulator fixes: the
  **host-ready 1B22 gate** (CONI leaves 1B22 clear during normal up; host_ready set by CONO 1B19)
  and the **FORCEDOWN lever** (`imp_force_down` global + `FORCEDOWN` reg + CONI surfaces 1B22 on
  demand). The repo's tracked `src/sims/PDP10/kx10_imp.c` does NOT yet have these (TODO).

## do-scripts/  (what each one tested)
- `forcedown-hostready.do` — **WORKS**: FORCEDOWN down/up cycle re-asserts host-ready (ncp31→69
  flips "Host is not up" → reachable).
- `trace-rfc.do` — **the key probe**: DEBUG_IRQ recv trace; proved the `@L 69` RFC reaches host69.
- `diag-buffers.do` — proved NOT buffer starvation (IMPNFI=8) and FORCEDOWN-exonerated.
- `diag-forcedown.do` / `diag-recycle.do` — gate-var examines (imprdy/impdrq/imprdl; found the
  recycle completes ~10s after restore; CONI GATE probe).
- `recycle-v2.do` — **the decisive dead end**: real FORCEDOWN-while-UP down/up with NETDWN; the
  25 stuck conns SURVIVED → recycle cannot clear them.
- `recycle-step.do` / `recycle-forcedown.do` / `reset-semantic.do` / `reset-table.do` /
  `reset-clean.do` / `calib.do` — the earlier failed recycle/reset variants (IMPDRQ poke;
  table-zap that SEGFAULTED; step-count calibration). The full dead-end set.
- `build-tenex-inspect-faithful.do` — the stdio-console inspect harness that SEGFAULTS (proved
  the crash is console-mode, not missing media).

## launchers/
- `launch-*.sh` — the harnesses that drove the above (stop old ki, drainers, console-daemon on
  2323, run ki with a given .do). `launch-do.sh`/`launch-reset.sh` are the generic/early ones.

## logs/  (the evidence)
- `host69-trace.log` — the DEBUG_IRQ trace incl. `IMP ncp recv poll#5217 nw=7 … link=0` = the
  RFC arriving at host69.
- `host69-diag.log` — the IMPNFI=8 buffer exam + link_up toggling (STATE A vs B).
- `dc16945.log` — the TENEX console: `NETWORK ON, IMP ON/OFF` cycles + the `IMPBUG … 132445`
  metronome.
- `exam-output.log` — the offline snapshot exam (B'): the IMPLT1/2/3 line-table dump (25 active
  slots, all IMPLT3=0).
- `inspect-console.log` — the `notelnet` console SEGFAULT evidence.
