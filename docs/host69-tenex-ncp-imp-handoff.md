# Host #69 BBN-TENEX — authentic ARPANET IMP bring-up: session handoff

**Date:** 2026-06-24  ·  **Branch:** `host69-tenex-ncp-imp`  ·  **Author:** Kurt Hamm + Claude

This documents the work to give the BBN-TENEX simulator (host #69) an authentic
1822 host interface so it can join the lab's 1972 ARPANET and serve `@L 69`.
Read this first in any future session, then the memory files it links.

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

## 5. The remaining gap: host→IMP (TENEX's monitor sending NOPs)

IMP→host is proven. **host→IMP — TENEX's monitor initiating the 1822 NOP handshake — has
NOT been observed (IMP `received` count = 0 in every run).** Two intertwined reasons:

1. **It requires a fully-booted live TENEX monitor with the IMP present at boot.** TENEX
   inits its IMP host interface once at `go 100`; if the IMP isn't responsive then, it does
   not appear to retry (starting the H316 IMP late produced no handshake).
2. **Whether the monitor brings up NCP at all over this link is the genuinely-unproven OS
   question** (see [[host69-tenex-authentic-goal]] "OPEN UNKNOWN"). The bare install-stage
   monitor (NO EXEC / NO SYSJOB) may not run the host-interface handshake.

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

**IMP↔host communication: SOLVED, proven on the wire, committed.** host→IMP handshake +
production cutover: staged and held, gated on a clean full-install boot with the IMP present
and the open TENEX-NCP-startup question.
