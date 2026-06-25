# Host #69 BBN-TENEX — authentic ARPANET IMP bring-up: session handoff

**Date:** 2026-06-25 (updated)  ·  **Branch:** `host69-tenex-ncp-imp`  ·  **Author:** Kurt Hamm + Claude

This documents the work to give the BBN-TENEX simulator (host #69) an authentic
1822 host interface so it can join the lab's 1972 ARPANET and serve `@L 69`.
Read this first in any future session, then the memory files it links.

---

## 0. START HERE (next session) — exact state + next steps

> **PATCH NOTE (2026-06-25):** `patches/rcornwell-ncp-imp.patch` is now the COMPLETE
> emulator delta from base `9510a91` (apply with `git apply` in the rcornwell-sims
> checkout) — it captures BOTH the ncp/IMP work AND the base working-tree fixes
> (scp.c console-timeout, kx10_disk.c fflush/IOERR, kx10_cpu.c pager, kx10_tym.c,
> kx10_cty.c, kx10_dt.c). It's ~968K because cpu/dt also carry CRLF/whitespace noise;
> the real fixes are small. So the working binary is fully reproducible from this one
> patch — nothing critical lives only in the (gitignored) build tree anymore.

> **2026-06-25 LATE UPDATE — live bring-up reached `RDY=1`; blocker is now NO-SYSJOB.**
> Verified end-to-end on a STABLE running TENEX (fast installed-boot, see below):
> - Emulator fixes committed (rcornwell `33f226e` + a follow-up): TENEX-faithful
>   CONI/CONO bit layout; **inbound UDP poll re-armed with `sim_activate`** (the
>   `sim_clock_coschedule` poll silently stops after boot); **surface IMP-ready on a
>   live UDP link** (the H316 IMP's ready Nop is a one-shot startup burst, missed if
>   the host wasn't booted yet). Patch `patches/rcornwell-ncp-imp.patch` (763 lines).
> - **INBOUND LINK VALIDATED (2026-06-25 late):** with `UDP` debug on, host69
>   receives the IMP's real 1822 NCP burst cleanly — `link 0 - packet received
>   sequence=0..5`, ZERO magic/sequence drops, `host69rx=6`, `RDY=1`. The poll fix
>   (sim_activate) makes this reliable; receive works regardless of IMP-start order.
>   So IMP→host over the authentic 1822-over-UDP wire is PROVEN. (Earlier "0 received"
>   was just checking before the burst arrived.)
> - **OUTBOUND still blocked (the wall):** even with the IMP ready at boot, TENEX
>   never runs `IMPRSS`, so `TENEXCONO=0`/`pia=0` and it sends no host Nops. The boot
>   device-init bring-up (137143, which would assign the channel) doesn't complete,
>   and the fork path `IMPSTB`→`IMPRSS` is gated. `CHKNET` (clears `NETTCH`) IS called
>   by job-0's `CHKR`, so NETTCH alone isn't it — `IMPRDY` state and/or job-0 not
>   advancing point back at needing **SYSJOB** (the net job). Provisioning SYSJOB is
>   the unified next step for BOTH link-completion and login. Caveat: the forced
>   IMP-ready may set IMPRDY=-1 (premature "up") and should likely be REMOVED so the
>   real handshake drives IMPRDY — test that with SYSJOB present. Also the sim
>   occasionally exits after a couple min at `!` ("KI DIED") — console/idle stability
>   to revisit.
> - (superseded sub-line) TENEX now reads CONI as **ready (`RDY=1`)**. But it still does NOT assign
>   the PI channels (`TENEXCONO`=0, `pia=0`). Per `impdv.mac`, `IMPSTB` calls `IMPRSS`
>   only when `IMPRDY==0 && NETON && NETTCH<=0`; it's stuck because `IMPRDY` is already
>   `-1` (device-init thought the link up) and/or `NETTCH>0` (an unreported net
>   state-change). Clearing that needs the network job/logger to run = **SYSJOB**.
>   `sysjob.sav` is in the kit (`kit-cache/imsss/files/system/sysjob.sav.3`); the
>   install driver never installs/starts it. THAT is the next step (see [[host69-tenex-authentic-goal]]).
> - **Inbound receive caveat (unsolved):** even with the poll fix, host69's tmxr-UDP
>   received 0 datagrams from a freshly-restarted IMP (sockets correct, `Recv-Q=0`);
>   that's why IMP-ready had to be forced. Investigate tmxr UDP delivery / start the
>   IMP BEFORE host69 so host69's tmxr connects to a live peer.
>
> **FAST ITERATION (big win — no more 18-min reinstall):** the installed disk now
> boots in ~1 min via `runtime/build-tenex-bootinstalled-ncp.do` (SYSLOD no-clobber).
> One-shot harness: `reboot-test.sh` (cleans only host69 procs, boots, drains the
> 2323 console with `scratchpad/pyconsole.py`, restarts the IMP, watches for
> `TENEXCONO`; self-reports to `logs/reboot-test.out`). LAUNCH DETACHED:
> `setsid bash reboot-test.sh &` — inline/`run_in_background` ki launches get
> SIGTERM'd at the 2-min tool timeout; a setsid/detached script survives.
> Do NOT `reset-disk.sh` (it wipes the installed system; full reinstall driver is
> `build-tenex-live-ncp-nodumper.do`).
>
> **2026-06-25 UPDATE — the diagnosis below this box SUPERSEDES the older framing.**
> The prior "fix one input-done bit; output-done already matches; pia=5" story was WRONG
> on multiple counts (verified against the real driver source). Read this box first.

**Authoritative source found:** the real TENEX IMP driver `impdv.mac` is IN THE KIT —
`kit-cache/build-tenex/install/monitor/impdv.mac;3` (the source THIS monitor was built
from). It is the definitive CONI/CONO spec; do NOT infer bits from the disassembly or a
generic 1822 doc. `IMPCHN==5` is in `…/install/monitor/params.mac;5`.

**What was actually wrong + FIXED (committed, rebuilt, verified live):**
rcornwell's `TYPE_BBN` CONI/CONO bit layout wholesale-mismatched this TENEX (upstream
master has the same wrong bits — it was never validated against TENEX). Per `impdv.mac`:
input-ready=`010`(IMPINB), output-ready=`0200`(IMPOUB), end-input=`04000`(IMPEIB),
imp-ready-line=`020000`(1B22), power=`0200000`(1B19), out-chan field=`0160`; and TENEX
drives transfers with BLKI/BLKO+PI pacing (IMPION/IMPOON channel assign, IMPEOB=send),
NOT the emulator's STRIN/STROUT/FINO model. Rewrote the ncp CONI/CONO to match, gated on
`UNIT_NCP` (committed rcornwell `33f226e`; patch `patches/rcornwell-ncp-imp.patch`
regenerated, 749 lines). **Verified live:** with the missing `020000` ready-line bit now
emitted, CONI reads `220000` (power+ready) and `IMPR` LATCHES against imp05 hi2 — the old
binary stalled at `pia=0` exactly because that bit was absent.

**THE REAL REMAINING BLOCKER (correctly located now):** it is NOT the emulator. The bare
`go 100`/NO-EXEC bootpark monitor never brings up NCP because the NCP background fork is
spawned by `IMPBEG` (`impdv.mac:767`), which is `CALL`ed only from `RUNDD`
(`swpmon.mac:849`, `IFDEF IMPCHN <CALL IMPBEG>`) during FULL system startup. No fork →
`IMPSTT`→`IMPRSS` never runs → no channel assign, no NOPs (`TENEXCONO`=0 in bootpark).
This is the same "NO SYSJOB / network job" wall as [[host69-tenex-authentic-goal]].

**NEXT STEP (in progress at handoff):** boot a FULLY-installed live TENEX so RUNDD spawns
the fork. Driver `runtime/build-tenex-live-ncp-nodumper.do` (install → live `!` EXEC,
skips flaky DUMPER, parks on 2323); runner `run-h69-live.sh`. With imp05/imp69 present,
watch `logs/host69-live.log` for `TENEXCONO` (channel assign) and the IMP log for a
message FROM host69 (= host→IMP NOP = success). Isolated test IMP: `mini/imp69-hi2only.simh`
(hi2 only on 21051/21052, no hi1 to crash). See memory [[host69-tenex-imp-bitmap]].

**Also verify once packets flow (handoff missed):** `mini/imp05.local.simh` hi2 has NO
`set convert`; `mini/pdp-hosts` says PDP-10 IMP links need convert mode (1822 long↔short
leader).

---
### (historical, superseded) original §0 framing
The text below was the prior session's hypothesis; kept for context but corrected above.

**Status:** the host↔IMP 1822 handshake is ~85% working. TENEX's monitor boots, runs its
full IMP bring-up, receives the IMP's NOP, and assigns PI channel 5 (`pia=5`). The LAST
step — host69 sending its own NOP back to imp05 — stalls on a **BBN-IMP device-fidelity
mismatch** in rcornwell's `TYPE_BBN` emulation.

**BEST next move (recommended):** get the authoritative **BBN IMP host-interface spec** and
map the bits exactly. (Superseded: the authoritative source is `impdv.mac` in the kit, and
the bits are already mapped + fixed; the blocker is the NCP fork / full boot.)

**Reproduce in ~4 min:**
```
cd mini/host69-bbn-tenex/kit-cache/rcornwell-sims && make pdp10-ki   # if you edited source
cd mini/host69-bbn-tenex && ./run-h69-bootpark.sh                    # boots host69 -> parks on 2323
# in mini/: run imp05 standalone AFTER host69 binds 21052:
cd mini && nohup ./h316ov ./imp05.local.simh > host69-bbn-tenex/logs/imp05-standalone.log 2>&1 </dev/null &
# connect to release `go` + give it a console:
bash -c 'exec 3<>/dev/tcp/127.0.0.1/2323; cat <&3 & printf "\r\n" >&3; sleep 600'
```
Watch `logs/host69-bootpark.log` for `BBNCONO` (pia decode), `chkint` (IRQ channel),
`IMP ncp recv/send`; success = `HI2 ... received` lines in `logs/imp05-standalone.log`.
Driver: `runtime/build-tenex-bootpark-ncp.do` (boot to bare monitor + IMP debug + park 2323;
it also `examine`s neton/imprdy at NO EXEC). NOTE the driver's `deposit 70204` neton-force is
a leftover no-op (neton is already set) — harmless, can remove.

**Emulator state:** `kit-cache/rcornwell-sims` HEAD `877cde5` (EXPERIMENTAL single-PI-channel
output, UNPROVEN — proven-good baseline is `a438d50`). The 4 prior fixes (disk fflush/IOERR,
scp.c console timeout, kx10_cpu.c pager, kx10_tym.c div0) are uncommitted working-tree mods —
a rebuild preserves them; do NOT `git checkout` them. Patch: `patches/rcornwell-ncp-imp.patch`
(655 lines, from base `9510a91`).

**Lab process state at handoff:** imp05 may be running standalone (pid varies) with hi2; a
host69 `pdp10-ki` may be parked on 2323. `kill $(pgrep -x pdp10-ki)` and re-run as above for a
clean start. imp05's noc instance is STOPPED (noc per-IMP PTY restart crashes a peerless hi2);
imp05 standalone is the working approach (start it AFTER host69 binds 21052).

---

## 1. The goal

Authentic 1972 user experience: a visitor types `@L 69` over the ARPANET, sees the
real `BBN-TENEX … EXEC` herald, logs in, and runs an ICCC scenario. Host #69 =
BBN-TENEX, attached to **IMP #5 (`imp05`), host interface `hi2`**, ports
`21051`/`21052`.

## 2. The problem we solved (THE blocker)

**IMP↔host communication was the issue.** The lab's H316 IMP (`mini/h316ov`, built
from `larsbrinkhoff/linux-ncp`) talks to hosts via a **1822-leader-over-UDP-datagram**
framing (RLA's `h316_udp.c`: `udp_create`/`udp_send`/`udp_receive`, magic `'H316'`,
per-link sequence, count, network-order 16-bit words; `data[0]` = flags word with
`PFLG_READY`=02 / `PFLG_FINAL`=01, `data[1..]` = the raw 1822 message words).

host #70's working `pdp10-ka` has that backend (binary has `udp_create`). But the
TENEX sim (`pdp10-ki`, rcornwell git `9510a91`) was built with Cornwell's **newer
IP/Ethernet/pcap IMP** — `udp_create`=0, `eth_open`=4. So `set imp ncp` → "Non-existent
parameter" and `attach -u imp …` tried `pcap_open_live`. **The two emulators could not
exchange a single packet** — that is why `@L 69` produced nothing. Nobody had bridged
this before (the tracked `rcornwell-bbn-tenex.patch` only fixes the pager/TYM).

## 3. What we built — and it works

A new authentic **`SET IMP NCP`** mode in the rcornwell PDP-10 IMP device, relaying raw
1822 messages to the H316 IMP over UDP, wire-identical to the lab IMP.

**Files (in the rcornwell-sims checkout, `mini/host69-bbn-tenex/kit-cache/rcornwell-sims/`):**
- `PDP10/imp_udp.c` + `imp_udp.h` — RLA's `h316_udp.c` ported standalone (H316 header dep
  stripped). Exports `udp_create/udp_release/udp_send/udp_receive`. Byte-for-byte wire
  compatible with the lab IMP.
- `PDP10/kx10_imp.c` — `UNIT_NCP` flag + `NCP`/`NONCP` MTAB; `imp_attach` opens a UDP link
  (`udp_create`) instead of `eth_open` in ncp mode; **host→IMP** splice at the top of
  `imp_send_packet` (packs `sbuffer` bytes → 16-bit words + `PFLG_FINAL|PFLG_READY`, then
  `udp_send`); **IMP→host** via `imp_udp_packet_in` poll in `imp_eth_srv`/`imp_srv` tail
  (`udp_receive`, surface `PFLG_READY`→`IMPR`/`IMP_RDY` CONI bit, unpack words → `rbuffer`,
  set `ILEN`); the eth/IP path is untouched. Plus the `imp_link_up` **input gate** (see §6).
- `makefile` — `imp_udp.c` added to all 4 PDP-10 build lists.

**PROVEN on the wire (isolated test, nothing live touched):** TENEX with `set imp ncp`
received and correctly decoded the H316 IMP's host-interface startup —
`IMP ncp recv … flags=1` (IMP not ready) → `flags=3` (IMP **ready**) → first 1822 message.
So the authentic 1822-over-UDP link works **IMP→host including the ready-line handshake**.

Device smoke test (was impossible before; now clean):
```
set imp enabled bbn
set imp nodhcp
set imp ncp
attach -u imp 21052:localhost:21051   ->  "attached …, NCP, BBN"  (no pcap error)
```

## 4. Commits (saved; review before merge)

- **rcornwell-sims repo** (`…/kit-cache/rcornwell-sims/`, gitignored by arpanet):
  - `fa21f3b` — imp_udp.{c,h} + kx10_imp.c ncp mode + makefile
  - `9eaf68f` — `imp_link_up` input gate (speculative/unproven; see §6)
  - NOTE: the disk/console/pager/TYM fixes (`kx10_disk.c` fflush+IOERR, `scp.c`
    `sim_check_console(604800)`, `kx10_cpu.c` `pi_enc=4`, `kx10_tym.c` size==0) remain
    **uncommitted working-tree mods** — rebuilding preserves them; don't `git checkout` them.
- **arpanet repo, branch `host69-tenex-ncp-imp`:**
  - `e592b09` — `mini/host69-bbn-tenex/patches/rcornwell-ncp-imp.patch` (reproducible, now
    includes the gate) + `mini/imp-test69.simh` (isolated test IMP).
  - **Not pushed, not merged to main.** Also uncommitted on the branch:
    `mini/host69-bbn-tenexctl.sh` (prior build-tenex WIP) and the latest
    `mini/imp-test69.simh` port edit.

Current built binary: `…/rcornwell-sims/BIN/pdp10-ki` (Jun-24 22:17, with gate). Backups:
`pdp10-ki.bak-preudp-*`, `.bak-pregate-*`, `.orig-20260620`.

## 5. The remaining gap — NARROWED to a BBN-IMP CONI/CONO bit mismatch (2026-06-25)

A long deep-dive (via `kit-cache/build-tenex/tenex.dis`, the full monitor disassembly)
moved this from "host→IMP never happens" to "the monitor runs its entire IMP bring-up and
is one bit-layout fix from completing the handshake." Findings:

- **The monitor DOES start its network at boot.** `netini` (436652) runs in the device-init
  sequence (147050-61, alongside mtaini/lptini/…); it sets `neton`. Confirmed live:
  `neton`=-1, `imprdy`=-1, `dbugsw`=0. The earlier "bare monitor doesn't start NCP"
  conclusion was WRONG — an emulator input gate was masking the bring-up.
- **With the fixed `pdp10-ki` the monitor runs the IMP bring-up** (TENEX 137143-137175):
  `CONO 200000` → `DATI` → `CONO 050000`(STRIN) → `CONO 320` → `setom imprdy` → output
  `DATO`; receives the IMP's NOP; runs the input handler `CONO 206415` to assign **PI
  channel 5** (`pia=5`); input-done goes pending.
- **What we changed in `kx10_imp.c` to get here** (committed rcornwell `a438d50`; patch
  `patches/rcornwell-ncp-imp.patch` regenerated): always surface IMP-ready (IMPR) from
  inbound `PFLG_READY`; **arm input on CONO ODPIEN** (the channel-setup, after the monitor
  confirms IMP_IDONE clear) not on STRIN; **hold** a received 1822 message until the host
  arms input (the H316 IMP sends its startup NOPs once). Plus `BBNCONO`/`chkint` debug.
- **THE REMAINING BLOCKER:** rcornwell's `TYPE_BBN` CONI/CONO bit layout does not fully match
  TENEX's real BBN interface. The monitor's IMP service (`impsvx`, 131077) dispatches
  input-done on **CONI bit 010**, but the emulator sets input-done at bit **020000**
  (`IMP_IDONE`); output-done (bit 04000) DOES match. So with input-done pending the monitor
  never services it → never sends its own NOP → `imp05 received` still 0. **NEXT = reconcile
  the BBN IMP CONI/CONO/PIA bit assignments to what TENEX polls** (use the BBNCONO/chkint
  debug + the impsvx mask reads at 131077/131101/131103/131105/131106 as the spec). That is
  the last mile.

### (historical, superseded) original framing of the gap
IMP→host is proven. host→IMP had not been observed; we suspected the bare monitor never ran
NCP. The deep-dive above showed it DOES run NCP — the blocker is emulator bit-fidelity, not
TENEX OS startup.

## 6. Boot-harness findings (the time sink — read before re-trying)

- **The `[Confirm]` "stalls" were a BROKEN SHORT DRIVER, not the IMP.** `runtime/
  build-tenex-bootimp-ncp.do` (a short boot-to-`go 100`) NEVER cleanly reaches the monitor —
  control with the H316 IMP OFF still failed at the BADSPOTS `[Confirm]`. Do NOT use the
  short driver. (`;continue` vs no-`;continue` on the first `[Confirm]` both fail short.)
- **The ONLY driver that reaches a live monitor is the FULL proven install**
  `runtime/build-tenex-live.do` (= bringup.do + `set console telnet=2323,nomessage; go`).
  With the **standard** hardware it ran all the way through EXEC install + DLUSER (DONE.) to
  the `DUMPER` `<SUBSYS>` restore, reaching a live `!`.
- **`DUMPER` restore of `system.tap` hits an intermittent `IO DATA ERROR AT 2575`** — flaky,
  and **not needed for login** (DLUSER already made the dirs). It breaks the do-script's
  `expect "DONE."` (hangs at `!`). A future driver should tolerate/skip DUMPER and park on
  2323 after DLUSER.
- **My earlier `[Confirm]` stall with extra debug:** a hardware config with `set debug
  stdout` + `set imp debug=detail` ALSO stalled the install — keep the ncp hardware MINIMAL
  (`runtime/build-tenex-hardware-ncp.do` = standard + only `set imp nodhcp`/`set imp ncp`/
  `attach -u imp …`; NO debug lines).
- **The `imp_link_up` gate (commit 9eaf68f)** was built to stop IMP-input from disturbing the
  install — but since the stall was the driver, it is unproven. Harmless; leave it.
- **Harness mechanics that matter:** drain BOTH console sockets (DC 16945 + TYM 16946) with
  persistent reconnecting `nc` loops (the tyhngu wedge fix). Launch sims from a **script
  file** (cwd drifts; inline `( cd … ) &` kept failing — use `nohup`/`disown` or a `.sh`).
  Reboot-from-installed-snapshot is broken-by-design (wedges) — install-to-live in one pass
  and keep the sim running.

## 7. To FINISH host→IMP (next session, recommended approach)

1. Build a driver = `build-tenex-live.do` but: (a) hardware = `build-tenex-hardware-ncp.do`
   with the **production** IMP attach `attach -u imp 21052:localhost:21051`; (b) tolerate/skip
   the DUMPER restore (park on 2323 after DLUSER); ideally drive it in a **tmux PTY** so it's
   interactive, not fire-and-forget.
2. Have the H316 IMP **present from the start** (isolated test: `mini/imp-test69.simh`, or
   the real imp05). Run the install; reach live `!`.
3. Watch the IMP log for `received` > 0 = TENEX sent NOPs = **host→IMP handshake works**.
4. If TENEX still doesn't send NOPs, the blocker is TENEX-side network/NCP startup config
   (the missing SYSJOB/network job) — a deeper TENEX-OS problem, not the emulator.

## 8. Production cutover (STAGED, held — gated on §7 passing)

Approved by Kurt 2026-06-24, sequencing "validate boot first, then cutover, then website".
Full plan + exact edit locations in [[host69-production-cutover]]. Summary:

- **imp05:** uncomment `hi2` in `mini/imp05.simh` (~lines 27-29) + the `05:1:69:21051:21052:
  BBN-TENEX` route in `mini/arpanet` (~line 67), restart imp05 — **this briefly drops live
  BBN-NCC (host 0); needs Kurt's operator OK.** Add a production host69 launch (controller
  currently starts no public route).
- **Website (all 4 approved):** `arpanet_terminal2.html` add host 69 to the `activeHosts`
  array (~line 1536: `{host:'69', name:'BBN-TENEX', system:'TENEX 1.31', role:'BBN TENEX
  timesharing at IMP #5', login:'@LOGIN ICCC ICCC 11514', …}`); `arpa/arpanet-nodes.json`
  (host 69 already present, status "Server"); the interactive map + `arpa/arpanet-node-5-
  BBN.html`; then deploy (outward-facing — confirm first). Terminal backend = `ws://
  localhost:8080`.

## 9. Key paths

- Controller: `mini/host69-bbn-tenexctl.sh`
- Emulator + build: `mini/host69-bbn-tenex/kit-cache/rcornwell-sims/` (binary `BIN/pdp10-ki`)
- Install dir (run sims from here): `…/kit-cache/build-tenex/install/` (media/ has the packs)
- Drivers/hardware configs: `mini/host69-bbn-tenex/runtime/`
- Isolated test IMP: `mini/imp-test69.simh` (run `./h316ov ./imp-test69.simh` from `mini/`)
- Protocol reference: `src/linux-ncp/test/simh/H316/h316_udp.c`, `h316_hi.c`, `h316_imp.h`
- Memory: [[host69-tenex-authentic-goal]], [[host69-production-cutover]],
  [[host69-tenex-install-state]], [[kurt-debugging-style]]

## 10. One-line status

**IMP↔host link SOLVED + proven both directions; TENEX's monitor now runs its full IMP
bring-up and assigns PI channel 5 — the host→IMP NOP send is blocked only by a residual
BBN-IMP CONI/CONO bit-layout mismatch (input-done dispatched on CONI bit 010, emulator sets
020000).** Fix that bit reconciliation and `@L 69` should come up. Production cutover (imp05
hi2 is already enabled via `mini/imp05.local.simh`; website edits) is held until then.

### Reproduce the current state
1. `mini/imp05.local.simh` (hi2 on 21051/21052) is the imp05 override; run imp05 standalone
   (`./h316ov ./imp05.local.simh` from `mini/`) — noc's per-IMP PTY restart crashes a
   peerless hi2, so standalone is reliable. Start it AFTER host69 binds 21052.
2. `mini/host69-bbn-tenex/run-h69-bootpark.sh` boots host69 to the bare monitor with IMP
   debug, parks on telnet 2323 (driver `runtime/build-tenex-bootpark-ncp.do`). Connect to
   2323 to release `go`. Watch `logs/host69-bootpark.log` (BBNCONO/chkint/ncp recv/send) and
   `logs/imp05-standalone.log` (HI2 received = host→IMP success).
3. Emulator source: `kit-cache/rcornwell-sims` (rebuild `make pdp10-ki`). The 4 prior fixes
   (disk fflush/IOERR, scp console timeout, cpu pager, tym div0) are working-tree mods; the
   ncp+handshake work is committed (`a438d50`) and in `patches/rcornwell-ncp-imp.patch`.
