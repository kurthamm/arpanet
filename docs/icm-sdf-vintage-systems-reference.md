# ICM / SDF Vintage Systems — reference for our ARPANET boxes

**What:** The **Interim Computer Museum** (ICM, Tukwila WA; inherited much of the Living
Computers: Museum + Labs collection) runs a public **remote vintage-systems cluster** with
**SDF.org**. It's the setup in the Interim Computer Museum photo (PDP-10 + Altair, shown at VCF
Southeast / Atlanta, Sept 2026). Captured live 2026-09-18.

**Why it matters to us:** it's the same *OS lineage* we run — and their **ITS is version 1652, the
exact same ITS as our HAMM-KA0** (`KA ITS.1652`). Their PDP-10s run on the same SIMH KA-10 / PDP-6
lineage, reached over an **MTY device** (same telnet-line quirk we see on our own consoles). The
difference is architectural: **they expose each machine over a modern SSH→telnet bridge — no IMPs,
no NCP.** We have the actual ARPANET (IMP/1822/NCP/`@L`) between hosts; they don't. Complementary.

## How to connect (verified)

```
ssh menu@tty.sdf.org          # then: "Are you NEW? (y/n)" -> y ; press RETURN for GUEST
```
Also: web terminal at `https://ssh.sdf.org`, or point a browser/telnet at `connect.sdf.org`.
- At `(main) Your choice? (q to quit):` type the letter of a system.
- **CTRL-]** returns from a system to the menu; **CTRL-Z** gets the terminal's attention; `q` quits.

## The live roster (captured 2026-09-18) — and how it maps to our hosts

| SDF | System | Machine | ~ our host |
|-----|--------|---------|-----------|
| a | Multics MR12.8 | Honeywell 6180 (DPS8M sim) | **host 6 MIT-MULTICS** |
| b | TOPS-20 7(110131) | XKL TOAD-2 (real) | TENEX-family → ref for **host 69** |
| c | TOPS-20 7(63327) | XKL TOAD-2 (real) | ″ |
| d | TOPS-20 MARS | SC Group SC40 | ″ |
| e | TOPS-10 MARS 7.05 | SC40 | — |
| **f** | **ITS ver 1652** | **PDP-10 KS10 (real) / PDP-6 sim** | **hosts 49/70/126/134/198 (ITS)** |
| g | TOPS-10 6.03a | sim KA10 1050 | — |
| h | TOPS-10 7.04 | sim KL10 2065 | — |
| i | OpenVMS 7.3 | VAX 4000-96 | — |
| j | TSS/8 | PDP-8/e | — |
| k | VM/SP5 | Hercules 4361 | — |
| l | CTSS | i7094 | — |
| m | NOS 1.3 | DTCyber CDC-6500 | — |
| n | Honeywell CP-V | XDS Sigma (sim) | **host 1 UCLA-Sigma** |
| o | Dartmouth/GE DTSS | GE-265 sim | — |
| 1 | UNIX submenu | MissPiggy Unix v7, m-net, UNIX50 | — |

**Guest logins per system:** ITS → `:login tourist` (`:logout`); WAITS → `LOGIN 1,USR` (`KJOB`);
Multics → guest per on-screen prompt. (Their ITS/WAITS aren't on this menu snapshot but are in the
collection: WAITS on KL-1095 host `waits`, extra ITS on PDP-6 host `its`.)

## Their notes = the SDF "vintage systems" wiki (the closest thing to ICM docs)

These are ICM/SDF's own per-machine operating notes — read/borrow freely:
- ITS: `wiki.sdf.org/doku.php?id=vintage_systems:its_topics` → ITS Survival Guide (DDT), "Games on
  and off ITS", "Adding a new ITS user", "How to start/stop ITS", Maclisp/PDP-6 LISP, Logo.
- WAITS: `…:waits_topics` — `LOGIN 1,USR`, `DIR`, `TYPE file`, `KJOB`; files `NAME.EXT[PRJ,USR]`;
  `$` = ESC. (Directly useful for our **host 11**.)
- Multics: `…:multics` — paths use `>` (and `<` = parent); editors `qedx` / Multics EMACS /
  Multics TECO; PL/I, Multics Maclisp; `help` not `man`. Deeper: **multicians.org** and
  **multics-wiki.swenson.org**. (For our **host 6**.)
- TOPS-20: `…:tops-20` — the `@` EXEC; the closest running relative of TENEX → **use as a working
  reference for host 69** (command style, EXEC behaviour).
- TOPS-10: `…:tops-10_survival_guide` · CP-V: `…:cp-v` · TYMCOM-X: `…:tymcom-x` · menu: `…:menu`.

## What is NOT available from ICM

No public GitHub, no downloadable disk images, no software downloads. Their blog
(`icm.museum/blog`) is narrative restoration stories (KICKI = their 1972 **KI10** PDP-10, PiDP-11/70
build workshop, GE-200 DTSS, Miss Piggy PDP-11/70 Xenix, Altair 8800) — light on configs. The
gettable value is: (1) **log in and study** live authentic systems, (2) the **SDF wiki notes**
above, (3) **the people** — small SDF-run nonprofit, exhibiting at **VCF Southeast, Atlanta (end of
Sept 2026, ~3 hr from Columbia SC)**; best route to real notes/collaboration, and our ARPANET layer
is the thing they *don't* have.

## Findings from logging in (2026-09-18)

- Reached the menu and entered ITS `[f]`; guest access is `:login tourist`. Their ITS is **v1652**,
  same as HAMM-KA0 — so our ITS build is museum-grade / identical lineage. Good validation.
- Their ITS sits behind a SIMH **MTY** device (`Connected to the KA-10 simulator MTY device`) — the
  same buffered-telnet behaviour that makes scripted capture flaky on our own consoles (use a raw
  pipe / real TTY, not a fragile expect, to drive it — same lesson as HAMM-KA0).
- Deep `:listf sys3;` / `games;` comparison didn't flush over their public guest link (that MTY
  buffering) — not worth hammering their service; the software set is the standard PDP-10/its build,
  same source tree we build from.
