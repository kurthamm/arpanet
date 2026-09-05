# host69 TENEX idle-spin — isolated-rig root cause (2026-09-04)

## What was built
`mini/host69-bbn-tenex/idle-rig/` — a **safe, isolated reproduction rig** for the "TENEX
spins the CPU when the ARPANET link is up" bug, so it can be root-caused WITHOUT touching
the live mesh (the docs mandate this — probing the live imp05 islands the lab).

- `imp-test.simh` — a standalone `h316ov` IMP: same firmware/identity as imp05 (`num=5`)
  but **no modem/trunk lines** (isolated from the mesh) and `hi2` on **private ports
  41051/41052** (never collides with the live imp05 on 21051/21052). Completes the
  host-ready handshake so TENEX sees "link up".
- `run-ki-test.do` — restores the golden snapshot, **force-reattaches every disk to a
  disposable copy** (`idle-rig/install/media/*` — never the live packs), uses all-private
  I/O ports (dc 46945 / tym 46946 / console 42323 / imp 41052), runs the FORCEDOWN
  host-ready cycle, `set cpu idle`, `go`.
- `idle-rig/install/` — disposable copy of the disk packs (gitignored; relaunchable).

Run: start `imp-test.simh` (cwd=mini), then the ki from `idle-rig/install` against
`run-ki-test.do`, then drain console 42323. Reproduces the spin at ~47–73% CPU. Live
host69 stays untouched.

## ROOT CAUSE (the breakthrough)
The spin is a **spinlock on `genlck` (the TENEX general lock)**. Guest-PC histogram (via
`gdb -p <ki> -batch -ex 'p/o *(unsigned int*)&PC'`) mapped through
`kit-cache/build-tenex/tenex.dis`:

```
105172 = slockr   (global; the lock-acquire routine)
105200:  aose  genlck        ; test-and-set the general lock (addr 61263)
105201:  jrst  105200        ; <-- spin back on itself
```
A TENEX fork cycles `slockr → genlck → work (~115xxx/127xxx) → release → re-acquire`
continuously when the link is up, and busy-waits on `genlck` at 105200 instead of
dismissing. On a real single-CPU KI10 this spin is near-instant (the holder releases
immediately, interrupts off in the critical section); in emulation the lock stays
contended when the link is up — a busy maintenance fork (very likely NCP/IMP) holding /
re-taking `genlck`, possibly amplified by our own kx10_imp.c IMP-interrupt timing.

## NEXT STEP for the fix
Identify which fork holds `genlck` and why it keeps re-entering the critical section when
the link is idle-but-up (examine the runnable fork + the IMP-interrupt/timer that wakes
it), then fix the emulator so the fork dismisses like real hardware. Verify CPU drops on
the isolated rig; only then remove the interim CPUQuota cap. (`M[]` reads in gdb need a
cast — the `M` symbol collides with an enum; use the SIMH history or address math.)

## Related finding — this is a CLASS problem, and the box is oversubscribed
`sigma` (host 1, UCLA CP-V) chronically runs at **~94% CPU** — the same idle-spin class.
With 36 IMPs + 9 host emulators on a **4-vCPU** droplet, steady-state load is ~15–20;
TENEX (the most load-sensitive host) islands under that load. So the idle-spin fix is not
just cosmetic: fixing it on sigma + TENEX (and/or a larger box) is what makes all 9 hosts
sustainable at once. See `host69-tenex-idle-patch.md`.

## Process caution (bit us again 2026-09-04)
Repeated `ncp-telnet -o` probes + a second ki + gdb churn during this investigation
islanded the live mesh (load spiked to 31). Recovered by killing the rig + restarting
`arpanet-host69.service`. Keep rig probing minimal; never run the reproduction against the
live imp05.

## CONCLUSION 2026-09-05: genlck spin is inherent TENEX behavior, not an emulator bug
Ran the rig on a CPU-freed box and traced it fully. The `genlck` HOLDER is the KI10
clock-interrupt / metering path (`apclki`/`kimuos`/`mtime`/`kissav`/`kislod`); the scheduler
spins on `genlck` while that handler holds it, and link-up makes the scheduler run enough to
contend heavily. Checked the two emulator suspects and ruled both out:
- **RTC rate = 60 Hz** for the KI (`kx10_cpu.c`: `rtc_tps` is 500 only under `#if KS`; the KI
  build uses 60) — the clock is NOT over-firing.
- **imp_eth_srv poll is already adaptive** (10k fast window -> 100k quiet) — not the driver.
So the busy-when-link-up state is inherent guest behavior: a real KI10 ran the same NCP-fork +
scheduler + metering work (at ~1 MIPS, so it "pegged" its slow CPU too). There is no emulator
bug to fix. The host-side **CPUQuota cap on the ki is the correct management** of legitimate
emulation-speed CPU use — not a workaround for a bug. `SET CPU IDLE` can't help because TENEX
genuinely does not idle while the link is up. Closing the genlck line of investigation.
