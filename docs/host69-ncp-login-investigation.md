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
| host69 ↔ imp05 UDP link + 1822 host-ready | ✅ SOLVED (§3) |
| `@L 69` RFC reaches host69 + NCP dispatches to socket 1 | ✅ SOLVED (§10.3/10.7) |
| NETLIT-1c full ICP socket-swap + herald to client | ✅ PROVEN END-TO-END (§10.9) |
| **`@L 69` → real TENEX `@` EXEC + credentialed DEMO login** | ✅ **PROVEN** via `ATPTY` (§10.10); NETSER not needed |
| NETLIT-1d persistent (re-listens after each session) | ✅ proven (§10.10) |
| Golden snapshot (`host69-login.state`) + systemd service | ✅ built (§10.11) |
| Cold-start service validation against a healthy mesh | ✅ **MET** (§10.12) — clean restart → two full DEMO logins from the service-restored snapshot |
| imp05 hi2 startup ordering (host69 must listen before imp05) | ⚠️ production follow-up (§10.12) |
| NETLIT re-listen robustness (1e: 0 s re-listen, survives unlimited sessions) | ✅ FIXED — 5/5 live gate (§10.13) |
| Promote 1e into the golden snapshot (service durably runs 1e) | ✅ DONE — service-restored 1e served 5/5 logins (§10.13b) |
| Lab mesh fragility (host69 bounce islands routing) | ⚠️ open follow-up |

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

### 10.6 ROOT CAUSE (2026-06-28, session 2) — host69 cannot TRANSMIT post-FORCEDOWN; output engine wedged (`IMPOB` stuck)

The §10.4/§10.5 "RST/RRP convergence" framing was a **symptom, not the cause.** Re-ran one clean
`@L 69` from ncp31 with the lab `ncpdov` stderr tapped (`strace -f -e write` on the ncp31 daemon
PID, since the controller reads then discards ncpdov output) and the host69 `[NCP]`/`[GATE]` probes.
Findings:

1. **Lab side (definitive, reproduced twice):** ncp31 → `send to 105, type 12/RST` → gets the RFNM
   → **`Timed out waiting for RRP`** (RRP_TIMEOUT=20) → `error 255` → `Open refused`. The lab
   received **nothing** back from host69 — no RRP, and no RST either.
2. **host69 side:** the lab's RST **is** received and dispatched (`[NCP] dispatch=1 IM8: rst=1 rrp=1`,
   `ctlconn=1`). The source path is correct: `IM8RST`→`CALL RECRST`(netwrk.mac:2297)→`NETHDN`→
   `JRST IMPRRP` — and the `RET` from `IMPRRP` is the only way execution reaches the `IM8RRP`/`HSTHSH`
   fall-through, so **`IMPRRP` (build+queue the answering RRP) definitely runs.** The RRP is built.
3. **But host69 transmits NOTHING.** Across the entire trace (boot **and** `@L`): `OD=1`
   (output-done) fires **0** times, `out=` is frozen, **no** output CONO is ever issued (`OON`=0,
   `EOB`=0, `STO`=0), and **0** `DATAO` output-buffer writes. host69 only ever issued two
   **input-side** CONOs (`206415` = input PI + 1B19 host-ready; `014010` = input GEB). The host→IMP
   1822 output channel never runs — not the 48 boot RSTs, not the RRP.
4. **Why:** the TENEX **software** output-in-progress flag `IMPOB` (mem `070330`, *"buffer now being
   emptied by pi routine"*) is **stuck non-zero live** (`impob=777777000000`), while `IMPORD`
   (`070213`, master output-enable) = `-1` (output **is** allowed) and `IMPDRQ` (`070224`) = 0.
   `IMPXOU` ("start msg going out", impdv.mac ~5594) does `SKIPN IMPOB` → with `IMPOB`≠0 it believes
   "output already in progress" and **never starts a new send.** So every queued RST/RRP is stranded
   behind a flag that says busy-forever. The monitor only clears `IMPOB` when its output engine
   drains the queue, which is driven by **output-done interrupts that never arrive.**
5. **The trigger is the FORCEDOWN recycle.** At the **snapshot** (pre-FORCEDOWN) `impob=070330`=**0**
   (idle) and `nopcnt`=2 — output had worked. **Live, post-FORCEDOWN**, `impob`=`777777000000`
   (stuck) and `nopcnt`=2: `IMPRSS` re-armed `NOPCNT=3`, the engine shipped **one** host-ready NOP
   (3→2), then wedged with `IMPOB` set because no output-done came back to advance/clear it. This is
   the **output-side analog of the §10.3 input re-arm bug** — an emulator 1822-fidelity gap in the
   host→IMP output-done handshake during/after the FORCEDOWN down/up cycle.

**Conclusion:** host69 can *hear* the lab but cannot *answer*. The lab's RTS is withheld only because
host69 never sends the RRP, and host69 never sends the RRP (or anything) because its IMP **output
channel is wedged** (`IMPOB` stuck) after the FORCEDOWN bring-up. The fix is in the **emulator output
path** (`PDP10/kx10_imp.c`), not in NCP reset convergence and not on the lab side.

**Diagnostic instrumentation added** (gitignored fork, uncommitted): `[GATE]` probe extended with
`impord/impob/nopcnt`; new `[OUT]` probe block (impord/impdrq/impob/nopcnt/impobo/imphbo). Tap method
for the lab view: `sudo strace -f -tt -e trace=write -s2048 -p <ncp31-ncpdov-pid>` (PID = the
`./ncpdov localhost 20311 20312` process; 20311/20312 = CCA-TENEX = host 31). `kill -TERM` the ki to
flush SIMH's block-buffered debug.

**Next step (proposed):** trace the FORCEDOWN→IMPRSS→first-NOP output with `set imp debug=IRQ;CONO;
DETAIL` enabled *before* the FORCEDOWN cycle to find exactly where the output-done handshake stalls
(the manual-launch port-cleanup is fragile — drive it through `launch-trace.sh`'s machinery with a
debug-early `.do`, or add a one-shot wait for ports 16945/2323/21052 to clear). Then fix the
emulator so the TENEX NCP output path raises output-done (`IMPOD` + interrupt) after `imp_send_packet`
so `IMODN` advances and clears `IMPOB`. Candidate sites: the `CONO IMPEOB` handler at kx10_imp.c:992
(currently *clears* `IMPOD` after the send, never sets it) vs the generic service routine
(kx10_imp.c:1438 — which *does* `STATUS |= IMPOD; check_interrupts`). Validate by re-firing one
`@L 69` and confirming the lab logs `received RRP from 105` then `Send ICP RTS`.

### 10.7 SOLVED (2026-06-28, session 2) — output-done fix lands; `@L 69` reaches host69's login listener (LSNG→RFCR)

**The emulator fix (committed, fork `37744c0`).** In the TENEX NCP `CONO IMPEOB` handler
(`PDP10/kx10_imp.c` ~998) changed the post-ship `uptr->STATUS &= ~IMPOD;` to
**`uptr->STATUS |= IMPOD;`**. The `check_interrupts(uptr)` already at the end of the CONO handler
then raises the completion output-done. Rationale, confirmed against `impdv.mac`: the driver's output
ISR `IMODN` ships a message with `CONO I.EOM` (end bit), arms `IMODSP=IMODN2`, and **waits for one
more output-done interrupt** to run `IMODN2` (start next queued msg, or stop output and clear the
software `IMPOB`). The old handler cleared `IMPOD` and never re-raised it, so `IMODN2` never ran and
`IMPOB` stayed set forever (the bring-up traced exactly: `OON`→word→`EOB`/`packet sent sequence=1`,
then **no further output-done**). This is the output-side analog of the §10.3 input re-arm fix.

**Verified end-to-end (one clean `@L 69`):**
- host69 output drains: `impob` 0, `nopcnt` 3→0, host69 now transmits (the host-ready NOPs, RSTs, and
  the answering RRP all go out).
- **RST/RRP converges:** the lab advances from `type 12/RST → Timed out waiting for RRP` to **`type
  1/RTS`** (it received host69's RRP, marked host69 alive, and sent the connection RTS). host69
  receives it: `[NCP] RECRTS≥2`.
- **The RFC reaches host69's login listener.** With NETLIT listening on socket 1 and the client fired
  as **`NCP=ncp31 ./ncp-telnet -o 69`** (the `-o`/`OLD_TELNET` flag = contact **socket 1**, the
  authentic 1972 TENEX logger socket; the default is `NEW_TELNET`=socket 23, which does NOT match
  NETLIT, `telnet.c:14,597`), **NETLIT's `GDSTS` walked `LSNG` → `RFCR`**: from `HOST=511 SKT=-2`
  (listening, any host) to **`HOST=31 SKT=1002`** (RFC received from host 31 = CCA/ncp31, peer socket
  1002). This is precisely the success state NETLIT (NETSER-lite milestone 1a) was built to
  demonstrate — the `@L 69` now traverses the **entire** NCP stack to host69's BBN-TENEX login socket.

**What "Open refused" at the client still means (expected, not a host69 bug):** NETLIT is a *minimal
observer* — it opens the listen and watches the state walk, but does **not** send the answering STR /
complete the ICP / serve a login herald. So the client's `Timed out completing RFC` is by design.
Completing an authentic login (herald → `@LOGIN`) requires the real **NETSER**, which is blocked on
the FAIL/STALLM assembler wall (see `[[host69-netser-build-attempt]]`). The NCP transport is now
proven; the remaining work is the login *server*, not the network path.

**Two operational requirements discovered (pin these):**
1. **Emulator fix `37744c0`** must be built in (output-done after EOB). Without it host69 is mute.
2. **Client must contact socket 1** (`ncp-telnet -o`) to match the TENEX login socket; the default
   socket 23 silently never matches the listener.

### 10.8 SOLVED (2026-06-28, session 4) — NETLIT 1c does the full ICP socket-swap; herald crosses the NCP path

Built **`netser-build/netser-lite-1c.fai`** — the DOICP-lite socket-swap server (RFC 123/165 +
lab-`ncp.c`-validated). On one `@L 69` the host69 console walks the **entire ICP**:
`RFC RECEIVED → CONTACT ACCEPTED → SEND SOCKET NUMBER → SOCKET NUMBER SENT → OPEN DATA SOCKETS →
DATA SOCKETS OPEN → HERALD SENT → DONE`. The lab `ncpdov` confirms the full NCP handshake
(`Received STR … send 4/ALL … Confirm STR, send RTS … Client got RTS, STR, and socket from server …
connection 1, error 0` — **the client opens, no "Open refused"**). And a lab strace caught the herald
on the wire: `read(3, "…TENEX NETLIT TEST\r\n…") = 44`. **The host69/NETLIT server side is done and
correct.** 1c flow: listen socket 1 (contact, byte size 32) → RFCR → `MTOPR fn20` accept →
`NET:<S>.<fhost>-<fskt+2>;T` (octal) → GTJFN send+recv → `CVSKT` → `BOUT` S on contact → `CLOSF` →
`OPENF` send `103000,,100000` + recv `100000,,200000` (byte size 8) → `SOUT` herald → DISMS → close.

**Remaining = lab-tool, NOT host69:** the herald reaches the lab's NCP but `ncpdov` mis-delivers to
the client *app* socket (stale `/tmp/client.*` + a **duplicate ncp31 daemon** the noc keeps
respawning). One bounded reset+re-fire (per the plan) did not display the herald (`NCP open error`
the moment the dup daemon broke the path). Classified as `ncpdov`-to-client delivery cleanup; server
milestone met. Full writeup + the lab-tool fix: `netser-build/NETLIT-STATUS.md` (milestone 1c).

**★ CRITICAL OPERATIONAL FINDING:** the deterministic `SIGTERM PC 102737` that killed every host69
`pdp10-ki` for most of session 4 was **Claude's execution sandbox reaping the command's process
tree** (PC 102737 = TENEX's idle scheduler, incidental). **Run the emulator inside the persistent
`h69r` tmux session** (`tmux send-keys -t h69r "bash …/build-1c.sh …" Enter`) so the ki is a child of
the tmux daemon and survives; drive/monitor from Claude via the FIFO + log files. This is why earlier
sessions' builds were flaky. Also fixed a FIFO race (`mkfifo` it explicitly, else console-daemon
tight-loops a regular file and garbles the FAIL drive).

---

### 10.9 ✅✅ DEMO PROVEN END-TO-END (2026-06-28, session 5) — the CLIENT displays the herald

`NCP=ncp31 ./ncp-telnet -o 69` printed **`BBN-TENEX NETLIT TEST`** in the client while host69's
console walked the full ICP (`RFC RECEIVED → … → HERALD SENT → DONE`). The §10.8 "lab-tool polish"
gap is **CLOSED**. Two fixes:

1. **noc ncp31 double-spawn — FIXED (commit `170f30a`).** Root cause = `mini/noc/server/process.py`
   `_handle_pty_read` treating a PTY **EOF/EIO as process death** (fires `on_exit` →
   `NCPController._handle_exit` nulls `self._process`, state→CRASHED) while the real `ncpdov` is still
   alive → a restart/re-fired IMP-RUNNING event spawns a SECOND ncpdov on the same ports (state guards
   blind because the handle was nulled). Fix = `NCPController._reap_stray_daemons()` in
   `noc/server/ncp.py`: sweep `/proc` for any live ncpdov on this NCP's exact `(tx,rx)` pair and
   SIGKILL it before spawning. The systemd noc runs from the repo, so the fix went live on recover.

2. **The actual blocker was MESH-WIDE routing loss**, not the double-spawn: every IMP islanded (each
   NCP pings its OWN IMP but `IMP cannot be reached` to all others) — the §8 self-inflicted wound from
   `ncp-telnet`/`ncp-ping` spam. Fix = `mini/arpanet-recover.sh recover` (NOT plain `systemctl restart
   arpanet-noc`). host69's ki survives recover; afterward `ncp31→69` reads `Host is not up` (§8 item 3:
   a SIMH imp restart doesn't drop host69's 1B22 CONI ready line, so TENEX never re-asserts host-ready
   to the new imp05). **Land host-ready by RELAUNCHING host69 (`launch-1c-test.sh`) after imp05 is
   stable** — the `impctl.py restart 5` nudge did NOT land it; the FORCEDOWN relaunch did.

**Recovery runbook:** `sudo ./arpanet-recover.sh recover` → poll `ncp-ping -c1 69` until it leaves
`IMP cannot be reached` → kill+relaunch host69 (`launch-1c-test.sh` in `h69r` tmux) to `NETLIT IS
LISTENING` → `ncp-ping -c1 69` `Reply` → `ncp-telnet -o 69` shows `BBN-TENEX NETLIT TEST`.

---

### 10.10 ✅✅✅ REAL CREDENTIALED LOGIN (2026-06-28/29, session 5) — NETSER is NOT needed; ATPTY is the key

The authentic `@L 69 → BBN-TENEX → @LOGIN → session` is **PROVEN** — and it did **not** require
rebuilding NETSER (the FAIL/STALLM wall, §ref `host69-netser-build-attempt`). Reading the real
`netser.fai` (routine `DOLGC` @927) + our monitor showed the login core is **one JSYS we already
have: `ATPTY` (JSYS 274)**, implemented in our running monitor (`build-tenex/mon/netwrk.mac:1073`,
network-aware). It hands the NCP data connection to TENEX's normal dial-up login path:
`ATPTY`(recv JFN in AC1, send JFN in AC2) → `ASNNVT` assigns a Network Virtual Terminal → carrier-on
→ `ttysrv.mac` `TT7CX`/`TTCON` → `TTC7SJ` "START JOB" → monitor runs `<SYSTEM>EXEC.SAV` → `@` flows
back over the net; gated by `ENTFLG<0` (we deposit `-1`). `ATPTY` even RELEASES the JFNs — the MONITOR
pumps bytes, so the server needs NO byte-shuttle.

**NETLIT-1d** (`netser-build/netser-lite-1d.fai`) = 1c's DOICP socket-swap + `ATPTY` + `STI`. All
primitive JSYS; assembles with the on-box FAIL. Commits: `6833ee8` (ATPTY → live `@` EXEC reached),
`77cd55d` (credentialed login), `dc49ece` (persistent + marker removed).

Proven transcript over the ARPANET (`NCP=ncp31 ./ncp-telnet -o 69`, sending a CR):
```
 SUMEX-AIM Tenex 1.31.82, SUMEX-AIM EXEC 1.51
@LOGIN DEMO  1
 JOB 1 ON TTY131 22-JUN-72 12:08
@SYSTAT     ->  1 131 DEMO EXEC   (DEMO is a real logged-in job)
@LOGOUT
```
- **DEMO account** = non-privileged (`#3=700000`, no wheel/operator; `#6=5`; password `DEMO`),
  created by DLUSER at bring-up (`netser-build/demusr.txt`; `launch-1d-login.sh` /
  `build-snap-launch.sh`). DLUSER's `CAN'T CREATE ... CONTINUING` is the known-cosmetic message — the
  dir+password ARE created. LOGIN over the net: `LOGIN DEMO DEMO 1` (account = any number <2^33).
- **Persistent**: after the ATPTY handoff NETLIT loops back and re-listens on socket 1 (verified two
  back-to-back logins on one run; brief `OPENF FAILED` window while socket 1 settles).
- Client noise: `[NOECHO]` is the `ncp-telnet` client printing TENEX's old-NVT echo negotiation
  (client-side; the web terminal won't show it).

### 10.11 GOLDEN-SNAPSHOT SERVICE (2026-06-29, session 5) — built; cold-start validation blocked by mesh

The console-driven systemd bring-up (DLUSER+LOADER+START over a telnet/FIFO with sleeps) is the wrong
shape for production (Kurt: "a tiny séance every restart"). Chosen architecture = **golden snapshot**.
- **Built `snap/host69-login.state`** (gitignored runtime artifact): host69 booted clean, DEMO created,
  NETLIT-1d LISTENING, then SIMH-`SAVE`d. Rebuild via `netser-build/build-snap-launch.sh` (ki
  FOREGROUND in tmux `h69r:0` — stdout MUST be the pane/tty or SIMH goes non-interactive and the WRU
  break fails) + console-daemon in `h69r:1` + drive DLUSER/NETLIT → LISTENING, then break to `sim>`
  (`set console wru=034` must be AFTER `restore`; `tmux send-keys -t h69r:0 'C-\'`) → `save`.
- **Service rewired** (`mini/host69ctl.sh` + `mini/arpanet-host69.service`, `Type=exec`,
  After/Requires `arpanet-noc`): `daemon` = foreground ki that `restore -F`s the snapshot, reattaches
  IMP to imp05, FORCEDOWN re-asserts host-ready, `go`; `setup` = wait host-ready; passive drainers on
  16945/16946/2323 (the 2323 one unblocks the FORCEDOWN steps + drains NETLIT's console). NO
  DLUSER/LOADER/FIFO in startup. `RestartSec=90`, `StartLimitBurst=3`. Installed, NOT enabled. Commit
  `1c014bf`. (Earlier WIP `e9f33ef` documents why oneshot/setsid/screen all get the ki reaped → Type=exec.)
- **BLOCKED — cold-start validation**: needs a healthy mesh to run `ncp-telnet -o 69`, but after a
  session of host69 restart churn the **lab mesh won't re-converge** — `arpanet-recover.sh recover`
  completes clean (36 IMPs, ncp31 up) yet inter-IMP routing stays islanded (`ncp-ping` to other hosts
  hangs / "IMP cannot be reached"). Deferred mesh-fragility item, now the gate on validation.
- **UNVALIDATED RISK**: the restore's FORCEDOWN does NETDWN, which may tear down NETLIT's socket-1
  listen. Must verify NETLIT still LISTENS after a golden cold start (couldn't — mesh down).

### 10.13 ✅ NETLIT-1e re-listen hardening — 5-SESSION GATE PASSED (2026-06-29, session 6)

**GATE PASSED.** On a stable mesh, 5 consecutive `@L 69` sessions (connect → `LOGIN DEMO DEMO 1` →
`SYSTAT` → clean `LOGOUT`) all completed, **each re-listening in 0 s** with no `GTJFN FAILED`/`!` death
— including session 2's logout, exactly where 1d died. Final state: clean `LISTENING`. NETLIT-1e even
survived the `ncp-telnet` client's post-logout reconnects (the suspected 1d aggravator). Transcript:
`netser-build/netlit-1e-5session-gate-2026-06-29.txt`. The `CLOSF`+`RLJFN` on the contact socket
eliminated the ~2.5 min settle (→ 0 s, which is what enables many concurrent users); removing the JFN
leak + `HALTF` eliminated the trapdoor.

**Mesh stability (the blocker below) — RESOLVED as an operational procedure, root-caused:** today's
instability was the **thrashed-mesh state from my repeated imp05 restarts + connection spam**, NOT an
inherent fault. Recipe that yields stable host69 connectivity: (1) `sudo ./arpanet-recover.sh recover`
(re-converges all IMPs incl. a fresh imp05); (2) **WAIT** for convergence — minutes, be patient — note
host69 only needs imp05 reachable, which converges before the far mesh (11/16); (3) bring host69 up
*after* imp05 is fresh/stable; (4) **do NOT restart imp05 to "nudge"** and do not spam pings/telnet —
that is what islands it. Verified: after a clean recover, host69 reached + HELD reachability (both 1d
and 1e), and ran the 5-session gate without a hiccup. (The imp05-ordering §10.12 item 1 is the durable
fix; this is the manual procedure until then.)

Below: the original BLOCKED writeup (kept for the root-cause detail).

### 10.13a NETLIT-1e — BUILT + root-caused (the analysis; gate later passed, see §10.13)

Narrow re-listen hardening pass (Kurt: don't redesign login / don't touch the snapshot until proven /
don't revisit IMP-NCP routing). **Root cause of the 1d "~2 logins then GTJFN FAILED → `!`" trapdoor,
confirmed against the authoritative real `netser.fai`:**
- 1d's `OPERR` retry loop (the ~2.5 min `OPENF FAILED` settle) re-`GTJFN`'d socket 1 every iteration
  **without releasing** the prior JFN → a JFN leak; after enough retries the JFN table exhausted, the
  next `GTJFN` failed, and the error paths did **`HALTF`** → dropped to the `!` EXEC.
- 1d also `CLOSF`'d the contact socket **without `RLJFN`** → the NCP connection lingered (this is the
  ~2.5 min settle that also throttles concurrent onboarding).
- Real `netser.fai` never `HALTF`s: `MKICPF`/`DOICP` clean up with `CLRJFN` (= `CLOSF` **then** `RLJFN`)
  on every path (lines 538/576/584/586/914/920).

**Fix = `netser-build/netser-lite-1e.fai`** (login/ICP/ATPTY path byte-for-byte unchanged from 1d):
a `CLRJ` helper (`CLOSF`+`RLJFN`, no-op on JFN 0); every socket `CLRJ`'d on every exit/retry path;
the listen JFN released before each retry (`OPERR`); **all `HALTF` removed** — `GJERR`/`FAILJ`/`FAILS`/
`FAILR`/`FAILP` now log + clean up + `JRST START`. Assembles on-box (`PROGRAM BREAK 000515'`), loads,
`START`s, reaches `LISTENING`, and stayed LISTENING with no death through the idle/test window.

**Why this also serves "as many simultaneous users as possible" (Kurt's added requirement):** each
ATPTY'd user is an independent monitor login job; the only serialization point is socket 1, so fast +
reliable re-listen (no leak, no 2.5 min settle, no HALTF) is exactly what lets many users onboard.

**BLOCKED — the 5-consecutive-session gate could not run.** host69 mesh connectivity was unstable:
after a launch host69 replies to ~1 ping then goes "not up" (imp05 routes but won't hold host69's
host-ready). The 1d **service** showed the same instability today (converged once after ~3 min, flaky).
Restarting imp05 made it worse — **lesson: after a host69/imp05 change, WAIT for convergence (minutes);
do NOT restart imp05 to "nudge" it.** This is the imp05-ordering / host-ready / mesh-fragility area Kurt
fenced off from this pass. The hardening code is done and idle-verified; the network proof needs a stable
connectivity window (→ the mesh-stability/imp05-ordering follow-up is a prerequisite, see §10.12 item 1).
Build/test recipe: `build-1c.sh netser-lite-1e.fai` (assemble; it polls too early for `PROGRAM BREAK`,
so extract manually: TERM ki → `tendmp -x scratch.dta` → `cp xcr.rel netlit.rel` → rebuild `login.dta`)
then `launch-1d-login.sh` (manual `START` — the ESC-G/START choreography races).

### 10.13b ✅ NETLIT-1e PROMOTED INTO THE GOLDEN SNAPSHOT — service durably runs 1e (2026-06-30)

The hardened NETLIT-1e is now what the `arpanet-host69` service restores. Built the snapshot via
`build-snap-launch.sh` (restore `host69-live.state` → host-ready → drive DLUSER+LOADER+START NETLIT-1e
→ `LISTENING` → `C-\` break → `save`), promoted to `snap/host69-login.state` (1d preserved as
`host69-login.state.1d-bak`, the 1e source kept as `host69-login-1e-v2.state`). **Validation: service
cold-start → host69 reachable → 5/5 consecutive `@L 69` credentialed DEMO logins** (each a fresh listen;
consecutive success proves re-listen). **Durable deployment complete.**

**Two build lessons (cost a BUGHLT + a rebuild):**
1. **Capture point matters.** The first 1e save broke (`C-\`) while TENEX was at a non-resumable PC
   (101575); on service restore it pinned at PC 113760 and `BUGHLT AT 100561`. Fix: let the system
   **idle at LISTENING ~20 s** so NETLIT is quiescent, then break (caught PC 101002) — restores clean.
   If a snapshot BUGHLTs on restore, rebuild it; don't ship it. (Rollback to 1d via `host69-login.state.1d-bak`
   was clean — the rp03 packs are shared and tolerate it.)
2. **`All connections busy` on the restored console is BENIGN** — it's the monitor rejecting mesh
   probe/ping connections (NCP table pressure baked into a snapshot built while host69 was live on the
   mesh). It does **not** block ICP logins (5/5 passed). Cosmetic follow-up: rebuild the snapshot with a
   cleaner NCP table (e.g. build with imp05 briefly detached after host-ready) to silence the cty.log noise.

Also a process note: SIMH `build-snap-launch.sh` does **not** wait for ports to clear — if 2323 is in
TIME_WAIT it `bind`-fails and the ki falls back to stdio and **segfaults**. Wait for
2323/16945/16946/21052 to clear before launching it.

### 10.12 ✅ COLD-START SERVICE VALIDATION — GATE MET (2026-06-29, session 6)

With a healthy mesh (`ncp-ping` to 11/16 reply), ran the full validation against the
golden-snapshot service. **`sudo systemctl restart arpanet-host69` → two complete, clean DEMO
logins from the service-restored snapshot.** Transcript artifact:
`netser-build/golden-service-validation-2026-06-29.txt`.
```
 SUMEX-AIM Tenex 1.31.82, SUMEX-AIM EXEC 1.51
@LOGIN DEMO  1
 JOB 1 ON TTY131 22-JUN-72 12:10
@SYSTAT   ->  1 131 DEMO EXEC      (DEMO is a real logged-in job)
@LOGOUT
KILLED JOB 1, USER DEMO, ACCT 1, TTY 131, AT 6/22/72 1210
```
Results: NETLIT LISTENS from the restored snapshot; host69 `ncp-ping`-reachable after the clean
restart (no imp05 nudge needed this run); full credentialed login + SYSTAT + clean LOGOUT; NETLIT
**re-listened** after the first logout (~2.5 min settle) and a **second** `@L 69` logged in identically
(two full sessions per restart, matching §10.10). The §10.11 FORCEDOWN/NETDWN "tears down the listen"
risk is **DISPROVEN** — the listen survives restore.

**BUT the re-listen is fragile across repeats:** after the *second* logout NETLIT got past `OPENF` but
then hit **`GTJFN FAILED` and dropped to the `!` monitor EXEC** — i.e. NETLIT exited; a third `@L 69`
would get "Open refused" until a restart. So persistence is currently **~2 sessions per restart**, not
indefinite. (Possible aggravator, unconfirmed: after each logout the `ncp-telnet` client re-opened the
contact socket ~3× — `TELNET to host 105.` ×3 in each transcript — which may collide with NETLIT's
vulnerable re-listen window and induce the `GTJFN FAILED`. Worth isolating before blaming NETLIT.)

**The MUST-USE client detail (cost me three restarts):** drive `ncp-telnet -o 69` with stdin from a
held-open pipe (raw fd / FIFO), NOT through a **pty/pexpect** — under a pty the herald deterministically
**stalls at ~28 bytes** (`...Tenex 1.31.82, SU`) and the session dies. Raw stdin delivers the full
herald + interactive login. (The production web-terminal path is its own transport; this caveat is for
automated CLI testing only.)

**Three follow-ups surfaced (NOT login-architecture blockers — do NOT redesign the login/NETLIT/ATPTY/
snapshot):**
1. **imp05 hi2 startup ordering (production).** `imp05 hi2` must be (re)started/nudged *after* host69 is
   listening; otherwise imp05 boots without the host69 peer and host69 reads "Host is not up". It did
   NOT bite this run (imp05 was already healthy and stayed up across the host69 restart), but on a cold
   box boot the order isn't guaranteed. Least-magical fix options (decide later, don't build yet):
   (A) `host69ctl start` starts host69, then restarts/nudges only imp05 hi2, then verifies `ncp-ping 69`;
   or (B) `arpanet-recover` knows host69 is a real hosted peer and starts it before restarting imp05.
   **This gates `systemctl enable` (auto-start on boot).**
2. **NETLIT re-listen fragility (the real robustness gap).** Two parts: (a) after a session the
   monitor's NCP connection-cleanup holds socket 1, so NETLIT hot-loops `OPENF FAILED` ~2.5 min before
   re-`OPENF`-ing → `LISTENING` (within that window `@L 69` gets "Open refused"); (b) the re-listen
   eventually *fails* — after the 2nd logout it passed `OPENF` then `GTJFN FAILED` → dropped to `!` →
   NETLIT exited (host69 then refuses until restart). `Restart=on-failure` does NOT catch this (the ki
   is still alive; only NETLIT died). So host69 currently serves ~2 logins per restart. Fix later:
   harden NETLIT's re-listen loop (keep socket 1 NETSER-style / retry GTJFN, don't HALTF on transient
   failure) and first rule out the client-reconnect aggravator above. **This is the gap to close before
   a public/high-traffic exhibit**, though for a one-visitor-at-a-time demo it's tolerable with
   `RestartSec`-style recycling.
3. **`host69ctl setup` host-ready race.** `setup` (ExecStartPost) can match a *stale* `HOST-READY DONE`
   and report active ~110s early (systemd shows "active" while the ki is still in the FORCEDOWN cycle).
   Cosmetic for steady state but it makes `systemctl restart` return before the service is truly ready;
   fix = truncate/marker the runlog per-boot so `setup` only matches the current boot's line.

---

## NEXT SESSION — START HERE (handoff, session 6 — golden-snapshot validation)

Branch `host69-tenex-ncp-imp`. **The architecture is DONE and committed** (latest `1c014bf`): real
`@L 69` credentialed DEMO login is PROVEN (§10.10), NETLIT-1d is persistent, the golden snapshot
exists, and the service restores it instead of console-driving. **The ONLY remaining task is
cold-start VALIDATION against a healthy mesh** — a validation problem, not architecture.

**Status of the stack:**
- IMP/1822 input+output, RST/RRP — solved (§10.3/10.6/10.7).
- `@L 69` → real TENEX `@` EXEC + credentialed DEMO login — PROVEN (§10.10).
- noc ncp31 double-spawn — fixed (`170f30a`).
- Golden snapshot + service — built (§10.11), validation pending.

**Start from a CLEAN BASELINE (do NOT recover-thrash a churned lab):**
1. Reboot / cleanly restart the lab host if needed.
2. Start the NOC/IMP mesh (`arpanet-noc`).
3. Confirm inter-IMP routing: `NCP=ncp31 ./ncp-ping -c1 <6|11|16>` REPLIES. Don't proceed until healthy.
4. `sudo systemctl start arpanet-host69`.
5. `NCP=ncp31 ./ncp-ping -c1 69` replies.
6. `cd mini; NCP=ncp31 ./ncp-telnet -o 69`.
7. Prove DEMO login from the SERVICE-restored snapshot: `LOGIN DEMO DEMO 1` → `@` → `SYSTAT`.
8. Confirm NETLIT re-listens after `LOGOUT`.
9. If all pass: `sudo systemctl enable arpanet-host69.service`.

**THE RISK TO CHECK (step 6/7):** does the restore `.do`'s FORCEDOWN/NETDWN disturb NETLIT's socket-1
listen? If host69 pings but `@L 69` gives "Open refused" / no herald, that's it. FIX (only after mesh
healthy): reorder — restore → reattach IMP → re-assert host-ready WITHOUT NETDWN if possible, OR
re-START NETLIT after FORCEDOWN. Then address mesh fragility (why host69 bounces island routing) as a
separate follow-up.

**Authentic login is SOLVED — NETSER is NOT needed** (§10.10 supersedes the NETSER wall for the login
goal). Key files: `netser-build/netser-lite-1d.fai`, `demusr.txt`, `build-snap-launch.sh`,
`build-snap.do`; `mini/host69ctl.sh`, `mini/arpanet-host69.service`; full status
`netser-build/NETLIT-STATUS.md`. Memory: `host69-real-login-gate`.
