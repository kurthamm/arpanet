# NETSER-lite (NETLIT) — Status & Handoff

## ★★★ MILESTONE 1c (2026-06-28, session 4) — FULL ICP SOCKET-SWAP WORKS; herald reaches the lab

`netser-lite-1c.fai` (the DOICP-lite socket-swap server) is built on-box and the **entire ICP
completes end-to-end.** host69's console walks the full sequence on one `@L 69`:
```
RFC RECEIVED → CONTACT ACCEPTED → SEND SOCKET NUMBER → SOCKET NUMBER SENT
→ OPEN DATA SOCKETS → DATA SOCKETS OPEN → HERALD SENT → DONE
```
The lab `ncpdov` confirms the complete NCP handshake: `Received STR … send 4/ALL …
Confirm STR, send RTS … Client got RTS, STR, and socket from server … Application open reply …
connection 1, error 0`. **No more "Open refused" — the client opens (error 0).** And the herald
bytes **traverse the ARPANET**: a lab strace caught `read(3, "…TENEX NETLIT TEST\r\n…") = 44` —
host69's herald arriving at the lab over the IMP link, byte size 8.

**The host69/NETLIT server side is DONE and correct.** The 1c source: listen socket 1 (contact,
byte size 32) → wait RFCR → `MTOPR fn20` accept → build `NET:<S>.<fhost>-<fskt+2>;T` (octal) →
GTJFN send+recv data JFNs → `CVSKT` the local socket → `BOUT` it on the contact → `CLOSF` contact
→ `OPENF` send (`103000,,100000`) + recv (`100000,,200000`, byte size 8) → `SOUT` herald on the
send JFN → DISMS drain → `CLOSF` → `HALTF`. Matches RFC 123/165 and the lab's own `ncp.c` (which
uses the TENEX `+2` foreign-data-socket convention, `ncp.c:791`, not RFC123's `U+1`).

**Remaining gap = lab-side, NOT host69:** the herald reaches the lab's NCP but `ncpdov` sometimes
fails to deliver it to the client *application* socket (`sendto /tmp/client.<pid> … Transport
endpoint is not connected`) — debris from heavy test churn (stale `/tmp/client.*` sockets, a
**duplicate** ncp31 daemon). After clearing debris the client open succeeds but the herald display
via `ncp-telnet` is still flaky. Next: full lab `ncpdov` reset, then re-fire; if still flaky it's the
lab client tool's delivery path, not the server.

### NEXT STEP (Kurt's rule) — ONE bounded lab-client reset + ONE re-fire, then stop

Server: **solved.** Wire proof: **solved** (the lab daemon already `read()` the herald
`TENEX NETLIT TEST\r\n` off the NCP path). Client display: **worth exactly one clean retry** — do
NOT turn it into another archaeology dig.

**Keep host69 and NETLIT-1c untouched** — do NOT restart host69, do NOT rebuild NETLIT, do NOT
change the 1c code. The host69 side works. Clean **only** the lab/client delivery path:
1. Kill duplicate ncp31/`ncpdov` instances (there was a dup on ports 20311/20312).
2. Remove stale `/tmp/client.*` sockets.
3. Confirm exactly one ncp31 path is active (`mini/ncp31` socket + one `ncpdov localhost 20311 20312`).
4. Confirm no stale `ncp-telnet` clients are hanging around.
5. Re-run the socket-1 client **once**: `NCP=ncp31 ./ncp-telnet -o 69` from `mini/`.
6. Watch both sides: NETLIT reaches `HERALD SENT`/`DONE`; lab completes ICP; client should display the herald.

If the herald appears → **call the full visible demo path proven.** If it still does NOT appear →
**stop.** Classify as `ncpdov`→client-socket delivery cleanup (lab-tool polish), NOT host69/NETLIT
failure — the server milestone remains met (herald already observed crossing the NCP path).
**Do NOT reset the whole IMP mesh** unless the NCP client path cannot be cleaned locally (a full lab
reset risks disturbing a working host69/NETLIT instance and reintroducing host-ready chores).

**RESULT of the bounded retry (2026-06-28, end of session 4):** stale `/tmp/client.*` cleared; but
the **noc keeps respawning a duplicate ncp31 `ncpdov`** (two instances on 20311/20312, ~20s apart) —
I could not get to exactly one locally without touching the noc. The single re-fire returned
`NCP open error` with an EMPTY NETLIT console (the RFC never reached host69), i.e. the duplicate
daemon broke the client→lab→host69 path that very moment. **STOPPED per the rule. Classified as
lab-tool (`ncpdov` duplicate) cleanup.** Server + wire proof remain met. **NEXT-SESSION lab-tool fix:**
make `mini/noc-server.py` spawn exactly one `ncpdov` per NCP (it currently double-spawns ncp31), OR
manually leave a single ncp31 daemon owning `mini/ncp31` and immediately re-fire. Then the already-
working host69 herald should display in `ncp-telnet`.

### ★★★ CRITICAL OPERATIONAL FINDING — run the emulator in tmux, NOT directly from a Claude command

For ~most of session 4, every `pdp10-ki` launched from a Claude Bash command died at ~5s with
`SIGTERM received, PC: 102737` — deterministic, untraceable to any Unix sender, surviving
nohup/setsid/disown/foreground. **Cause: Claude's execution sandbox reaps the command's process
tree/cgroup on completion; `pdp10-ki` (a heavy background child) goes with it.** PC 102737 is just
TENEX's idle scheduler (incidental). **Fix: run the emulator inside a persistent tmux session.**
There is a long-lived `h69r` tmux session (a real daemon, outside the sandbox). Launch via:
```
tmux send-keys -t h69r "bash <abs-path>/netser-build/build-1c.sh >/tmp/netlit-build.out 2>&1 &" Enter
```
The ki becomes a child of the tmux server and survives. Drive/monitor from Claude via the FIFO + log
files (`logs/cty.log`, `/tmp/netlit-*.out`). Reading processes from Claude (pgrep/strace/firing
`ncp-telnet`) works fine — only the long-lived ki must live in tmux. **This was the whole reason
earlier sessions' builds were so flaky.**

### Repo-local run scripts (work in tmux or your own shell)
- `netser-build/build-1c.sh [SRC.fai]` — assemble on-box → rebuild `login.dta` run tape. Self-
  contained: generates its own `.do`, repo-local `scripts/{console-daemon,drain}.py`, scratch via
  `NETLIT_SCRATCH` (default `/tmp/netlit-$USER`). **Fixed:** `mkfifo` the FIFO explicitly (a race made
  it a regular file → console-daemon tight-looped → garbled FAIL). Bumped COPY/FAIL waits.
- `netser-build/launch-1c-test.sh` — host-ready (FORCEDOWN) boot + auto-load NETLIT → LISTENING; then
  fire `NCP=ncp31 ./ncp-telnet -o 69` from `mini/`.
- `netser-build/RUN-1C-OUTSIDE-CLAUDE.md` — the runbook.

---

## ★★ MILESTONE 1b PROGRESS (2026-06-28, session 3) — accept works; bare BOUT insufficient

Built **`netser-lite-1b.fai`** (accept-and-send shim) on-box and tested end-to-end. Reproducible
on-box assembler loop scripted in **`build-netlit.sh`** (FAIL via DTA1 build tape -> DTA0 .REL ->
`tendmp -x` -> rebuild `login.dta`). Test = `NCP=ncp31 ./ncp-telnet -o 69` against the running shim.

**Confirmed (instrumented console):**
- NETLIT detects the RFC (GDSTS foreign host appears, `HOST=31`).
- Explicit **`MTOPR fn 20` (NETACP) accepts: state RFCR(4) -> OPND(7)** — verified by GDSTS before
  vs after (`STS` state nibble 4 -> 7). The first BOUT does NOT auto-accept (it blocks); the
  explicit MTOPR is required. *(This validated the accept primitive.)*
- BUT the first **`BOUT` still blocks even at OPND**, and the client always reports
  `Timed out completing RFC` -> `Open refused`.

**Why bare accept+BOUT is not enough:** the lab `ncp-telnet` does the **standard ARPANET ICP** —
it sends `RTS` to socket 1, gets the RFNM, then waits for host69 to **complete the connection** by
sending back the **ICP data-socket number** over socket 1 and opening the data connections. A raw
text BOUT on the contact socket never gives the client that, so the client never completes the RFC
and never allocates buffer -> host69's BOUT blocks (no send allocation) and the client refuses.

**Conclusion:** the next required step is the **real ICP** (NETSER `DOICP` skeleton): after
MTOPR-accept, `BOUT` the local data-socket number on socket 1, `CLOSF` it, `GTJFN`/`OPENF` send+recv
data sockets `NET:<lcl>.<fhost>-<fskt+2>;T` (send `103000,,100000`, recv `100000,,200000`), then
SOUT the herald on the send JFN. The "smallest possible proof" got us through accept; data flow
needs the socket-swap. Source/build artifacts committed; runtime `.do`s are gitignored (rebuild via
`build-netlit.sh` + `launch-trace.sh`).

**Infra notes:** the IMP output-done fix (`37744c0`) is required (host69 mute otherwise). Use literal
console commands over the FIFO (a `bash -c "...\$1..."` indirection silently sends only the CR).
Re-`START`ing NETLIT after a stuck BOUT gives `OPENF FAILED` (socket 1 still held) — relaunch host69.

---

**Date:** 2026-06-27  **Branch:** `host69-tenex-ncp-imp`
**Goal:** authentic 1972 experience — a visitor types `@L 69` over the simulated ARPANET,
reaches host69 (BBN-TENEX / SUMEX-AIM 1.31.82), gets a herald, logs in. The missing piece
is a userland program that listens on the ARPANET LOGIN socket (socket 1). Historically that
is **NETSER**; building the full NETSER is blocked by a FAIL/STALLM assembler bootstrap that
no reachable toolchain can satisfy (see `host69-netser-build-attempt` memory + RESEARCH-FINDINGS.md).

**The pivot (Kurt's call):** instead of rebuilding historical NETSER, build **NETSER-lite
(NETLIT)** — a minimal NCP listener in *primitive* FAIL (no STALLM, no macros, no FAIL-v11
features) that just listens on socket 1, accepts the connection, prints a herald, closes.
"Prove the NCP mechanics with a tiny listener before recreating the whole historical beast."

---

## ★ WHERE WE ARE (milestone 1a program: WORKING)

**NETLIT is built from source and RUNS, listening on ARPANET socket 1.** Console output:
```
START
NETLIT OPENING LISTEN SOCKET 1
GTJFN OK
OPENF OK LISTENING
STS=12926844928 HOST=511 SKT=-2     (GDSTS observe loop, every ~1s)
```
So `GTJFN "NET:1#."` and `OPENF` (listen) both succeed and the program is in its observe loop.
Native TENEX JSYS code runs fine even though it was loaded by LOADER (a TOPS-10 program under
PA1050) — PA1050 only intercepts `CALLI`, not `JSYS (104)`.

**Blocked on:** the end-to-end `@L 69` test. Right now host69 is NOT NCP-reachable
(`ncp-ping 69` and *all* lab hosts time out; no host69↔imp05 socket). This is **lab plumbing
fallout** from when the lab was torn down for the (abandoned) TOPS-20 detour; `arpanet-noc`
restart didn't fully restore the host-connection ports. NOT a NETLIT problem. See "Blocker".

---

## ★ THE THREE WALLS WE CRACKED (hard-won; don't relearn these)

1. **Primitive FAIL works.** A hand-written FAIL source using only `OPDEF`, `__` defines, plain
   PDP-10 instructions, and labeled `ASCIZ`/`BYTE` data assembles cleanly. (The STALLM/FAIL-v11
   bootstrap wall only applies to the *historical* NETSER source, not to code we write fresh.)

2. **FAIL requires CRLF source line-endings.** LF-only source (what a unix file + `tendmp`
   produce) makes FAIL *count* lines but never recognize `END` →
   `FATAL END OF FILE & NO END STMT` (even a 3-line file; proven: MINTST/LF fails, MINCR/CRLF
   gives `PROGRAM BREAK`). **Fix:** `sed 's/$/\r/' x.fai > xcr.fai` before `tendmp`.

3. **`dskasn` BUGHLT 140046 = incremental DSK file GROWTH.** Fixed-size `COPY DTAx:F DSK:F`
   is FINE. But any *growing* DSK write BUGHLTs the monitor: FAIL `.REL` output to DSK,
   `COPY TTY: DSK:`, LOADER `.SAV` output to DSK. **Fix (route A):** keep assembly I/O OFF
   DSK — source from a DECtape, output the `.REL` to a *writable* DECtape; only the
   `FAIL.SAV`/`PA1050.SAV`/`LOADER.SAV` toolchain lives on DSK (read-only use). Also note:
   only **one** FAIL/LOADER invocation per restart (a 2nd one BUGHLTs — PA1050 DSK scratch
   accumulates).

Plus the run mechanics:
- **LOADER load + EXEC START.** `LOADER` → `*DTA1:NETLIT` loads the REL (returns to `*`, no
  unresolved globals). `$G` (altmode-G) just *exits* the loader with the image loaded
  ("EXIT."). Then at the EXEC `!` prompt, **`START`** runs the loaded image. (Do NOT expect
  `$G` to start it.)
- **Preserve artifacts with `kill -TERM`, never `-9`.** SIMH buffers the DECtape in memory and
  only flushes to the host file on clean shutdown/detach. SIGTERM flushes; SIGKILL loses it.
  Then `tendmp -x scratch.dta` to extract host-side.

---

## ★ THE WORKING BUILD → LOAD → RUN LOOP (reproducible)

All paths relative to `mini/host69-bbn-tenex/`. Helper scripts in `netser-build/scripts/`
(copies of the live session scripts; the live ones run from the scratchpad).

**Tapes / devices (set by `runtime/build-tenex-restore-loginbuild.do`, copy in `netser-build/runtime/`):**
- `dt0` = `runtime/login-build/scratch.dta` — blank **WRITABLE** DECtape (DTA0:, for output).
  Make a fresh one: `tendmp -T -L TENEX -b boot/dtboot.bin -c scratch.dta dummy.txt`
  (needs ≥1 file e.g. a `dummy.txt` so the directory is valid). Only DTA0:/DTA1: exist — no DTA2:.
- `dt1` = `runtime/login-build/login.dta` — read-only toolchain+input tape (DTA1:).
- console = telnet **2323**; the `.do` also `deposit 57174 777777777777` (ENTFLG=-1).

**Build (assemble NETLIT.REL):**
1. `cp netser-build/netser-lite.fai runtime/login-build/dta/x.fai`
   `sed 's/$/\r/' runtime/login-build/dta/x.fai > runtime/login-build/dta/xcr.fai`  ← CRLF!
2. From `kit-cache/build-tenex/install/`: `tools/tendmp -T -L TENEX -b boot/dtboot.bin -c
   .../login.dta  .../dta/xcr.fai  .../dta/pa1050.sav  .../subsys/fail.sav`
   (flat tape, 6-char names → DTA1:XCR.FAI etc.)
3. `bash netser-build/scripts/run-loginbuild.sh`  (restores host69 + media + 2323 console daemon)
4. On TENEX `!` (drive via the cty FIFO; see copyfile.sh): `MOUNT DTA0:` ; `MOUNT DTA1:` ;
   `COPY DTA1:FAIL.SAV <SUBSYS>FAIL.SAV` ; `COPY DTA1:PA1050.SAV <SUBSYS>PA1050.SAV`
5. **ONE** FAIL run: `FAIL` then `DTA0:XCR_DTA1:XCR.FAI`. Success = `PROGRAM BREAK nnnnnn'`.
   Do NOT run DIRECTORY or anything else after (DSK ops BUGHLT).
6. Preserve: `kill -TERM` the `pdp10-ki` pid → flushes scratch.dta; `tendmp -x scratch.dta`.

**Run (load + start NETLIT):**
1. Build a run tape: `tendmp ... login.dta  netlit.rel  loader.sav  pa1050.sav`
   (netlit.rel → DTA1:NETLIT.REL).
2. `run-loginbuild.sh` ; on `!`: `MOUNT DTA1:` ; `COPY DTA1:LOADER.SAV <SUBSYS>` ;
   `COPY DTA1:PA1050.SAV <SUBSYS>`.
3. `LOADER` → `*DTA1:NETLIT` (load) → `$G` (exit loader, image loaded) → at `!` type `START`.
4. NETLIT prints its banner + GDSTS loop on the 2323 console.

---

## ★ LAB TOPOLOGY (learned 2026-06-27)

- host69 ↔ its IMP = **imp05**, interface **hi2**.
  `imp05.local.simh`: `attach -u hi2 21051:127.0.0.1:21052`  (imp05 listens 21051, dials 21052).
  host69 restore: `attach imp 21052:127.0.0.1:21051`  (host69 listens 21052, dials 21051).
  → link is imp05:21051 ↔ host69:21052.
- The lab IMPs (imp01..imp05+) are supervised by **`arpanet-noc.service`** (systemd). ~37
  `h316ov` processes when fully up.
- NCP client tools live in `mini/`: `ncp-ping`, `ncp-telnet`, `ncp-finger`, invoked
  `NCP=ncp31 ./ncp-ping -c1 <hostnum>`. `ncp31` is a config selector, not a daemon.
- Host management: `mini/hostctl.sh`; health: `mini/arpanet-health.sh`.
- `@L 69` = ICP to host 69 socket 1 (the telnet/login contact socket) = NETLIT's listen socket.

---

## ★ LAB ROUTING — was broken by my stop/start, now FIXED  (full writeup: `lab-fix/README.md`)

My `systemctl stop/start arpanet-noc` (to free CPU for the TOPS-20 detour) broke lab-wide
routing. **Root cause:** the noc's hardcoded `NCP_START_DELAY=35s` was tuned for the slow
2-vCPU box; the upgraded faster box boots IMPs before 35s, so their host-interfaces sat
peerless and errored (NOT load — "it worked on half the power" proves that). **Fix:** made
NCP startup **event-driven** in `mini/noc-server.py` — start each NCP the instant *its* IMP
reaches RUNNING (idempotent, old timer kept as a backstop). Verified: 18/18 HIs up at full
speed, mesh `ncp-ping` replies, no duplicate daemons. Committed (arpanet repo working tree +
copy/patch in `lab-fix/`). Throttle reverted to 15%.

## ★ CURRENT BLOCKER — host69 not yet reachable (the 1822 handshake)

Lab routes between NCP-daemon hosts now, but **host69 itself is unreachable**: it boots
(operator `!`, NETWORK ON), host69↔imp05 **hi2 UDP link is ESTAB** (`21052↔21051`, both via
`imp05.local.simh` which the noc DOES use — line 79 prefers `.local`), yet the mesh says
**"Host is not up"** → the **1822 host-IMP "host ready" handshake isn't completing**, so imp05
never advertises a route to host 69. Restarting host69/imp05 in various orders (thrashing)
hasn't reliably landed it.

Next (discuss, don't thrash):
- Canonical host69 bring-up? host69 is the real BBN-TENEX (NOT an noc NCP daemon — `05:1:69`
  correctly commented in the NCPS list), launched ad-hoc via `scripts/run-loginbuild.sh`.
  Is there repo host-lifecycle tooling / a documented order that lands the 1822 handshake?
- A prior session got "Open refused" from `@L 69` → host69 WAS reachable before; reproduce
  that wiring.
- Inspect host69 console NCP/IMP state: is it asserting host-ready / exchanging 1822 with
  imp05 hi2, or stuck on the snapshot-time IMP?

---

## ★ AFTER CONNECTIVITY: remaining NETLIT milestones

**1a finish (observe):** with the path up, run NETLIT, connect `@L 69`, watch GDSTS — expect
the state to leave idle and reach **RFCR (4)** (states: PNDG=2 RFCR=4 OPND=7 LSNG=3). If it
never reaches RFCR, suspect (Kurt's traps) **byte size** (OPENF mode `400000,,100000` vs the
RFC's byte size) or the local socket spec, NOT the JSYS sequence.

**1b (accept + herald):** inline only NETSER `DOICP`'s skeleton (no SGNON/CRPROC/PTY/LOGIN):
- `MTOPR fn 20` on the listen JFN = **accept** (RFCR→OPND). (fn 24 in MKICPF is listen-config.)
- Then the ICP: allocate local socket pair, `GTJFN` send+recv data sockets
  (`NET:<lcl>.<fhost>-<fskt+2>;T`), `BOUT` the new socket number over the ICP link, `CLOSF` it,
  `OPENF` send (`103000,,100000`) + recv. Then `SOUT` herald `BBN-TENEX NETSER-LITE TEST\r\n`,
  read with `BIN`, close both. (Source refs: netser.fai MKICPF ~516, DOICP ~804, CHECK ~560.)

**TENEX JSYS numbers** (from `build-tenex/mon/stenex.mac` `DEFJS name,num`; JSYS = `104B8+num`):
GTJFN=20 GNJFN=17 RLJFN=23 OPENF=21 CLOSF=22 SOUT=53 NOUT=224 PSOUT=76 PBOUT=74 MTOPR=77
GDSTS=145 DISMS=167 HALTF=170 SYSGT=16 CVSKT=? GETAB=10 BIN/BOUT=? SIR=125 EIR=126 AIC=131 ATI=137.

---

## ★ ARTIFACTS INVENTORY (`netser-build/`)

- `netser-lite.fai` — master source (LF), milestone 1a (listen + GDSTS observe).
- `NETCRL.FAI` — the CRLF source FAIL actually assembled.
- `netlit.rel` — **the assembled object** (3855 B, `PROGRAM BREAK 000206'`).
- `artifacts/` — redundant backups: `scratch-NETCRL-REL.dta` (full tape w/ NETCRL.REL),
  `netlit.rel`, `NETCRL.FAI`, `netser-lite.fai`, `SHA256SUMS.txt`, `README-NETLIT.txt`.
- `scripts/` — `run-loginbuild.sh`, `console-daemon.py`, `copyfile.sh`, `drain.py`, `dskscan.py`.
- `runtime/build-tenex-restore-loginbuild.do` — restore driver (dt0=writable scratch, dt1=login).
- `README.md`, `RESEARCH-FINDINGS.md` — prior research (FAIL bootstrap, etc.).
