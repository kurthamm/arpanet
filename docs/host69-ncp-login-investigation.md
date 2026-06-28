# host69 BBN-TENEX — ARPANET login (`@L 69`) investigation journal

**A lab notebook, not a spec.** This documents *how* we are getting the real BBN-TENEX on
host 69 to accept an authentic 1972 ARPANET login (`@L 69` → herald → login) — including the
dead ends and *why* they failed, the diagnostic probes (so you can re-run them), and the exact
commands. The point is that you can **recreate, understand, and correct** this — not just clone
a working snapshot.

Status as of 2026-06-28: **host-ready SOLVED; login blocked one layer up, in the NCP's
incoming-RFC dispatch.** Frontier section at the bottom. Companion docs:
`mini/host69-bbn-tenex/netser-build/{HOST69-IMP-RECOVERY-HANDOFF.md, NETLIT-STATUS.md}`,
`mini/host69-bbn-tenex/netser-build/lab-fix/README.md`.

---

## 1. The goal & the architecture

A visitor on the simulated ARPANET types `@L 69`, reaches host 69 (the real BBN-TENEX running
under a PDP-10 emulator), gets a login herald. `@L 69` == an **ICP** (Initial Connection
Protocol) **to host 69, socket 1** (the login contact socket).

Topology:
- **host69** = BBN-TENEX, emulated by rcornwell SIMH `pdp10-ki`. Its 1822 host-IMP interface
  is an emulated IMP *device* (`kx10_imp.c`, `TYPE_BBN` + `UNIT_NCP`).
- **imp05** (BBN) = the ARPANET IMP host 69 hangs off, emulated by `h316ov`. host 69 uses
  imp05's host interface **hi2**.
- **Link**: UDP. `imp05.local.simh`: `attach -u hi2 21051:127.0.0.1:21052`. host69 restore:
  `attach -u imp 21052:127.0.0.1:21051`. So **imp05:21051 ↔ host69:21052**.
- The wider lab (36 IMPs + 18 `ncpdov` NCP-host daemons) is supervised by the systemd service
  **`arpanet-noc`** (`mini/noc-server.py`). host 69 is the *real* TENEX, NOT an `ncpdov`
  daemon (its route `05:1:69` is correctly commented out in `mini/arpanet`).
- **Bring-up of host69** = the SAVE/RESTORE production path: `mini/host69-bbn-tenex/
  netser-build/scripts/run-loginbuild.sh`, which `restore -F`'s `snap/host69-live.state`,
  attaches the UDP IMP link + DC/TYM console drainers + the NETLIT build tapes, and puts the
  TENEX console on telnet **2323** with a console-daemon. (Do **not** reboot TENEX from
  scratch — that path is upstream-broken; we live on RESTORE forever.)

Login data path, layer by layer (this is the map for the whole investigation):
```
ncpXX (lab) --RFC--> imp31 --ARPANET routing--> imp05 hi2 --UDP--> host69 imp device
   --> TENEX monitor IMP input service (STRIN/IMISRT) --> NCP (netwrk.mac) RFC dispatch
   --> match to a LISTENing socket --> deliver to the server (NETSER, or our NETLIT)
```

---

## 2. Status board

| Layer | State |
|---|---|
| host69 boots / SAVE-RESTORE | ✅ comes up `NETWORK ON, IMP ON`, `pia=050` |
| host69 ↔ imp05 UDP link | ✅ both ends ESTAB (21052↔21051) |
| 1822 **host-ready** handshake | ✅ SOLVED (see §3) |
| Lab routing / reachability to host 69 | ✅ `ncp31 → 69` reaches imp05 and host is "up" |
| NETLIT login listener on socket 1 | ✅ runs, `OPENF OK LISTENING`, faithful to NETSER (see §6) |
| `@L 69` RFC reaches host69 | ✅ proven by trace (see §7) |
| NCP delivers RFC to the listen socket | ❌ **FRONTIER** — RFC held/undispatched (see §8) |
| 25 stale RFNM "stuck output" conns / metronome | ⚠️ present; correlated, causal role unproven |

---

## 3. SOLVED: the 1822 host-ready handshake (and the emulator fix behind it)

**Symptom**: host69 boots and the UDP link is ESTAB, but the lab reports `ncp31 → 69` = *"Host
is not up"* — imp05 never advertises a route to host 69.

**Root cause (emulator)**: the `TYPE_BBN`/`UNIT_NCP` CONI in `kx10_imp.c`. TENEX's `impdv.mac`
reads CONI bit **1B22 (`0020000`)** as the *imp-down* indication (`IMPRSS` only proceeds when
1B22 is OFF; `IMPSTT` marks the imp DOWN when 1B22 is ON). An earlier emulator bug raised 1B22
when the host asserted host-ready, which *dropped* the imp ~20s after bring-up. The fix: gate
the imp-ready line on the patched `imp_data.host_ready` field (set by the monitor's `CONO IMP,
1B19` in `IMPRSS`) and **never surface 1B22 during normal up-operation** — leave it clear.

**Operational gotcha (the part that actually bites)**: host-ready is an **edge-triggered**
handshake. host69 asserts host-ready *once* during its bring-up (CONO 1B19 in IMPRSS). If
imp05's hi2 isn't connected/ready at that exact moment — e.g. imp05 was (re)started while
host69 was absent — the assertion is *missed* and host 69 stays "not up" forever. Waiting does
not fix it (the doorbell rang in an empty house).

**The reliable lever — re-assert host-ready with a FORCEDOWN down/up cycle** (see §5 for the
emulator patch): make host69 re-run `IMPRSS` (and thus `CONO 1B19`) while imp05's hi2 is
already connected. Concretely: let the imp come **UP** (`imprdy` = -1), then `deposit IMP
FORCEDOWN 1` (surfaces 1B22 → TENEX takes NCP down via `IMPSTU→IMPNOF→NETDWN`), then `deposit
IMP FORCEDOWN 0` (1B22 clear → `IMPRSS→IMPRSN` brings NCP back up and **re-asserts host-ready**
to the now-connected hi2). Result: `ncp31 → 69` flips from *"Host is not up"* to a hang
(= reachable; "hang" because host69 is a listener, not an echo responder). The console logs the
visible cycle `NETWORK ON, IMP ON` → `... IMP OFF` → `... IMP ON`.

---

## 4. How to drive it (reproduction commands)

All from `mini/` unless noted. `H = mini/host69-bbn-tenex`.

```bash
# Lab healthy baseline (NOT `systemctl restart arpanet-noc` — see §9):
cd mini && ./arpanet-recover.sh recover         # ordered bring-up; ./arpanet-recover.sh verify to check
./arpanet-health.sh                              # FAILURES=0 (a lone Pi-SSH WARNING is unrelated)

# Bring host69 up (production SAVE/RESTORE path):
bash $H/netser-build/scripts/run-loginbuild.sh   # ki on telnet 2323 + console-daemon + drainers

# If `ncp31 -> 69` says "Host is not up": land host-ready.
#  - simplest: one `python3 impctl.py restart 5` WITH host69 already up (peer-dependency step)
#  - robust:   the FORCEDOWN re-assert cycle (scripted relaunch; §5)

# Reachability probe (DIAGNOSTIC ONLY — not the goal). MUST set NCP=, use -c1, do NOT SIGKILL:
NCP=ncp31 ./ncp-ping -c1 69      # "Host is not up" = host-ready not landed; hang = up; reply = echo host
#  gotcha: `timeout -s KILL` discards ncp-ping's block-buffered stdout -> looks empty even on success.

# Drive the host69 console (write to the console-daemon FIFO; it relays to telnet 2323):
FIFO=<scratch>/cty.fifo                          # path printed by run-loginbuild.sh
printf 'MOUNT DTA1:\r' > "$FIFO"                 # TENEX EXEC commands, CR-terminated
bash $H/netser-build/scripts/copyfile.sh LOADER.SAV "<SUBSYS>"   # COPY w/ [New file] confirm
#  gotcha: after `COPY ... [New file]` TENEX waits for a CONFIRMING CR; send `\r`, not the next cmd.

# Load + run NETLIT (the login listener):
printf 'LOADER\r' > "$FIFO"; printf 'DTA1:NETLIT\r' > "$FIFO"   # `*` prompt loads the REL
printf '\033G' > "$FIFO"                          # altmode-G: exit loader, image loaded ("EXIT.")
printf 'START\r' > "$FIFO"                         # run -> "NETLIT OPENING LISTEN SOCKET 1 / GTJFN OK / OPENF OK LISTENING"

# The actual test: one @L 69 (ICP to host 69 socket 1):
NCP=ncp31 ./ncp-telnet 69                          # watch NETLIT's GDSTS, not ncp-telnet's exit
```

---

## 5. The emulator patch (FORCEDOWN lever) — REPRODUCE THIS

⚠️ **Reproducibility gap**: the patched simulator source lives in the **gitignored** build
cache `mini/host69-bbn-tenex/kit-cache/rcornwell-sims/PDP10/kx10_imp.c`, NOT in tracked source.
To rebuild from a clean clone you must apply this patch and `make pdp10-ki` there. (TODO: also
land the host-ready 1B22 gate + this lever in tracked `src/sims/PDP10/kx10_imp.c`.)

The lever surfaces CONI 1B22 on command, so we can drive a clean host69-side IMP down/up cycle
(to re-assert host-ready, §3). It is a **separate global**, deliberately NOT a field of
`imp_data`, so the SAVE/RESTORE `SAVEDATA(DATA, imp_data)` blob layout is unchanged and the
existing snapshot still restores. Default 0 = stock behavior.

```c
/* near `double last_coni;` (~line 570) */
int       imp_force_down = 0;   /* deposit IMP FORCEDOWN 1 -> CONI surfaces 1B22 (imp-down) */

/* in imp_reg[] (the device register array) */
{DRDATA(FORCEDOWN, imp_force_down, 32), REG_HIDDEN},

/* in imp_devio() CONI, TYPE_BBN + UNIT_NCP path, after the IMPR/1B20 block (~line 1104) */
if (imp_force_down)
    *data |= 0020000;   /* 1B22 forced: imp-down indication (post-RESTORE recycle) */
```
Build: `cd kit-cache/rcornwell-sims && make pdp10-ki` (sanity check must print "Good
Registers"). Use: in a `.do` (no live `sim>` is reachable — see §9 gotchas),
`step` until `imprdy`(70203) = -1, then `deposit IMP FORCEDOWN 1` / `step` / `deposit IMP
FORCEDOWN 0` / `step` / `go`.

---

## 6. NETLIT — the login listener (and why it's NOT the bug)

The real ARPANET login server is **NETSER**; building historical NETSER is blocked by a
FAIL/STALLM assembler bootstrap wall. So we wrote **NETLIT** (`netser-build/netser-lite.fai`),
a minimal primitive-FAIL listener: open a LISTEN on socket 1, print the GDSTS status each
second, so we can watch an incoming `@L 69` walk the connection state LSNG → RFCR.

We **statically verified NETLIT is byte-for-byte faithful** to NETSER's `MKICPF` (the routine
that builds the login ICP listen socket, `kit-cache/tenex/cusps/netser.fai:516`):

| element | NETLIT | NETSER MKICPF |
|---|---|---|
| GTJFN filespec | `NET:1#.` | `"NET:"`+socket+`"#."` (public) → `NET:1#.` |
| GTJFN flags | `MOVSI A,400001` | `MOVSI 1,400001` |
| OPENF mode/byte-size | `[XWD 400000,100000]` | `[XWD 400000,100000]` |
| MTOPR listen-config | fn 24, `C=777723` | fn 24, `C=777700+₁₉` = `777723` |

And NETLIT's idle GDSTS `STS=12926844928` = `140240000000` octal; the state subfield
(`POINT 4,2,3`, the same field NETSER's `CHECK` tests) = **3 = LSNG** — it *is* correctly
listening. So a socket-spec / byte-size mismatch is ruled out: if an RFC reached the socket it
would step LSNG(3)→RFCR(4), which the 1-second poll would catch.

---

## 7. Diagnostic methodology — the probes (re-runnable)

The single most useful probe was a **narrow IMP receive trace** that proves whether an incoming
RFC physically reaches host69, and whether the monitor armed input to take it. Enable in a
`.do`: `set debug stdout` + `set imp debug=IRQ` (this is narrow — the full `set imp debug`
floods and can BUGHLT; `IRQ` alone is safe). `kx10_imp.c`'s `imp_udp_packet_in` then logs every
received 1822 message:
```
IMP ncp recv poll#<n> nw=<words> buf0=<flags> link=<imp_link_up>
IMP ncp gate#<n> ILEN=.. STATUS=.. pending=.. link_up=..
```
- `nw=1` = a host-ready NOP (just flags); **`nw>1` = a message body, i.e. an RFC**.
- `link`/`link_up` = whether the monitor has armed input (`CONO IMP_STRIN`); a message arriving
  with `link_up=0` is **HELD** at the IMP, not delivered to the monitor.

Other re-usable examines (monitor memory; octal addresses from the build's `tenex.dis`):
- host-ready / IMP state: `imprdy`=70203 (0=down,−1=up), `impdrq`=70224 (recycle req), `neton`=70204,
  `imprdt`=70215, `imprdl`=70214.
- input buffers: **`impnfi`=70227 (count of FREE input buffers)**, `impfri`=70226 (free list),
  `impinp`=70331 (BLKI ptr), `iminfb`=70335.
- the metronome bug: `impbgc`=70650 (cumulative IMP-bug count); PC 132445 = `impdv.mac` `RFNCK3`,
  `BUG(IMH,<MESSAGE STUCK IN OUTPUT QUEUE>)`.

**What the trace proved for `@L 69`:** the RFC *does* reach host69 (`recv poll … nw=7`); it was
momentarily held (`link_up=0` at arrival); but input arms periodically (`link_up` toggles
1↔0), free input buffers are plentiful (`impnfi=8`, unchanged by a FORCEDOWN cycle), so it is
**not** buffer starvation and **not** caused by the FORCEDOWN lever. Therefore the RFC reaches
the NCP but is not dispatched to the listening socket — pushing the blocker up into the NCP.

---

## 8. The dead-end log (the valuable part)

**Goal of these attempts**: the running snapshot carries ~25 IMP "links" stuck waiting for
RFNMs whose retransmit buffers were lost in the SAVE (`IMPLT1=200000` in-use, `IMPLT2` RFNMC
pending, `IMPLT3=0` = buffer gone). They produce the once-per-minute `IMPBUG … MESSAGE STUCK IN
OUTPUT QUEUE` "metronome" (`impbgc` climbs +25/min). We *suspected* they wedge the NCP and tried
to clear them. **All runtime-clearing approaches failed:**

1. **`deposit IMPDRQ -1`** (ask the monitor to recycle): no effect — the metronome continued on
   its original schedule. The IMPDRQ poke did not produce an effective recycle.
2. **Zero the link tables** (`deposit` IMPLT1=free / IMPLT2=0 / IMPLT3=0): **SEGFAULT** on
   resume. Clearing the tables out from under live NCP/fork/queue state leaves dangling
   references. (Confirms: you cannot table-surgery your way out — companion state matters.)
3. **`detach`/`attach` the IMP** (a socket-level outage): TENEX never noticed. A SIMH detach does
   not drop the CONI ready line (1B22), so the monitor's down-detection never fired.
4. **FORCEDOWN while the imp was still coming up** (`imprdy`=0): wrong path — went through the
   *bring-up* (`IMPSTB→IMPRSS`), not the *tear-down* (`IMPSTU→IMPNOF→NETDWN`). No NETDWN.
5. **FORCEDOWN while UP** (the *correct* recycle): the console showed a real `IMP ON → OFF → ON`
   cycle with `NETDWN` running — **and the 25 stuck conns survived it.** A full NCP down/up,
   including NETDWN abandoning the network, does **not** clear them; neither does the natural
   `IMPRSN`. The stuck `IMPLT2` RFNMC state outlives both.

**Conclusion from the dead ends**: the runtime IMP/NCP *recycle* cannot clear this stale state.
And — per §7 — the stuck conns are **not** starving input buffers. So whether they are even
*causal* for the login failure is still unproven; they may be a correlated symptom of the same
poisoned snapshot rather than the mechanism.

**Lab self-inflicted wound (learn from this)**: spamming `ncp-telnet 69` wedged the lab's
`ncpdov` daemons; then `sudo systemctl restart arpanet-noc` made it worse (cold restart loses
converged routing; the 4-core box thrashes at `nothrottle` and won't re-converge at 15%
throttle). The fix was the documented `./arpanet-recover.sh recover` (it kills stale procs AND
deletes stale `ncp*` sockets, which a plain noc restart does not). **Do not** reach for
`systemctl restart arpanet-noc`.

---

## 9. Gotchas index (things that will waste your time)

- **No live `sim>` on a running host69.** It's launched `nohup … </dev/null`; SCP is on a dead
  stdin, and telnet 2323 is the TENEX *CTY*, not SCP (WRU/`^E`/`^\` go to TENEX). To run
  `deposit`/`examine`/FORCEDOWN you must script them in the `.do` and relaunch, OR use bounded
  `step <count>` between SCP commands (a `.do` can `step` then `deposit` then `step` … then `go`).
- **`set console notelnet` (stdio console) SEGFAULTS at `go`** with this snapshot. Use telnet
  console (2323). The full `set imp debug` can BUGHLT; `set imp debug=IRQ`/`=CONI` are safe.
- **`ncp-ping`/`ncp-telnet` need `NCP=ncpNN` set** (else the client segfaults). Use `-c1` and do
  NOT wrap in `timeout -s KILL` (SIGKILL eats their buffered stdout → false "empty").
- **TENEX `COPY … <SUBSYS>` prompts `[New file]` and waits for a confirming CR** — send `\r`.
- **DSK growth BUGHLTs** the monitor (incremental writes); only fixed-size `COPY` to DSK is safe.
  One `LOADER`/`FAIL` invocation per restart.
- **`tendmp -t <tape>.dta`** lists a DECtape image host-side (verify NETLIT.REL/LOADER.SAV/
  PA1050.SAV are on `login.dta`).
- Shell: this session's harness has quirks — separate commands with `;`, guard `pkill`/`tmux`
  with `|| true`, and **never `pkill -f 'drain.py'`** (it matches the tool wrapper and kills your
  own shell).

---

## 10. FRONTIER (where to pick up)

Proven: the `@L 69` RFC reaches host69's IMP, input is armed periodically, buffers are
available — yet NETLIT never leaves LSNG. So the RFC reaches the NCP but is **not dispatched to
the listening socket (socket 1)**. Next target is **`netwrk.mac`**: the incoming-RFC →
listen-socket matching / ICP-receive path. Open questions:
- Does the NCP's RFC handler run and try to match socket 1, or is the NCP input-message loop
  itself stalled after the first message?
- Is the stale connection state (the 25 RFNM conns) actually blocking RFC dispatch, or is it a
  red herring and the real issue is that an unprivileged foreground NETLIT isn't the registered
  contact-socket server the monitor will hand RFCs to?
- If the stale state *is* causal and unrepairable at runtime, the remaining path is a genuinely
  **clean/quiescent snapshot** — but note that's chicken-and-egg (the only snapshot is the
  poisoned one; recycle won't clear it; fresh boot is upstream-broken).

### 10.1 `netwrk.mac` source audit (2026-06-28) — byte-size RULED OUT; NETLIT confirmed correct

Read the NCP source (`kit-cache/build-tenex/install/monitor/netwrk.mac;1`, 2097 lines):

- **NCP state machine** (transition table 1363-1368): a listening socket on *received-RFC*
  advances `LSNG → RFCR` (line 1365) — exactly what NETLIT needs. Per-socket state is
  `NETSTS(UNIT)`, state field `PFSM = POINT 4,NETSTS(UNIT),3`. States
  `FREE/CLZD/PNDG(2)/LSNG(3)/RFCR(4)/RFCS(6)/OPND(7)`.
- **The reject path** is `RRFB` = "received RFC with non-matching byte size" (def 1286; set in
  `RECSTR`, netwrk.mac:1900). `RECSTR` (1888) compares the **listener's** byte size
  (`PBPBYT = POINT 6,NETSTS(UNIT),17`) vs the **incoming RFC's**; mismatch → `RRFB` (reject +
  CLS), match → `RRFC` → `RFCR`. An RRFB would leave NETLIT in LSNG *and* bounce a CLS to ncp31
  — matching both symptoms — so it was the prime suspect.
- **But byte size MATCHES → RRFB is NOT the cause.** OPENF byte size = AC2 **bits 0-5**
  (`jsys.mac:165,185`). NETLIT/`MKICPF` OPENF `400000,,100000` → bits 0-5 = `100000`b = **32**.
  The lab ICP client sends **32** (`mini/src/ncpd-ovREUSE/src/ncp.c:772`). 32 == 32.
- **`HSTCHK` (1795) is "always OK if listen"** — the foreign-host check doesn't block it either.

**Conclusion:** NETLIT's socket params are correct (byte size, gender, contact socket all match
the real `NETSER` `MKICPF` and the incoming ICP). The break is **not** NETLIT and **not**
byte-size — it's the **RFC delivery/processing path**: either the emulator-fork's held-message
redeliver (the RFC arrives `link_up=0`, gets held; the redeliver was built for the startup NOP —
`netser-build/emulator-fork/`), or the monitor's NCP control-message input not running `RECSTR`
on the delivered RFC.

**Decisive live test (next):** `launch-trace.sh` → NETLIT listening; break to `sim>` (2323
telnet console); dump the `NETSTS` connection table; fire one `@L 69`; break + diff `NETSTS` —
does a connection entry appear / change state (did `RECSTR` run) and land on NETLIT's socket-1
listen, or is the RFC never delivered/processed?

### 10.2 LIVE RESULT (2026-06-28) — the RFC is never DELIVERED: TENEX stops re-arming IMP input

Ran `launch-trace.sh` (host69 up, host-ready re-asserted — `ncp-ping 69` hangs, the
host-ready-landed signature), fired one `@L 69`, then stopped the ki to flush the (block-buffered)
`DEBUG_IRQ` recv trace. Result:

- **The RFC arrives:** `IMP ncp recv poll#10841 nw=6 buf0=2 link=0` (a 6-word message = the ICP
  RFC/STR), then `poll#10842 nw=1` (a host-ready NOP).
- **`link=0` on ALL 14 recv-polls** — `imp_link_up` is **never 1**. `chkint` shows `RDY=1`
  (host-ready up), `pia=055` (our single-PI-channel assignment), steady-state `ID=0 OD=0`. Early
  in the run there WERE input-dones (`ID=1`, `STATUS=102010/002010`); then it settled to
  `ID=0 link=0` and never re-armed.

**The break is delivery, upstream of the NCP:** TENEX arms IMP input initially (handles the
host-ready NOP traffic) **then stops re-arming**. An RFC arriving after arming stops is **held in
the emulator's `pending_buf` and never delivered** → `RECSTR` never runs → NETLIT (correctly
listening) never sees it → ncp31 hangs. Not NETLIT, not byte size, not RFC matching — **`imp_link_up`
never returns to 1.**

**New frontier — why does TENEX stop re-arming IMP input?** Two candidates:
1. **TENEX-side IMP-service stall** — the 25 stuck RFNM connections (`RFNCHK` "MESSAGE STUCK IN
   OUTPUT QUEUE" metronome) may starve the shared IMP service so it never re-posts an input
   receive (`IMISRT`/`STRIN`). This would make the 25-stuck-conn snapshot the *root* cause, not a
   cosmetic side effect — looping back to the "need a quiescent snapshot" problem.
2. **Emulator-fork arm-detection bug** — our fork sets `imp_link_up=1` on detecting the host's
   input-arm (CONO/BLKI). If TENEX re-arms but our detection misses it, `link_up` stays 0.

**Next test:** trace the host's IMP input-arm path (the CONO/DATAI/BLKI our fork keys off) and
correlate with `IMISRT` in the monitor — is TENEX issuing the re-arm at all (→ candidate 1) or
issuing it and being missed (→ candidate 2)?

### 10.3 SOLVED (2026-06-28) — IMP input re-arm deadlock fixed (TWO 1822-fidelity emulator bugs)

The narrow question is **answered: candidate 2 (emulator), not TENEX-side stale state.** TENEX
issues the arm correctly; the *hardware-interface model* (`kx10_imp.c`, rcornwell's recreation of
the 1822 host-IMP interface — NOT authentic IMP software, so faithful corrections are legitimate)
dropped it. Two distinct faults, both fixed toward real 1822 behavior (the authentic 1972
`impdv.mac` is untouched):

1. **Bodiless NOP/ready frames ate the arm.** `imp_udp_packet_in()` set `imp_link_up=0` *before*
   the `nb==0` check, so a bare host-ready keepalive (`nw=1`) silently consumed the host's armed
   input buffer with no input-done interrupt. Fix: consume the arm only when a real body is
   delivered.
2. **End-of-input was collapsed into input-word-ready (the killer).** Real 1822 raises EOI
   (`IMPEIB`) as a **separate** interrupt; TENEX's `IMPSV` dispatch (impdv.mac:397-405) runs
   `IMPEIN` — which clears `IMIB` and re-arms via `IMISRT` — **only** on an interrupt with
   `IMPINB` clear + `IMPEIB` set. The model cleared `IMPLW` on the `DATAI` that read the last data
   word and never interrupted on `IMPLW` alone, so `IMPEIN` never ran, input was never re-armed,
   and (because `IMIB` stayed set) the process-level restart at impdv.mac:1166 also never fired.
   Fix (scoped to `UNIT_NCP`): `DATAI` clears only `IMPID` (leaves `IMPLW` until `CONO IMPGEB` in
   `IMPEIN`); `check_interrupts` raises the standalone EOI interrupt on `IMPLW`.

**Verified live** (`launch-trace.sh` + NETLIT + one `@L 69`): RFC delivered word-by-word →
`STATUS=102010` (last word + EOI) → `102000` (last word read, **IMPLW preserved**) → `IMPEIN`
runs (`CONO IMPGEB 014010`) → input **re-armed** (`CONO IMPION 206415`); `link_up` stays 1; **zero
held RFCs** all run. Fix committed in the `rcornwell-sims` fork repo (`e7c64e7`); gitignored, so
also mirrored to `investigation-2026-06-28/emulator-patch/kx10_imp.c.patched`. **TODO: land it in
tracked `src/sims/PDP10/kx10_imp.c` + regenerate the emulator-fork bundle/patch.**

### 10.4 NCP dispatch traced end-to-end (2026-06-28) — RFC delivered; blocker = host-host RST/RRP handshake

With the IMP input layer fixed (§10.3), instrumented the **monitor-internal** RFC→`RECSTR` path
with **sampling-immune cumulative PC-execution counters** (CPU fetch-loop counters surfaced via the
IMP CONI `[NCP]` probe; addresses from `tenex.dis`). Diagnostic instrumentation committed in the
fork repo (`ec6b0b8`). Findings, in order:

1. **An `IMPRSS`-set flush count silently ate the RFC.** `IMPRSS` (IMP bring-up, impdv.mac:4328)
   sets `IMPFLS=-2` to flush the first 2 inbound messages. The harness **FORCEDOWN host-ready
   re-assert re-runs `IMPRSS`**, re-arming that flush — so the one `@L 69` RFC took `IMPEIN`'s
   flush branch (counter `flush=1`) and was discarded before reaching the NCP. **Bypassed** with
   `deposit 70360 0` (clear `IMPFLS`) after the FORCEDOWN cycle in `trace-rfc.do`. ⚠️ *Production
   note: any host-ready method that runs `IMPRSS` re-arms this; clear `IMPFLS` or send 2 warm-up
   msgs.*
2. **With the flush cleared, the RFC flows into the NCP:** queued to the input queue (`RFCq=1`,
   `impibi`→a real buffer), drained at process level, and a **control connection is created**
   (`ctlconn=1`, `impncl` 0→1→0). The IMP/driver layer is fully working.
3. **`IMPCNP` dispatches exactly one control command (`dispatch=1`) — but it is a host-host
   `RST`/`RRP`, not the connection `RTS`.** Counters: `RECSTR=0 RECRTS=0 RECCLS=0`, while
   `IM8RST(133241)=1` → `RECRST` (+ fall-through to `IM8RRP` host-status update). Host-table gates
   are clear (`badhost=0 forcerst=0`). The lab client (`ncpd-ovREUSE/ncp.c`) sends an **RTS** to
   initiate ICP — but that RTS **never reaches host69's NCP**; the only inbound control message is
   the reset handshake. host69 meanwhile sent **48 RSTs** (`imsrst=48`).

**Conclusion:** the break has moved below the connection logic to the **NCP host-host reset
(RST/RRP) protocol**. host69 keeps (re)sending RST and processes an inbound RST, but the host-host
link with the lab never settles into "up" in the direction that lets the lab deliver the connection
RTS. NETLIT (correct, listening) and `RECSTR`/`RECRTS` are downstream of a handshake that isn't
completing. This is plausibly where the stale snapshot state (the 25 conns / reset bookkeeping)
finally bites — but now at the host-host-protocol layer, precisely located.

### 10.5 LAB-SIDE gating (2026-06-28) — the RTS is withheld until host69 sends an RRP; host69's RST spam destroys the connection

Read the lab daemon `mini/src/ncpd-ovREUSE/src/ncp.c` (the authentic-ish NCP the lab speaks). The
ICP-open path gates the connection RTS on the host-host reset (line ~1634):

```c
if ((hosts[host].flags & HOST_ALIVE) == 0) {     // host69 not yet known up
    ncp_rst (host);                              // lab sends RST to host69
    when_rrp (i, app_open_rts, app_open_fail);   // ONLY after host69's RRP -> app_open_rts sends the connection RTS
}
```
- `HOST_ALIVE` for host69 is set when the lab **receives an RST or RRP from host69** (`process_rst`
  line 1265, `process_rrp` line ~1283). The lab sends the connection **RTS only after it receives an
  RRP from host69** in response to the lab's RST (`when_rrp` → `app_open_rts`, `RRP_TIMEOUT=20`).
- **`process_rst` (line 1275) calls `reset_host(source)` which `destroy()`s ALL of that host's
  connections.** So every RST host69 spams at the lab **tears down the in-progress `@L` connection**.
  host69's **48 RSTs** are not benign — they actively reset the lab's host-host state and can nuke the
  pending ICP each time.

**Synthesis of both sides:** the two ends are not converging the host-host reset. host69 keeps
sending RST (doesn't mark the lab "up"); the lab answers RRP and marks host69 alive, but needs
host69's RRP (to the lab's RST) before it will emit the connection RTS. If host69 never sends that
RRP — or sends RST again and destroys the connection first — the lab's `when_rrp` times out
(`app_open_fail`) and the RTS is never delivered. Either way, **the missing message is the connection
RTS, and the cause is unsettled host-host reset state.**

---

## NEXT SESSION — START HERE (handoff)

Continue from branch `host69-tenex-ncp-imp`. **Rebuild the emulator first**
(`cd mini/host69-bbn-tenex/kit-cache/rcornwell-sims && make pdp10-ki`; fork repo HEAD `ec6b0b8` =
fix `e7c64e7` + diagnostic counters) — the gitignored binary carries the fix + the NCP probe.

**Status of the stack (do NOT re-litigate without new evidence):**
- IMP/1822 delivery — **solved** (§10.3, emulator fix `e7c64e7`).
- NCP input re-arm — **solved** (§10.3).
- IMPFLS bring-up flush — **understood + bypassed** (`deposit 70360 0` after the FORCEDOWN cycle; §10.4).
- NETLIT — **exonerated**, listening correctly (LSNG); do **not** touch or rebuild it.
- RECSTR / socket listener — downstream, **not reached yet**; do not debug it yet.
- **CURRENT WALL: host-host `RST`/`RRP` reset convergence** (§10.4 host69-side, §10.5 lab-side).

**Goal (brutally narrow):** explain why host69 exchanges `RST`/`RRP` but never reaches the state
where the lab delivers the connection `RTS`. The missing message is the `RTS`; the reason is
host-host reset state — find the `HSTSTS` transition that fails.

**Constraints:** one source only = **`ncp31 → host69`**. Do NOT use ncp1/ncp2/ncp35, repeated `@L`
attempts, NETLIT rebuilds, or `set imp debug` beyond the proven instrumentation.

**Runbook:**
1. Bring host69 up on the patched path (`launch-trace.sh`); land host-ready.
2. Account for IMPFLS (the `.do` already does `deposit 70360 0` after FORCEDOWN; verify it echoed).
3. **Trace before firing `@L`** — host69 side: `RECRST` (netwrk, called from `IM8RST`@133242), the
   send-RST path (`IMSRST`@133611), the receive-RRP path, host-status table `HSTSTS`(~`070440`) for
   ncp31's host number, any reset counter/timer, and `IMPCNP` dispatch. **Lab side (cheap, do first):**
   capture `ncpdov`'s stderr (`fprintf` logs "received RST/RRP from", "Send ICP RTS") — it shows
   directly whether the lab gets host69's RRP and whether it emits the RTS. (Ncpdov is launched by
   `mini/noc/server/ncp.py`; find/route its stderr.)
4. Fire exactly **one** `@L 69` from ncp31.
5. Capture: host69 inbound control-command sequence; host69 outbound RST/RRP; lab `ncpdov` view;
   `HSTSTS` before/after.

**Decision tree:**
- host69 gets RST but never RRP → lab not replying, or host69's outgoing RRP path invalid/invisible.
- host69 sends RST repeatedly but never marks ncp31 up → host-status / reset-completion logic stuck.
- host69 marks ncp31 up but RTS still absent → lab `ncpdov` withholding RTS (doesn't see host69 up).
- RTS arrives after convergence → next layer is finally `RECSTR`/`RECRTS` → socket match → NETLIT `RFCR`.

**Pinned cautions:**
1. **IMPFLS is a production-cutover hazard.** If the host-ready lever runs `IMPRSS`, it arms
   "flush next 2 inbound msgs," so a real `@L 69` can be eaten. Need a deterministic prod rule:
   avoid that host-ready method, clear `IMPFLS` after it, or delay until 2 harmless msgs consume it.
2. **The 25 stuck RFNM conns** were NOT the input-arm cause and NOT NETLIT — but may still poison
   reset convergence / host-status. Prove it here, with a sharp place to look.

**Addrs (tenex.dis):** recstr=441110 recrts=441206 reccls=441057 imsrst=133611 im8rst=133241
im8rrp=133244 recrst (call@133242) impbht=070656 imphrt=070430 impchu=070351 impcho=070352
impflg=070216 impibi=070321 impibo=070322 impnfi=070227 impncl=070336 impfls=070360 netsts=075656
(hststs ≈ 070440). **Harness:** `launch-trace.sh` (2323 telnet console, ~75–90s to host-ready).
NETLIT load: `MOUNT DTA1:` → `copyfile.sh LOADER.SAV <SUBSYS>` → `copyfile.sh PA1050.SAV <SUBSYS>`
→ `LOADER` (wait for `*`) → `DTA1:NETLIT` → `\033G` → CR (flush stray `G`) → `START`. Trace flush:
`kill -TERM` the ki (SIMH debug is block-buffered). **Leave the lab clean (host69 down, imp05 up).**
The scripted NETLIT load occasionally flakes on console timing — verify `OPENF OK LISTENING` before firing.
