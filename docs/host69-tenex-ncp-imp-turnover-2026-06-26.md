# Host #69 BBN-TENEX — NCP/IMP session turnover (2026-06-26)

**Branch:** `host69-tenex-ncp-imp`  ·  **Author:** Kurt Hamm + Claude
**Read this with** `docs/host69-tenex-ncp-imp-handoff.md` (older; its §0 framing is now
partly SUPERSEDED — see the reframing below) and memory `host69-tenex-authentic-goal.md`
(now carries a 🛑 2026-06-26 correction block at the top).

---

## 0. TL;DR — the one thing that changes everything

**The blocker was misdiagnosed in every prior session.** All the "NCP won't come up /
CONI-CONO bit mismatch / NO SYSJOB" work was done on a **half-booted (wedged) TENEX**.

- The **"fast" reboot-from-snapshot boot** (`build-tenex-bootinstalled-ncp.do`,
  `reboot-test.sh`, the 14-hour ki found running at session start) **wedges INFINITELY in
  `CHKBT`** — the disk bit-table consistency check — **before the IMP fork is ever created.**
- So `IMPBEG` (creates the NCP fork) never runs, `IMPRSS` (assigns the PI channel) never
  runs, `pia` stays `0`, no `TENEXCONO` ever fires. The "IMP polling" that looked like
  progress was just `IMPSV` periodic background device service, not the fork.
- **Only the install-to-live path (`CLOBBER=Y`, one pass) actually boots TENEX** to a
  live `!` EXEC. Verified this session.
- I **fixed a real emulator bug** in the IMP-ready/`IMPRSS` gating (below). It's correct
  at the CONI level but **not yet validated end-to-end**, because getting a *kept-alive*
  fully-booted TENEX is blocked by two harness issues (telnet-park exit + flaky install
  keystroke race).

**Next step:** land one clean install-to-live that stays alive, then watch for
`TENEXCONO` / `pia≠0` = `IMPRSS` ran = host→IMP NOP = NCP coming up.

---

## 1. The corrected blocker, proven step by step

Tooling: SimH breakpoints + the monitor disassembly `kit-cache/build-tenex/tenex.dis`
(has symbol annotations) + the monitor sources in
`kit-cache/build-tenex/install/monitor/` (`swpmon.mac;13`, `impdv.mac;3`, `dsk.mac;2`).

### Key addresses (verified against tenex.dis)
| symbol | addr (octal) | what |
|---|---|---|
| `rundd`   | 400153 | job-0 startup (RUNDD) |
| `CHKBT`   | 140464 | disk bit-table check; `CALL CHKBT` is at **400172** |
| (post-CHKBT) | 400176 | instruction right after `CALL CHKBT` |
| `$RUNNING DDMP$` TMSG | 400250 | swpmon.mac:819 |
| `DONSJ`   | (call at 400257) | swpmon.mac:827 |
| SYSJOB fork | 400260–400274 | swpmon.mac:828–844 (`<SYSTEM>SYSJOB.SAV` GET) |
| `SPCSTJ`  | (call at 400276) | first auto job |
| `impbeg`  | 131331 | **creates the NCP fork**; `CALL IMPBEG` at **400277** |
| `IMPSV`   | 131076 | PI interrupt-service entry (`XWD IMPSVX,IMPSV+1`) |
| `IMPSV+1` | 131077 | `CONSO IMP,7` — the periodic poll seen in CONI debug |
| `IMPSTB`  | 136777 | `impdv.mac:4207` — bring-up state machine (in the fork) |
| `IMPRSS`  | 137143 | `impdv.mac:4321` — assigns the PI channel (in the fork) |
| `dlckr1`  | 105144 | disk-lock success path (a hot spot during the wedge) |
| gate vars | imprdy=70203, neton=70204, nettch=70225, impdrq=70224, imprdl=70214, imprdt=70215 |

### The proof chain
1. Live ki + my probes: `IMP CONI` debug shows **PC=131077 / 131105 only** (= `IMPSV`,
   the interrupt service), never the fork's `IMPSTT`/`IMPSTB` (≈136777). `chkint` STATUS
   was only ever `002000` (IMPR) — the emulator **never actually posts an IMP interrupt**;
   `IMPSV` is just periodic background (~370 polls total, not a storm).
2. Break at **136777 (IMPSTB)** never fires → the fork loop never runs.
3. Break at **131331 (IMPBEG)** never fires in 2e9 cycles → the fork is never *created*.
4. Break at **400176 (post-CHKBT)** never fires → `CALL CHKBT` (400172) never returns.
5. Break at **105144** fires instantly → **the break mechanism works**; (4)/(3)/(2) are
   real, not tooling artifacts.
6. Console markers across ALL logs: `RUNNING DDMP` = 0 occurrences ever; `NO SYSJOB` = 0;
   `NO CHECKDSK` appears only in old *install* logs. So no boot ever passed `$RUNNING
   DDMP$` (400250) via the reboot path.
7. `CHKBT` (`dsk.mac:531`) calls `DSKLBT` (`DLOCK SYSLCK` then sets MMAP write bits) then
   the bounded `CHKB0` scan over `DSKBTB`. The hot spots during the wedge are the disk
   lock (`dlckr1` 105144) and the KI page-fault/trap handler (`kitrps`/`kitrpm` ~116510)
   → the wedge looks like `CHKB0` page-faulting to load bit-table pages from disk where a
   disk read loops/never resolves. **Inherent to the reboot path** (confirmed: wedges even
   on a freshly `CLOBBER=Y`-installed disk). Matches the long-known
   "reboot-from-installed-snapshot is broken-by-design" note in memory.

### Consequence
`swpmon.mac` RUNDD order is: `CHKBT`(769) → `$RUNNING DDMP$`(819) → `DONSJ`(827) →
SYSJOB fork(829) → `SPCSTJ`(848) → **`IMPBEG`(849)**. The wedge at CHKBT(769) is *upstream
of all of it*, so **SYSJOB was never the blocker** — job 0 never gets near it. Every
"RDY=1 / inbound validated / pia=000 outbound blocker / CONI-bit mismatch" finding in the
older handoff was observed on this wedged, fork-less system and does not describe a real
NCP problem.

---

## 2. The emulator fix I made (correct; unvalidated end-to-end)

**File:** `mini/host69-bbn-tenex/kit-cache/rcornwell-sims/PDP10/kx10_imp.c`
(working-tree edit, **rebuilt** `BIN/pdp10-ki`, **NOT committed**, **NOT in the .patch yet**).

**Bug:** `IMPRSS` (`impdv.mac:4321`, dis 137143) assigns the PI channel ONLY when power
(0200000) is ON **and the imp-ready line 1B22 (020000) is OFF**:
```
137143 IMPRSS: CONSZ IMP,1B19   ; power on?
137144         CONSZ IMP,1B22   ; ready line OFF?  (skip-if-zero)
137145         RET              ; bail if ready already on
137146         CALL IMPRSN ...  ; else: assert host-ready (CONO 1B19), assign PI, NOPCNT=3
```
The emulator's CONI was forcing `*data |= 0220000` (power **and** ready) whenever `IMPR`
was set, so `IMPRSS` always saw "already up" → `RET` → never assigned `pia`. The old code
comment claiming "IMPRSS requires BOTH 0200000 and 0020000" was **backwards**.

**Fix (4 edits):**
- Added `int host_ready;` to the IMP data struct.
- In the ncp CONO handler, on `*data & 0200000` (host asserts host-ready, 1B19) →
  `imp_data.host_ready = 1;`
- In the ncp CONI handler: always surface power 0200000 when `IMPR`; surface the
  ready-line 0020000 **only if `host_ready`** (matches real 1822: IMP responds ready only
  after the host enables the interface).
- Clear `host_ready=0` in `imp_reset` and `imp_attach`.

**Verified:** CONI now reads `200000` (power on, ready OFF) at boot instead of `220000`,
so IMPRSS's precondition is satisfied. **Not yet verified that `pia` gets assigned** —
that needs a fully-booted system (see §4).

---

## 3. Dead-ends and things tried this session (so they aren't re-tried)

### Measurement / probing dead-ends
- **Live memory examine via console Ctrl-E injection** → FAILED. The sim never broke to
  `sim>`. Root cause: this build sets **`set console wru=034`** (in
  `build-tenex-hardware-ncp.do`), so the SCP break char is **Ctrl-\ (034), NOT Ctrl-E
  (005)**. pyconsole's CMD-injection sends 005.
- **Patched pyconsole to send 034** → still no SCP output over the telnet console. SimH's
  telnet console doesn't reliably honor the WRU break through telnet negotiation. Live
  injection of `examine` over the running telnet console was abandoned.
- **Killing pyconsole to free 2323 and connecting a dedicated examine script** → KILLED
  the sim. Dropping the 2323 telnet console makes `go 100` return ("go-returns-on-
  console-drop"), and the driver then runs its post-go commands and exits. **Do not drop
  the console of a running ki.**
- **`probe-impstb.do` (the prior session's probe)** → never produced output: its `break
  136777` line was **silently skipped** because a duplicate `set console telnet=2323`
  (the hardware include already sets the console) corrupted the .do line sequencing
  ("No settable parameters", do-11 ran twice, do-12 skipped). Lesson: don't re-`set
  console telnet` when the include already did; put `break` on a clean line.
- **`runlimit 4000000000 cycles`** → `%SIM-ERROR: Invalid argument` (exceeds int32). Use
  `runlimit 2000000000 cycles` (the proven `syslod-break-*.do` value).
- **Trusting the runlimit-stop PC** as "where it's wedged" → MISLEADING. It stops wherever
  the busy code happens to be (saw 116510 trap handler, 105144 disk lock, 114326). Use
  *breakpoints at specific addresses* to localize, not the runlimit-stop PC.

### Boot-path dead-ends
- **bootinstalled / reboot-from-snapshot (`CLOBBER=N`)** → WEDGES in CHKBT, never reaches
  a live EXEC. Tried on the stale installed disk AND on a freshly-installed disk — wedges
  both times. This is the path the 14-hour ki and all prior "stable running TENEX"
  observations used; it is **not** a working boot. Do not use it to test NCP.
- **Interpreting the IMPSV CONI polling as "the IMP working"** → WRONG. It's periodic PI
  background service (device-init assigned the channel at `netini`), not the fork.

### Emulator-theory dead-ends (ruled out before finding CHKBT)
- **"IMPSVX interrupt storm" hypothesis** → ruled out: `chkint` STATUS only ever `002000`
  (IMPR); `set_interrupt`/`set_interrupt_mpx` are both no-ops when the PI channel is 0
  (`if (lvl)`), so the emulator never posts an IMP interrupt with `pia=0`. The ~370
  CONI reads are a slow periodic poll, not a storm.
- **"SYSJOB is the blocker" (older handoff)** → ruled out: job 0 wedges at CHKBT, which is
  upstream of the SYSJOB fork in RUNDD. `IMPBEG` is called unconditionally after the
  SYSJOB step regardless of whether SYSJOB loads (`swpmon.mac:835-849`), so SYSJOB is not
  a prerequisite for the NCP fork anyway.

### Install-harness dead-ends
- **install-to-live with telnet-console park** (`build-tenex-live-ncp-impdbg.do`) →
  installs FULLY (reached `TENEX IN OPERATION` → EXEC 1.51 → DLUSER `DONE.` → parks) but
  the final `go` **returns and the sim exits** the moment a console connects to 2323
  (go returned at PC 114326). Can't observe the post-boot IMP bring-up this way.
- **install-to-live with stdout-console park** (`build-tenex-live-ncp-watch.do`, created
  this session) → the install **garbled at the live-EXEC `GET DTA0:EXEC.SAV` keystroke
  step** (console froze at "GET DTA0:EXEC." with ".SAV" lost) — the known flaky SIMH
  expect/send keystroke race. The earlier impdbg run cleared this same step, so it's an
  intermittent race, ~50/50, not a deterministic failure.

---

## 4. What works + the exact next step

**install-to-live boots TENEX fully** (verified this session, old + new binary):
`run-h69-impdbg.sh` → `build-tenex-live-ncp-impdbg.do` does `CLOBBER=Y` → INIT BIT TABLE →
boot → GET/SSAVE EXEC.SAV → DLUSER `DONE.` → live `!` EXEC. RUNDD completes ⇒ the IMP fork
runs ⇒ `IMPRSS` will be attempted.

**To finish (validate the fix):**
1. Run a clean install-to-live with the new binary + the test IMP, parking on the
   **stdout** console (not telnet) so the sim stays alive and IMP debug streams to the log.
   Driver ready: `runtime/build-tenex-live-ncp-watch.do`; runner ready:
   scratchpad `run-watch.sh` (starts `imp69-hi2only` first, resets disk, drains
   16945/16946, launches the watch driver).
2. The install keystroke step is flaky (`GET DTA0:EXEC.SAV` race). If it garbles, just
   re-run; it succeeds intermittently. (A more robust fix: human-pace the sends, or add
   small `sleep`s between the GET/SSAVE expect/send lines.)
3. Once it reaches `=== PARKED ON STDOUT CONSOLE ===` and `go`, watch
   `logs/host69-watch.log` for **`TENEXCONO`** and a CONI line with **`pia` ≠ 000**.
   - `pia≠0` / `TENEXCONO` = `IMPRSS` ran = host asserted host-ready + assigned channels =
     host→IMP NOP should follow → check `logs/imp69-test.log` for a packet **received
     from** host69 = bidirectional 1822 handshake = NCP coming up.
4. If `pia` still stays 0 with a fully-booted system, re-open the IMPRSS path with the
   gate-var probe (now that the fork actually runs): break at **137143 (IMPRSS)** and
   single-step the `CONSZ IMP,1B19/1B22` to see which guard bails.

**Console break char for this build is Ctrl-\ (034), not Ctrl-E.**
**Safe test IMP:** `mini/imp69-hi2only.simh` (hi2 only on 21051/21052; start it BEFORE
host69 binds 21052). Never `pkill -f` a simh name (self-matches the shell); kill h316ov by
PID and only the `imp69-hi2only` one — never the 35 live lab IMPs.

---

## 5. Files created / modified this session

**Emulator (rebuilt, NOT committed, NOT in the .patch):**
- `mini/host69-bbn-tenex/kit-cache/rcornwell-sims/PDP10/kx10_imp.c` — `host_ready` field +
  CONO 1B19 set + CONI ready-line gating + reset/attach clear (the IMPRSS fix). Rebuilt
  `BIN/pdp10-ki` (2026-06-26 ~17:03).

**Drivers added (`mini/host69-bbn-tenex/runtime/`):**
- `probe2-impstb.do` — clean IMPSTB probe (no telnet console; break-based).
- `probe3-impbeg.do` — break at IMPBEG (131331) to test fork creation.
- `probe4-rundd.do` — staged breaks 400176/400217/400250 to bisect the RUNDD wedge.
- `probe5-validate.do` — break 105144+400176 to validate the break mechanism.
- `build-tenex-live-ncp-watch.do` — **install-to-live, stdout park, IMP debug** (the one
  to use for the next validation run).

**Scratchpad harness** (`/tmp/claude-1000/.../22e8052b-.../scratchpad/`):
- `run-probe2/3/4/5.sh`, `run-fullboot.sh`, `run-watch.sh`, `run-probe.sh`
- `pyconsole.py` (patched to send 034), `drain.py`, `examine.py`

**Memory updated:** `host69-tenex-authentic-goal.md` (🛑 2026-06-26 correction block at
top) and `MEMORY.md` index line.

---

## 6. Production cutover — still HELD
Unchanged and still gated on a validated boot (see `host69-production-cutover.md`). Do not
touch live imp05 / the website until host→IMP NOPs are proven on a fully-booted TENEX.
