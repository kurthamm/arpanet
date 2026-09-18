# HAMM-KA0 → the full-ITS showpiece (host 49, PiDP-10 on Tailscale)

**Effort:** turn Kurt's physical **PiDP-10** (`HAMM-KA0`, host 49 / octal 061) into the lab's most
complete ITS node — the full MIT-AI-Lab software set (games, Lisp, SHRDLU…), its own login
greeting, persistent + crash-safe — building on the earlier `imp-routed-sessions` work that first
put it on the ARPANET. **State: ✅ done** — full ITS rebuilt from source, all five headline games
launchable, greeting restored; live on `@L 49`, persistent/crash-safe, on the website.

> Split: this notebook is the **history + lessons**. The **reproducible how-to** (exact build
> commands, TECO/MIDAS greeting recipe, game-launch steps) lives in the companion repo,
> `pidp10-arpanet-node/docs/full-its-games-rebuild.md` — per the rule that PiDP-10 site/hardware
> specifics stay in the companion repo and platform history/lessons land in `main` here.

## Why this exists
HAMM-KA0 was already on the ARPANET (see `docs/journal/imp-routed-sessions.md`), but its disk pack
was a **reduced ITS build** — `SYS3;` held only utilities, no games or Lisp, so `:advent` / `:lisp`
returned "SYS3 … NON-EXISTENT". Kurt wanted the node to be a *showpiece*: the legendary AI-Lab
software (Zork, Colossal Cave, Spacewar, MacHack chess, Eliza, SHRDLU) running **on his own
hardware**, over the real IMP/NCP network. This is the arc from reduced pack → full-ITS showpiece.

## What we did (history)
1. **Found the pack was reduced** (games absent; `SYS3;` sparse). Root cause: it had been built with
   `BASICS=yes` (the CI/`.travis` minimal profile), not a full build.
2. **Tried the shortcut — swap in the stock full `its` packs.** It **failed to boot**: those packs
   are *"directories out of phase"* (mismatched ITS generation/MDNUM stamps), which the SALVAGER
   makes **fatal** on the DSKDMP + GOGO boot path HAMM-KA0 uses (they only boot the `its` system's
   own direct-disk READ-IN way). Rolled back to the working pack.
3. **Rebuilt the full pack from source** (`make … EMULATOR=pdp10-ka BASICS=no MACSYMA=no`, ~2h22m
   under emulation, `rc=0`). A **fresh single-build pack is in-phase** → boots clean via DSKDMP.
   Cut it over (compressed backup taken first).
4. **Greeting — two ways, done right:** baked into the build **source** (`telser.175` `KA` branch +
   regenerated `sources.tape`) so *every future build* includes it; **and** re-applied to the
   **live** pack (TECO edit + `:MIDAS` reassemble of the telnet server) so `@L 49` greets
   *"Kurt Hamm PiDP-10 - Columbia, South Carolina"* now — no downtime.
5. **Made every game one-command.** `:advent` and `:zork` worked already; `:eliza` needed an
   autostart Lisp band (SUSPEND) + link. Everything else — Spacewar (`:spcwar`), chess, Trek,
   Adventure 350/448, MacHack, Maze, Life, Nim, etc. — are pre-built `GAMES;TS *` executables, so
   they just needed a `SYS3;→GAMES;` **link** each (`:link sys3;ts NAME,games;ts NAME`). Linked them
   all: `:advent :zork :chess :chess2 :eliza :spcwar :tvwar :trek :adv350 :adv448 :animal :bkg :ckr
   :dazdrt :guess :maze :mlife :nimlin :o :sprout :c :ocm`. Log in first (`:login <name>` — turist
   can't play; authentic ITS). Display games (Spacewar/TV-war/MacHack) draw on the **Type 340**.
6. **Studied the Interim Computer Museum / SDF vintage-systems cluster** — same ITS 1652, same
   chess/SHRDLU/Type-340 demos. Validation, plus the key difference: they bridge each machine over
   telnet; **we route real IMP/1822/NCP** between hosts. See
   `docs/icm-sdf-vintage-systems-reference.md`.
7. **Carried a learning to host 69 (BBN-TENEX):** TOPS-20 (the living TENEX cousin, studied on SDF)
   → use TENEX **detached jobs + `ATTACH`** for a persistent login server. See
   `docs/host69-tenex-unstick-nextsteps.md`.

## Gotchas / lessons (cost real time)
- **Reduced vs full pack = the `BASICS` flag.** Manual `make … BASICS=no` gives games; the CI
  `BASICS=yes` profile is minimal. `MACSYMA=no` keeps the build shorter and smaller.
- **Scavenged packs "out of phase" are fatal on DSKDMP+GOGO.** A *fresh from-source* build is
  in-phase — **rebuild, don't scavenge** another system's disk images.
- **Rebuild only the `rp03` packs** (targeted `make out/pdp10-ka/rp03.2 …`); the top-level target
  also rebuilds the aux emulator (needs `autoconf`, which was missing on the Pi).
- **Bake the greeting into `sources.tape`, not just the working tree** — the build reads source
  from the tape. And **stray `.pre-*`/backup files in `src/` get tarred as a *duplicate*
  `SYSNET;TELSER`**, which can clobber the real one on the build disk. Keep backups OUT of `src/`.
- **Turn any ITS Lisp game into a `:command`:** `SUSPEND` an autostart band
  (`(sstatus toplevel '(ENTRY))`) to `((games) ts NAME)` **inside one `progn`** (setting the
  toplevel otherwise drops you straight into the game before `suspend` runs), then
  `:link sys3;ts NAME,games;ts NAME`. Suspend to `((games) …)`, **not** `((sys3) …)` — `sys3`
  parses as a *device*. (Pattern cribbed from `animal.133`'s own `DUMP`.)
- **Most games are already dumped executables** (`GAMES;TS *`) — just `:link` them into `SYS3;` for
  `:name` launch; only a true Lisp-source game (Eliza) needs the SUSPEND-band trick. And beware:
  `:lisp gjd;sine lisp` is **not** Spacewar (it only regenerates the display sine table) — the game
  is `GAMES;TS SPCWAR` (`:spcwar`). Verify a game's real launcher before documenting it.
- **Driving ITS reliably:** the CTY console needs a **`^Z` wake** before it accepts input; drive it
  with a **raw pipe** (`telnet <console>`), never fragile `expect` pattern-matching (which only
  captured the herald). Games require `:login <name>`.
- **Never `cp` over `rp03.*` while a sim has them open** (corrupts both) — stop all sims first.
  Note `pgrep -x` silently fails on the sim (process name > 15 chars); match the full command line.
- **Git/infra:** GitHub **deploy keys are per-repository** — the `arpanet` deploy key could not
  push the companion repo; a *dedicated* key per repo is required (fixed). And `pkill -f '<pat>'`
  will **self-match the shell running a heredoc** (exit 144) — run such kills from a script file.

## Status / remaining
- ✅ Full ITS; five games launchable; greeting restored; persistent + crash-safe; on the net
  (`@L 49`) and on the website (map node + detail page).
- Spacewar & MacHack chess are **Type-340 display games** — seen via `pdp type340` / `rpdp` / VNC
  (viewer on the user's own machine), not over a text `@L`.
- Every game is one-command now (`:name`); Spacewar is `:spcwar`/`:spacewar`. Optional: map-
  coordinate nudge on the website node.

## Cross-references
- Companion (reproducible how-to): `pidp10-arpanet-node/docs/full-its-games-rebuild.md`,
  `…/persistence-crash-recovery.md`.
- This repo: `docs/pidp10-host-identity.md`, `docs/icm-sdf-vintage-systems-reference.md`,
  `docs/host69-tenex-unstick-nextsteps.md`, and the earlier `docs/journal/imp-routed-sessions.md`
  (HAMM-KA0's ARPANET integration + host-49 renumber).
