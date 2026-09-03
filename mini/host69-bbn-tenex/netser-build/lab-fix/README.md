# Lab routing fix — event-driven NCP startup (2026-06-27)

## What broke (my doing)
During the NETSER-lite work I `systemctl stop`/`start`ed `arpanet-noc.service` (to free
CPU for a TOPS-20 detour). After the restart the whole lab lost inter-host routing:
`ncp-ping` to every host (and `arpanet-health.sh`) timed out, and 16-18 of 18 IMP
host-interfaces were down.

## Root cause (NOT load — a timing race)
`mini/noc-server.py` started all IMPs, then waited a **hardcoded `NCP_START_DELAY = 35.0s`**
before starting the NCP daemons ("some IMPs take ~30s to reach RUNNING"). That 35s was
calibrated for the **old 2-vCPU droplet**. On the **upgraded faster box** the IMPs reach
RUNNING well before 35s, so their host-interfaces sat **peerless** (no NCP-daemon UDP peer)
long enough to hit "unrecoverable host-interface errors" → HIs down → no routing.

Key insight (Kurt): *it worked on half the processing power.* A slower CPU is what made the
fixed timer line up. So more cores exposed the latent race — it's a fixed-timer-vs-boot-speed
bug, not oversubscription. (Throttling IMPs to ~2-vCPU speed in `impconfig.simh` was a valid
workaround that confirmed this — it brought 18/18 HIs up — but it's a crutch and slows the lab.)

## The fix (in arpanet repo `mini/noc-server.py`; copy + patch here)
Start each NCP daemon **event-driven, the instant *its* IMP reaches RUNNING**, instead of a
global fixed timer. The noc already tracked IMP state.
- `_on_imp_state_change`: on `new_state == RUNNING`, call `_start_ncps_for_imp(imp.config.number)`.
- `_start_ncps_for_imp(imp_number)`: start the NCP(s) whose `config.imp == imp_number`;
  **idempotent** (skips NCPs already STARTING/RUNNING, reuses the existing controller — never
  spawns a duplicate `ncpdov`).
- `_schedule_ncp_start` repurposed as an **idempotent fallback sweep** (`_fallback_start_ncps`)
  at the old 35s, only starting NCPs whose IMP is already RUNNING — a backstop for a missed event.
- `NCPController.start()` was already guarded (only acts if STOPPED/CRASHED), so this is safe.
This is **CPU-speed independent** — works on 2 vCPU, 4 vCPU, throttled or not. Throttle reverted
to the original 15% in `impconfig.simh`.

## Verified (acceptance test, full speed)
- 36/36 IMPs RUNNING; **18 event-driven NCP starts** logged (`IMP NN RUNNING: starting NCP ...`).
- **18/18 host-interfaces up**; exactly 18 `ncpdov` (no duplicates).
- `ncp-ping` replies across the mesh (`ncp1→2`, `ncp31→1`, `ncp2→35`, `ncp35→31`, `ncp1→31`).

## Files
- `noc-server.py.event-driven-ncp-start` — the patched noc (copy of the live arpanet one).
- `noc-server.event-driven.patch` — diff vs the original (`mini/noc-server.py.bak-preEventDriven`).
- Live: `/home/deltaprism/arpanet/mini/noc-server.py` (running). Original backup alongside it.

## STILL OPEN — host69 reachability (the 1822 handshake)
The lab routes between NCP-daemon hosts, but **host69 (the real BBN-TENEX) is not yet reachable**
from the lab: it boots (operator prompt, NETWORK ON), the host69↔imp05 **hi2 UDP link is ESTAB**
(`21052↔21051`), but the mesh reports **"Host is not up"** — the **1822 host-IMP "host ready"
handshake** between host69 and imp05 isn't completing, so imp05 never advertises a route to host 69.
Restarting host69/imp05 in various orders (thrashing) hasn't reliably landed the handshake.
Open questions for next session:
- Is there a canonical host69 bring-up (repo host-lifecycle tooling / documented order) vs the
  ad-hoc `scripts/run-loginbuild.sh`? host69 is NOT in the noc's NCPS list (it's the real TENEX,
  not a daemon — correctly commented as `05:1:69`), so its lab integration is bespoke.
- A prior session got "Open refused" from `@L 69` — so host69 WAS reachable before; reproduce
  that wiring rather than guessing restart orders.
- Inspect host69's console NCP/IMP state: is it actually asserting host-ready / exchanging 1822
  with imp05's hi2, or stuck expecting the snapshot-time IMP?
Once host69 is reachable: load+run NETLIT (`LOADER` → `*DTA1:NETLIT` → `$G` → EXEC `START`),
connect `@L 69`, watch NETLIT's GDSTS reach RFCR — milestone 1a end-to-end.
