# host69 — TENEX CPU-idle investigation & emulator patch (2026-06-30)

**Status: IN PROGRESS — staged but not yet effective. Decision pending (see §7).**

This is the lab notebook for making the host69 BBN-TENEX KI10 emulator stop burning a whole
host core while idle. It is "big" because **nobody upstream had ever needed TENEX idle on
rcornwell's KI10 sim** — we are running TENEX as a persistent, mostly-idle login *service*, a
mode the emulator's idle detection was never written for. The result is a genuine first-of-kind
emulator patch (plus a remaining IMP-device change). Read this with
`mini/host69-bbn-tenex/kit-cache/rcornwell-sims/PDP10/kx10_cpu.c` (the patch) and
`docs/journal/README.md` (the spine).

---

## 1. Why we started — the load problem (and what it was NOT)

The box (4 vCPU) sat at load ~7–8. Recon of everything running:

- **36 H316 IMP simulators** (`h316ov`), **1 pdp10-ki** (host69 TENEX), **1 pdp10-ka** (host126).
- Upstream `obsolescence/arpanet` **runs the same 35-IMP farm** (its `mini/arpanet` launches
  IMPs 01–37 minus 15/21) and throttles each to `set throttle 15%` in `impconfig.simh` — so the
  farm was **not** something we wrongly added. (Upstream comments out `62:HILTON`; we run imp62.)
- The load came from **two unthrottled processes we added**:
  1. **imp62** — had `set nothrottle` → ~92% of a core. **Fixed**: removed `nothrottle` so it
     inherits the farm's 15% (commit pending). imp62 is load-bearing: it carries
     **host126/HILTON-KA1** (hi2, 21621↔21622) **and** the **PiDP-10 (host 41) Tailscale
     bridge** (mi2 → 100.105.230.31:11141 → the Pi's IMP41). See the topology note in the spine.
  2. **the host69 ki** — ~90–97% of a core, busy-spinning **even when idle**. This doc.

## 2. Dead end #1 — `SET THROTTLE` (documented to self-disable)

SIMH `SET THROTTLE` **turns itself off and runs full-speed when the host can't sustain the
requested IPS** (Sanyal; simh issue #361/#429). Our own runlog printed the smoking gun:

```
Host CPU could be too slow to simulate 1,000,000 cycles per second
Host CPU did only simulate 51,770 cycles per second
```

`25%`, `4M`, `1M` all no-op'd on the ki (the H316 IMPs honor throttle fine — different code path).
**Throttle is the wrong tool here.**

## 3. The right mechanism — `SET CPU IDLE` — and why it didn't fire

The rcornwell KI10 **implements `SET CPU IDLE`** (`kx10_cpu.c`: the `IDLE`/`NOIDLE` modifiers +
an idle-loop detector). But the detector only recognizes **TOPS-10** (jump-self in the AC block:
`PC<020 && AB<020 && (IR&0740)==0340`) and **ITS** (UUO via loc 041) idioms. **TENEX is not
covered**, so with `SET CPU IDLE` on, the ki stayed at 97%. (cf. simh issue #80, "KS10 Tops20
idle function not working" — idle detection on PDP-10 sims is OS-pattern-specific and brittle.)

## 4. Where TENEX actually idles — `SCHEDA` (empirically derived)

Captured the live idle loop two ways (CPU instruction history on a throwaway ki restored from the
golden snapshot; cross-referenced against `kit-cache/build-tenex/tenex.dis`, the symboled
disassembly of the *installed* monitor). TENEX's idle is **not** a one-instruction park; it is the
scheduler **wait-list scanner**:

- `SCHEDA = 0102713`, `SCHEDB = 0102714` (local symbols in `SCHED.MAC`).
- The loop walks the list of `DISMS`'d forks, calling `TIMET` to compare each fork's wakeup timer
  `fkintt(e)` against `todclk`. When no fork is runnable it spins `JRST SCHEDA` (102740) /
  `JRST SCHEDB` (102750) — **burning a whole core checking timers that only a clock tick can
  change.**
- This loop dominates the CPU **whether the IMP is up or down** (a runnable fork would be *run*
  instead, so SCHEDA-dominant ⇔ idle). That makes it a sound, stable detection point.

The general scheduler flow: `SCHED0 (100775) → SCH1 (forkx<0) → SKDJOB (101556) finds nothing →
back to SCHED0`, with the CPU spending the idle time inside the `SCHEDA` wait-list scan.

## 5. The patch (done) — teach the detector TENEX's idle

`PDP10/kx10_cpu.c`, in the "Check if possible idle loop" block, added a third clause alongside the
TOPS-10 and ITS ones:

```c
/* BBN-TENEX idle: ... scheduler wait-list scan SCHEDA ... */
(IR == 0254 && (AB == 0102713 || AB == 0102714))   /* JRST -> SCHEDA / SCHEDB */
```

- `IR = (MB>>27)&0777` is the 9-bit opcode; JRST = `0254`. `AB` is the resolved effective address
  (the jump target). So this matches exactly "about to `JRST SCHEDA/SCHEDB`."
- The ITS clause already hardcodes address `041`, so a TENEX-specific address is consistent with
  the file's own style. **These addresses are specific to the BBN-TENEX 1.31 monitor in the
  golden snapshot**; if that monitor is rebuilt, re-derive `SCHEDA` from `tenex.dis` and update.
- Rebuilt with `make pdp10-ki` (passes "Good Registers"). The new binary boots host69 to
  HOST-READY and serves logins normally. Backup of the prior binary:
  `kit-cache/rcornwell-sims/BIN/pdp10-ki.bak-preidlepatch`.

## 6b. Deeper dig (2026-06-30, second session) — idle ENGAGES but sleeps <1% of the time

Pushed further with `INT-CLOCK` idle-debug baked into the live service boot (`set int-clock
debug=idle` before `go`) + 4-minute settle + `gdb` PC sampling of the live ki. Refined picture:

- The **detector works and `sim_idle` is reached** — `gdb` breakpoint on `sim_idle` hits on the
  live ki with `sim_idle_enab=1`; the runlog shows **1070 actual sleeps** (+940 "too short").
- **But it only sleeps ~0.4% of wall-clock** (1070 × 1 ms ≈ 1 s over ~240 s) → ki stays ~97%.
  TENEX is **executing instructions ~99% of the time** when the ARPANET link is up.
- The pending-event devices `sim_idle` waits on: **`DK`** (disk, ~65 000 cycles out — far enough,
  yields the 1 ms sleeps) and **`TYM2`** (`tym_unit[2]`, the TYM/console interface) which
  **re-arms every 1 ms** (`sim_activate_after(&tym_unit[2], 1000)` µs, `kx10_tym.c:605`) →
  "too short: 0 usecs". DC is fine (it uses clock-aligned `sim_clock_coschedule`).
- **gdb PC histogram (proper-cast `*(unsigned int*)&PC`):** the live ki sits mostly in the
  **scheduler/scheda region** (`100775`–`105xxx`, `jrst scheda 102740`) with occasional
  excursions into the **IMP fork** (`131xxx`, just past `IMPBEG 131331`) — the NCP/IMP
  timer-driven maintenance loop (`impbeg`: `min(imptim,nettim,rfntim,negtim)` → dispatch
  `netchk`). (Earlier "PC = 06400" was a gdb artifact — it was reading the host RIP, not the
  guest PC; corrected.)

**Two emulator changes made this session (both login-verified, neither sufficient alone):**
1. `kx10_cpu.c` SCHEDA idle detector (§5) — correct, necessary, keep.
2. `kx10_imp.c` `imp_eth_srv` **adaptive re-arm** (was a flat `sim_activate(uptr,10000)` poll
   that itself sat under sim_idle's threshold): stay fast (10k) for a 50-poll window after any
   link activity, back off to 100k when quiet. Sound fix for a latent blocker, but did **not**
   drop CPU — because **`TYM2`'s 1 ms re-arm and TENEX's ~99%-busy execution dominate.**

**Refined conclusion:** the idle *infrastructure* now works; the wall is that, in the fully
network-up state, TENEX executes near-continuously — partly device-driven (`TYM2` 1 ms re-arm
keeps yanking it awake; the IMP fork wakes on its timers) and possibly a genuinely-runnable NCP
fork (could not confirm `NBPROC` — `gdb` couldn't read the typeless `M[]` array on the `-O2`
binary). A real KI10 didn't peg its CPU here, so this is emulation-side. **Remaining work is
multi-front and in load-bearing device code:** apply the same adaptive backoff to `TYM2`
(`kx10_tym.c`), confirm whether a TENEX fork is truly runnable, and only then will SET CPU IDLE
bite. Each step risks the working console/NCP path, so it wants careful per-step validation.

> ⚠️ **Process cost / lesson:** the many disruptive boot+probe cycles this session (each
> restarting imp05 to recover its host sockets) progressively **islanded the lab mesh**; required
> `sudo mini/arpanet-recover.sh recover` (full clean restart of all IMPs/hosts/noc) to fix. Future
> idle work should use an **isolated throwaway IMP pair** (a second `h316ov` on private ports) so
> the live mesh is never touched — do NOT probe against the live imp05.

## 6. The real blocker (first-session guess) — TENEX does not idle when the ARPANET link is UP

My first guess ("the IMP device isn't `UNIT_IDLE`") was **wrong** — checked the source: the IMP,
TYM, and DC console units **all already carry `UNIT_IDLE`**, and the clock/RTC units do too. So the
device side is fine. The truth came from `INT-CLOCK` idle-debug (`set int-clock debug=idle`) +
`perf`, run in three configs:

| config | `sim_idle()` calls / 5M instr | sleeps? | ki CPU |
|---|---|---|---|
| imp **detached** (`step`) | ~1035 | **yes, ~59%** ("pending event on DK") | low |
| imp attached to a **dead dummy port** | ~1400 | **yes, ~59%** | low |
| **live** (imp → imp05, network UP) | **~1** | no | **~96%** |

So the detector and `sim_idle` **both work** — but **in the live network-up state TENEX is
genuinely BUSY**: `sim_idle` is hit ~once per 5M instructions, i.e. **TENEX never reaches the
SCHEDA idle loop**; a fork is running continuously. `perf` on the live ki agrees: 59% `sim_instr`
+ 18% `Mem_read` + 15% `page_lookup` — it's executing guest code flat-out. And it is **not**
network traffic (tcpdump on 21051/21052 = ~0 pkt/s) and **not** NETLIT (its listen loop
`DISMS`es for `2000`₈ ≈ 1 s — negligible).

**Conclusion: the idle patch is correct but cannot help, because TENEX doesn't idle in
production.** When the host-IMP link comes up (host-ready), some TENEX fork spins continuously
even with no user connected and no packets flowing. A real 1972 KI10 did **not** peg its CPU on an
idle ARPANET connection (the 1822 interface was interrupt-driven) — so our emulation is making
TENEX busy where the hardware wouldn't. The likely culprit is the **IMP/NCP interaction** (the
host-IMP "ready"/status lines or an NCP maintenance fork polling), possibly amplified by one of our
own `kx10_imp.c` fixes (IMPOB/IMPOD/re-arm). **Not yet root-caused** — needs a PC histogram of the
live busy state mapped through `tenex.dis` (the capture attempt segfaulted on the history dump).

## 7. Where this leaves us — decision

- The **SCHEDA detector patch stays** (it's correct; the emulator genuinely lacked TENEX idle
  support, and it'll pay off once TENEX actually idles).
- The **real work** is now: *why does a TENEX fork spin continuously when the IMP link is up?*
  That's a deeper IMP/NCP investigation (Kurt has OK'd emulator changes — the guest is the
  artifact, the emulator is a tool).
- **Interim for load:** systemd `CPUQuota` on the host69 cgroup (applied after boot so boot stays
  fast) caps the ki regardless of the spin — guaranteed relief now, while the spin investigation
  proceeds. (Note `CPUQuota` slows emulated wall-clock speed; the KI10 was slow anyway.)
- Already banked: **imp62 `nothrottle` → 15%** (real ~0.75-core saving), and the whole TENEX-idle
  map above so nobody re-walks it.

## 8. Gotchas learned (the hard way)

- **Do NOT run a throwaway/probe ki that attaches to imp05's hi2 (21051) while you intend to keep
  the live service.** When the probe exits, imp05's hi2 UDP peer (host69 @ 21052) vanishes →
  imp05 gets ECONNREFUSED → **imp05 drops its host sockets (20051/21051) and only re-binds on its
  own restart.** This bricks host69's boot (`imp05_ready` never sees 21051). Recovery:
  `python3 impctl.py restart 05`, wait for `ss -uan | grep :21051`, then start host69. (imp05's
  *modem* links survive, so the mesh is not islanded — only its host interfaces die.)
- **systemd retry-storm:** rapid failed starts retry fast; each new `cmd_daemon` runs
  `pkill -9 -x pdp10-ki` and stomps the prior still-booting ki, and every ki death re-drops imp05
  hi2 → self-sustaining failure. Break it with `systemctl stop` + `reset-failed`, stabilize imp05,
  then **one** clean start (the boot takes ~3–4 min; don't poke it).
- The throwaway ki **segfaults on a stdio console** — use `set console telnet=2323` + a drainer
  (the known "use telnet console 2323" rule).
- IMP host links are **UDP** (`attach -u`) — check them with `ss -uan`, not `ss -tan`.
