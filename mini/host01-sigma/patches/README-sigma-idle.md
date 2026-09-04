# Sigma (host 1 / CP-V) idle detection

The open-SIMH XDS Sigma sim shipped with **no idle support** (`SET CPU IDLE` ->
"Non-existent parameter"), so it busy-spun the host CPU at ~94% while CP-V sat idle
waiting for an interrupt (OP_WAIT / wait_state). On a 4-vCPU droplet running the whole
ARPANET that was a chronic ~1 core of pure waste and a major source of mesh
oversubscription.

## Fix
`sigma-cpu-idle.patch` (against the sim tree at `src/linux-ncp/test/simh`, base
`2ccfed85`): adds the IDLE/NOIDLE CPU modifiers and calls `sim_idle(TMR_RTC, TRUE)` in
the `wait_state` branch of `sigma_cpu.c` so the host sleeps while CP-V waits for an
interrupt (the `// put idle here` spot the sim already flagged). Config
`mini/host01-sigma/f00rad.simh` now has `set cpu idle`.

Rebuild + deploy:
```sh
cd src/linux-ncp/test/simh && git apply /path/to/sigma-cpu-idle.patch && make sigma
# host01-sigmactl.sh / arpanet-host01-sigma.service run BIN/sigma f00rad.simh
```

## Result
Instantaneous sigma CPU **94% -> ~57%** with CP-V idle (host 1 still serves `@L`).
Real reduction (~0.4 core reclaimed); the remaining ~57% is per-RTC-tick poll work
between waits -- room for further reduction but a solid, correct fix (idle detection,
not a throttle/cap). Same class of fix as the TENEX genlck idle work.
