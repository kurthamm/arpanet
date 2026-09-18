# Host 69 (BBN-TENEX) — unstick plan, TOPS-20 study, and next steps

**Host:** 69 / octal 105 · IMP 5 (imp05) · a PDP-10 **KI10** running **BBN-TENEX**.
**Status:** reaches the real TENEX `@` EXEC and a login, but **not reliably serving** — marked
`planned` on the website and kept **off the `@L` menu**. Goal of this doc: the concrete path to a
*reliable* `@L 69` login so it can go `live`.
**Date:** 2026-09-18.

---

## Where host 69 actually stands (not "never worked")

The real-login **gate was met** (commit `6833ee8`, 2026-06-28): `@L 69` reaches the **real
BBN-TENEX `@` EXEC** — `SUMEX-AIM Tenex 1.31.82`, `EXEC 1.51`, a live `@` — via:

- **Path B:** `NETLIT-1c` DOICP + **`ATPTY` (JSYS 274)** hands the inbound **NCP** connection to
  TENEX's *own* login path: `ASNNVT` → carrier → `START JOB` → EXEC, gated with `ENTFLG=-1`.
  This sidesteps the NETSER/FAIL-v11 wall.
- Client path: `NCP=ncp31 ./ncp-telnet -o 69` (**socket 1 / old-style**, not default 23).
- Run the ki in the **`h69r` tmux**.

Other host-69 problems already root-caused/handled:
- **Output wedge** (post-FORCEDOWN IMP OUTPUT channel stuck) — fixed in emulator fork `37744c0`
  (`kx10_imp.c`: set `IMPOD` after EOB ship so `IMODN2` runs). The full NCP stack walks:
  lab sends RTS, NETLIT `GDSTS LSNG→RFCR`.
- **Idle CPU spin** — root-caused to a **genlck spinlock** (`slockr`/105200); shipping mitigation
  is a host-side **`CPUQuota` cap** on the ki (Kurt rejected leaving it hot).
- **Persistence** — do **not** reboot TENEX (upstream-broken; wedges in CHKBT). Instead **SIMH
  `SAVE` a fully-booted state and `RESTORE -F`** forever; the restored TENEX comes up NETWORK ON.
- **File transfer onto the live disk** — SOLVED via **DECtape COPY** (not DUMPER/GET).

### What's actually left (the "polish" from the gate)
1. **Persistent listener** — the current path serves a login but isn't a durable, always-on server.
2. **Prove a credentialed `LOGIN user password`** over the NVT connection (not just reaching `@`).
3. **Tune NVT echo.**
4. **Drop the diagnostic marker** left in the NETLIT path.

---

## What studying SDF's TOPS-20 taught us (the living TENEX cousin)

Logged into the Interim Computer Museum / SDF **TOPS-20** (real XKL TOAD-2, `LOGIN noaccount
icmguest`) — TOPS-20 is the direct descendant of TENEX, so its login/EXEC model is the reference
for what host 69 should do.

**Confirmed:**
- A healthy TENEX-family login is exactly: **connect → herald → `@` EXEC → `LOGIN user password`
  → in.** **Host 69 already reaches that `@` milestone** — it lands at the same prompt the working
  TOPS-20 does. So host 69 is at the right place; the gap is durability + a proven `LOGIN`.
- **The transferable insight → the persistent listener:** the TOPS-20 herald advertises
  *"Use the **ATTACH** command to recover **detached jobs**."* TENEX/TOPS-20 natively support
  **detached jobs + `ATTACH`**. That is the idiomatic way to run a *persistent* login service:
  keep the login/EXEC job **detached**, and have each inbound NCP connection **`ATTACH`** to it
  (or spawn+ATTACH), instead of a fragile bespoke listener that dies after one connection. Host 69
  is TENEX, so it has DETACH/ATTACH too — use it.

**Honest limits (what TOPS-20 could NOT give us):**
- SDF's TOPS-20 is reached over a **modern telnet bridge, not NCP** — so its *network login
  transport* does not map to 1972 TENEX-over-NCP (host 69's actual layer).
- It's **guest-surface only** (no monitor internals) and has the **same buffered-MTY telnet quirk**
  that blocks deep scripted capture (same lesson as our own consoles: drive with a raw pipe / real
  TTY, never a fragile expect).
- Therefore TOPS-20 **validates the target behavior, but is not a shortcut to the JSYS/NCP/ATPTY
  internals** — those are host-69-internal work backed by TENEX source + the JSYS manual.

---

## Next steps (prioritized)

1. **Resume Path B (ATPTY / NETLIT-1c), not NETSER.** NETSER assembly is blocked on a FAIL/STALLM
   macro-version mismatch and there's no prebuilt NETSER on the box — Path B already reaches a live
   `@`, so build on it.
2. **Make the listener persistent via a detached TENEX job + `ATTACH`** (the TOPS-20 pattern):
   run the login/EXEC job detached; on each inbound NCP connection, `ASNNVT`→`ATTACH` to it (or
   spawn a fresh job and attach). This replaces the one-shot listener behavior.
3. **Prove a full credentialed `LOGIN user password`** over the NVT connection end-to-end (reaching
   `@` is done; drive an actual login to a working session and capture it).
4. **Tune NVT echo** and **remove the diagnostic marker** in the NETLIT path.
5. **Keep the idle CPU capped** (`CPUQuota` on the ki) so a persistent host 69 doesn't cook a core.
6. **Back the work with real TENEX docs from bitsavers** — the **TENEX JSYS manual** and **EXEC
   reference** (for `ATPTY`/`ASNNVT`/`LOGIN`/detach-attach semantics). That's where the internals
   live — *not* ICM/SDF.
7. **Go-live when reliable:** add `@L 69` to `dotelnet.sh`/website `@L` menu and flip the node from
   `liveStatus: 'planned'` → `'live'` in `arpa/assets/js/arpanet-nodes.js` (host 69 BBN-TENEX).
   Until then it **stays off the menu** (do not advertise a flaky host).

## Testing notes / gotchas carried forward
- Test via a **real TTY**, not a raw non-interactive pipe: `NCP=ncp31 ./ncp-telnet -o 69` in a PTY
  (or the `do.sh` visitor path). A raw pipe only prints "TELNET to host 105" with no herald.
- Don't probe imp05's live hi2 (21051) with a throwaway ki — it drops imp05's host sockets and
  bricks host69's boot until imp05 restarts.
- Rebuild the emulator (`make pdp10-ki`) after any `kx10_imp.c` change; the ki runs in `h69r` tmux.

## Cross-references
- Existing host69 spine: `docs/host69-go-live-plan.md`, `docs/host69-ncp-login-investigation.md`,
  `docs/host69-tenex-ncp-imp-handoff.md`, `docs/host69-tenex-idle-patch.md`,
  `docs/host69-bbn-tenex-plan.md`.
- ICM/SDF study source: `docs/icm-sdf-vintage-systems-reference.md` (TOPS-20 = `[b] toad-2`).
- Memory: host69-real-login-gate, host69-netser-build-attempt, host69-tenex-idle-genlck,
  host69-output-wedge-rootcause, host69-netlit-1c-and-tmux, host69-tenex-saverestore-breakthrough.
