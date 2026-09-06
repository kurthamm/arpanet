# PiDP-10 host identity — HAMM-KA0, host 49 / IMP 49

**Effort:** naming and numbering Kurt's physical PiDP-10 as a *unique, historically-grounded*
ARPANET node. **Date:** 2026-09-05. **Result:** the PiDP-10 is **`HAMM-KA0`**, host **49** /
octal **061** / **IMP 49**, description *"Hamm Computer Laboratory"* — a KA10 running ITS,
reached over a Tailscale IMP62↔IMP49 trunk. Verified: `ncp-ping 49` → "Reply from host 061";
`@L 49` → full ITS login; `arpanet-health.sh` → UP.

## Why it was renumbered off host 41

The node originally sat at host **41** / octal **051**. Research against the **actual text of
RFC 597** (NIC "Host Status", 12 Dec 1973 — parsed directly, not via any summary) showed that
octal 051 = **IMP 41, host slot 0**, and IMP 41 in the real ARPANET was **NORSAR** (the Norwegian
Seismic Array / NDRE), the network's first international node. So the PiDP-10 was unintentionally
impersonating a real site. Kurt wanted a *unique, fictional private node* — "a computer I own and
run, as if I could afford one in the 1970s" — which no real site ever occupied.

## The ARPANET host-number scheme (confirmed real)

A classic ARPANET host number is 8 bits: **octal = (host-slot × 64) + IMP#**, IMP in the low 6
bits (valid IMPs 1–63). The lab's decimal host labels are simply that octal value read in
decimal. This is exact history — from RFC 597:

| Lab host | Octal | IMP·slot | Real 1973 site |
|----------|-------|----------|----------------|
| 1   | 001 | 1·0  | UCLA-NMC (Sigma 7) |
| 6   | 006 | 6·0  | MIT-MULTICS |
| 11  | 013 | 11·0 | SU-AI (Stanford, WAITS/SAIL) |
| 65  | 101 | 1·1  | UCLA-CCN (IBM 360/91) |
| 69  | 105 | 5·1  | BBN-TENEX |
| 70  | 106 | 6·1  | MIT-DMS |
| 134 | 206 | 6·2  | MIT-AI |
| 198 | 306 | 6·3  | MIT-ML |
| 126 | 176 | 62·1 | HILTON-KA1 (Kurt's; IMP 62 vacant in 1973 — a nod to the Oct 1972 ICCC demo at the Washington Hilton) |

## Choosing a genuinely empty slot

Parsing every host number in RFC 597 and deriving IMP = host mod 64: the Dec 1973 ARPANET ran
IMPs 1–48 (with some slot gaps), and the **IMP numbers with nothing on them** were:

> **38, 39, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63**

The 1973 network's last IMP was 48, so **IMP 49 = "the next node the network would have added"** —
chosen as HAMM-KA0's home. (Scope: "vacant" here means *absent from the Dec 1973 host status*, the
exact era this lab recreates; the real net kept growing after 1973.)

## The name

ARPANET host names are `SITE-MACHINE` (or `SITE-FACILITY`). `KA` = the PDP-10 **KA10** processor
(the CPU ITS classically ran on; cf. the lab's `HILTON-KA1`); the digit is the host-slot index.
So **HAMM-KA0** = Kurt Hamm's KA10 at slot 0. The facility term is period-authentic: 1970s
university sites said *Computation Center* / *Computer Laboratory* (not "Computer Center") — hence
the description **"Hamm Computer Laboratory"** (`-LAB` flavor), cf. real sites `SU-DSL`, `ILL-CAC`,
`SDC-CC`.

## What was changed (mechanics)

- **Pi `imp41.simh`:** `set imp num=49` (the trunk ports 11141↔11262 don't encode the IMP number,
  so the droplet trunk is untouched). File still named `imp41.simh` — cosmetic.
- **ITS local host number `IMPUS`:** set to octal **061** via a boot-time DDT deposit in
  `boot.pidp` — `send "ITS\rIMPUS/61\r\eG\r"` (host-side patch at boot, **not** an image edit). ITS
  otherwise answers as the wrong host and `@L 49` fails.
- **Droplet:** `dotelnet.sh` (normalize 061→49, add `-o` old-style telnet for 49/061),
  `arpanet-health.sh` roster `49:HAMM-KA0`, README + CHANGELOG.
- **Backups:** `imp41.simh.pre-renumber49-20260905`, `boot.pidp.pre-renumber49-20260905`.

## Greeting — SOLVED (2026-09-06)

`@L 49` now greets **"Kurt Hamm PiDP-10 - Columbia, South Carolina"**. The greeting is the
Telnet server `SYSNET;TELSER`, keyed on the 2-letter machine name (`KA`). Kurt had added the
`KA` branch to the Linux source in June 2026, but the packs were built *3 days earlier*, so the
running TELSER predated the edit and fell through to the default `Unknown ITS PDP-10`. Fix:
re-edit `SYSNET;TELSER` on the pack (ITS TECO — `ER`/`EW`/`Y`/`N`/`-18D`/`I`/`EE`, not DEC
TECO's `EB`/`EX`) and reassemble `SYSBIN;TELSER` (`:MIDAS SYSBIN;TELSER_SYSNET;TELSER`, logged
in — a turist can't write `SYSBIN`). The greeting change persists (see below).

## Persistent + crash-safe (2026-09-06) — THE stable-server requirement

host 49 is now a **persistent server whose modifications survive a power-off** — full details in
the companion repo `docs/persistence-crash-recovery.md`. Summary:
- **Persistence:** the arpa51 `boot.pidp` per-boot disk-reset (line 20, `!cp -a … rp03 …`) is
  **disabled**. That reset — unique to `its-arpa51`; stock `its`/`tops20`/`waits` all persist —
  was the only reason changes didn't stick.
- **Crash-safe boot:** with the reset gone, a power-off leaves a dirty pack DSKDMP can't mount
  (`PKNMTD`). The boot now recovers it: `boot.pidp` line 2 expect →
  `send "L\e1\eL\e2\eL\e3\eITS\rIMPUS/61\r\eG\r"` — DSKDMP `L$1$ L$2$ L$3$` puts the packs
  **online**, then `ITS` + `IMPUS/61` + `$G` starts ITS, whose **SALVAGER.317** repairs the
  crashed pack (`CRASH; … KA ITS 1652 IN OPERATION`).
- **Validated:** the banner (a real change) was applied, the sim hard-killed (power-off), and on
  reboot the banner was intact + host 49 back up. **No data loss** — files with content persist;
  the SALVAGER only deletes *empty/incomplete* crashed directories.
- DSKDMP recovery primitives (from `system;dskdmp`): `S$` list packs, `L$n$` put disk n online.
- Pi backups: `boot.pidp.pre-crashrec-20260906`, `boot.pidp.pre-persist-20260906`. Golden clean
  packs remain at `src/its/out/pdp10-ka/rp03.*` for rollback.

## Sources

Parsed directly from raw text: [RFC 597 — Host Status (Dec 1973)](https://www.rfc-editor.org/rfc/rfc597.txt).
(Note: automated *summaries* of RFC 752 hallucinated host data during this research and were
discarded; only the directly-parsed RFC 597 host list was trusted.)
