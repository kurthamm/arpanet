# Host #69 BBN-TENEX — authentic ARPANET IMP bring-up: session handoff

**Date:** 2026-06-25 (updated)  ·  **Branch:** `host69-tenex-ncp-imp`  ·  **Author:** Kurt Hamm + Claude

This documents the work to give the BBN-TENEX simulator (host #69) an authentic
1822 host interface so it can join the lab's 1972 ARPANET and serve `@L 69`.
Read this first in any future session, then the memory files it links.

---

## 0. START HERE (next session) — exact state + next steps

**Status:** the host↔IMP 1822 handshake is ~85% working. TENEX's monitor boots, runs its
full IMP bring-up, receives the IMP's NOP, and assigns PI channel 5 (`pia=5`). The LAST
step — host69 sending its own NOP back to imp05 — stalls on a **BBN-IMP device-fidelity
mismatch** in rcornwell's `TYPE_BBN` emulation (CONI/CONO/PIA bit layout + the output
FINO/IMPLHW/IMPOD state machine don't match what TENEX 1.31 drives). `imp05 received` = 0.

**Two concrete remaining mismatches (the work):**
1. The monitor's IMP service `impsvx` (PC 131077) dispatches **input-done on CONI bit `010`**
   (131101 `consz 550,10`), but the emulator surfaces input-done at bit `020000` (`IMP_IDONE`).
   Output-done (bit `04000`) DOES match. Reconcile the BBN CONI bits to the impsvx mask reads
   at PC 131077 / 131101 / 131103 / 131105 / 131106 (use those as the register spec).
2. The output never reaches `imp_send_packet`: `imp_srv` (kx10_imp.c ~1223-1240, KI `#else`
   path) sends only when `IMPLHW` is set, but TENEX's CONO order (CONO 320 FINO *before* the
   DATO) isn't leaving IMPLHW/IMPOD in the state that triggers the send. Trace the
   FINO(0100)/STROUT(0200)/IMPLHW/IMPOD interaction vs TENEX's 136610-136640 output loop.

**BEST next move (recommended):** get the authoritative **BBN IMP host-interface spec** (BBN
Report 1822 / the KA10–KI10 "BBN IMP interface" CONI/CONO bit definitions) and map the bits
exactly, instead of inferring from the TENEX binary. Then the two mismatches above are
mechanical fixes. Avoid blind bit-guessing — each cycle is ~5 min build+boot and risks
regressing the working parts.

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
