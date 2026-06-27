# host69 TENEX IMP/NCP host-ready recovery — HANDOFF (resume here)

**Date:** 2026-06-27.  **Branch:** `host69-tenex-ncp-imp`.  Next session is dedicated to this.
This is the read-first doc for resuming the ONE open blocker. Companion docs:
`NETLIT-STATUS.md` (NETSER-lite build/run), `lab-fix/README.md` (the noc routing fix).

## ⛔ GROUND RULE
`@L 69` (public ARPANET login to host 69) **remains DISABLED and must stay disabled** until
real EXEC/login AND a stable, reproducible host-ready path are captured. The tracked NCP route
`05:1:69:21051:21052:BBN-TENEX` in `mini/arpanet` is correctly commented; leave it commented.
This is private backend validation only.

## ✅ DONE & SOLID (committed; not the blocker)
1. **NETSER-lite (NETLIT) built, preserved, runs, listens on ARPANET socket 1.**
   - Source `netser-build/netser-lite.fai` (LF) / `NETCRL.FAI` (CRLF, what FAIL assembled).
   - Object `netser-build/netlit.rel` (3855 B, FAIL "PROGRAM BREAK 000206'"). Tape image +
     hashes in `netser-build/artifacts/`.
   - Run path proven: `LOADER` -> `*DTA1:NETLIT` -> `$G` -> EXEC `START` -> prints
     `NETLIT OPENING LISTEN SOCKET 1 / GTJFN OK / OPENF OK LISTENING` + GDSTS observe loop.
     (Requires NETWORK ON; OPENF a listen socket succeeds even with the IMP link idle.)
   - Build recipe (CRLF required; output to writable DECtape to dodge dskasn BUGHLT; one FAIL
     run per restart; kill -TERM to flush): see NETLIT-STATUS.md.
2. **Lab routing FIXED — event-driven NCP startup** in `mini/noc-server.py` (committed
   `6163bc9`). Was broken by my `systemctl stop/start arpanet-noc`; root cause = hardcoded
   `NCP_START_DELAY=35s` tuned for the slow 2-vCPU box, vs the faster upgraded host booting
   IMPs before 35s -> peerless host-interface errors. Fix = start each NCP when ITS IMP hits
   RUNNING (`_on_imp_state_change` -> `_start_ncps_for_imp`, idempotent; old timer kept as
   `_fallback_start_ncps` backstop). Backup `mini/noc-server.py.bak-preEventDriven`.
   **Verified healthy & left running:** 18/18 managed host-interfaces up, exactly 18 `ncpdov`
   (no duplicates), full speed (throttle back to 15% in `mini/impconfig.simh`), mesh `ncp-ping`
   replies (ncp1->2, ncp31->1, ncp2->35, ncp35->31, ncp1->31). `python3 mini/impctl.py status`.

## ⛔ THE OPEN BLOCKER — host69 <-> imp05 1822 host-ready not reproducible
host69 boots to the operator `!` and the **UDP wiring is correct**, but the **1822 host-IMP
"host ready" handshake does not complete**, so imp05 never advertises a route to host 69 and
the host is unreachable.

Evidence:
- imp05 runs `imp05.local.simh` (noc prefers `.local`, imp.py:79); `hi2` enabled,
  `attach -u hi2 21051:127.0.0.1:21052`. host69 reciprocal: `attach -u imp 21052:127.0.0.1:21051`,
  `set imp nodebug`. `show imp` on host69 = `attached to 21052:127.0.0.1:21051, NCP, BBN`. Correct.
- With host69 up first, then ONE `impctl restart 5`, hi2 socket goes **ESTAB** — but:
  `NCP=ncp1 ./ncp-ping 69` = **"Host is not up"**; `NCP=ncp1 ./ncp-telnet 69` = **hangs** (NOT
  the "Open refused" a prior fragile moment gave). So the ICP never reaches host69.
- tcpdump on 21051/21052 is ~quiet (1 pkt / 10-20s) — but that does NOT discriminate: a
  *working* host link (host1<->imp01, 20011/20012) is also ~quiet when idle. Packet volume is
  not the signal; host-ready STATE is.
- **imp05's hi2 is host69's interface, NOT an noc-managed ncpdov**, so the event-driven NCP fix
  does NOT cover it: if imp05 boots while host69 is absent, hi2 goes peerless and its socket
  closes. So host69 must exist before hi2 initializes (the dependency we satisfied by hand).
- Inspection (host69 in tmux, console on pane, `sim>`): IMP config correct; host69 resumes to
  `!` fine WITHOUT debug; **`set imp debug` + `cont` -> `BUGHLT 100561`** (likely the SIMH
  IMP-debug path flooding this flow-control-sensitive console, NOT proof the net code crashes —
  but it means IMP debug is unusable here). `show imp r`=just radix; `examine imp` needs a
  register name (unknown), so host-ready bits not readable that way.

Working hypothesis: the **restored TENEX is not reliably driving its IMP/NCP side** — its saved
internal IMP state (snapshot was "NETWORK ON, sends host->IMP 1822") is desynced from the fresh
UDP socket / fresh imp05, and it does not re-assert host-ready after re-attach. The prior single
"Open refused" was a fragile coincidental coherent state, not a reproducible wired path.

## NEXT-SESSION STARTING POINTS (host69-side, do NOT churn the lab)
- The lab is healthy and should be LEFT ALONE (don't `systemctl stop/start arpanet-noc`; if you
  must, the event-driven fix now makes a clean restart safe, but imp05's hi2 still needs host69
  present at boot). Verify with `mini/impctl.py status` + the ncp-ping set above.
- Bring host69 up: `bash netser-build/scripts/run-loginbuild.sh` (telnet console 2323), OR for
  `sim>`/DDT inspection use `runtime/build-tenex-inspect.do` in tmux (console on pane; WRU=`^\`).
  (Copy of the inspect .do preserved in `netser-build/runtime/`.)
- Questions to answer: (1) After restore+resume, does host69's TENEX actually have NETWORK ON
  and is it periodically asserting host-ready on the IMP device? (read the monitor's NCP/IMP
  status words via DDT, or the IMP CONI — my notes reference `CONI 200120`, `pia=050`). (2) Does
  it need a post-restore network/IMP re-init (a monitor command / DDT poke) to re-handshake with
  a freshly-attached IMP? (3) Is `BUGHLT 100561` debug-only, or does host69 crash on real IMP
  interrupts (re-test WITHOUT debug, host69 fresh, let it run while imp05 is up & hi2 ESTAB)?
- Consider: the durable fix is host69 lifecycle-started BEFORE imp05 boots, OR teach the noc a
  model for external host interfaces (hi2) so it doesn't boot an IMP host-interface peerless.

## ARTIFACTS / RESUME DATA
- `netser-build/`: `netser-lite.fai`, `NETCRL.FAI`, `netlit.rel`, `NETLIT-STATUS.md`,
  `lab-fix/` (noc patch+copy+writeup), `scripts/` (run-loginbuild, console-daemon, copyfile,
  drain, dskscan), `runtime/` (restore drivers incl. the inspect .do), `artifacts/` (tape image
  + SHA256SUMS).
- Live lab fix: `mini/noc-server.py` (committed) + backup `mini/noc-server.py.bak-preEventDriven`.
- Snapshot: `snap/host69-live.state` (the booted BBN-TENEX). host69 currently **stopped** (clean).
- Session transcript (full detail):
  `/home/deltaprism/.claude/projects/-home-deltaprism-arpanet/8b7f08a0-a8a0-45c1-9900-263c6de29ffb.jsonl`
