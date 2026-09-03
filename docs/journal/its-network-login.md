# ITS network login — activating the present-but-dead MIT/HILTON hosts

**Effort:** make the MIT ITS PDP-10s (**#70 MIT-DM, #134 MIT-AI, #198 MIT-ML**) and the
**HILTON-KA1 (#126)** KA-10 actually answer ARPANET logins. **State: ✅ done** (native NCP).
This is the `feature/its-ncp-debug` line (the early Civitae work, now on the droplet).

## The trap: present ≠ active
Upstream (`obsolescence/arpanet`) shipped these ITS hosts as **present and bootable** — the dirs,
the `pdp10-ka` emulator, the disk images are all there, and the README lists 70/134/198 as the
"working" hosts. **But they did not answer network logins.** Two independent bugs:

1. **Silent NCP plumbing failure.** The IMP host-attach lines used `attach -u hi* …:localhost:…`.
   On any host where `localhost` resolves to IPv6 (`::1`), the IMP host interface (which binds
   IPv4) closed immediately with `HI – UNRECOVERABLE I/O ERROR`. NCP packets appeared to send
   but never left the source IMP. The network *looked* up and was dead.
2. **KAIMP interrupt bug.** The stock KA-10 emulator (`pdp10-ka`) mishandled the IMP interrupt
   (PDP-10/its issue #2376), so ITS never serviced an incoming NCP connection — `@L` hung.
   Worse, on a KA running ITS 1652, the *first* NCP connection caused a **kernel panic**.

## What we did (all beyond upstream — verified absent from upstream main)
- **`localhost` → `127.0.0.1`** in the `attach -u hi*` lines of all 18 NCP-backed IMP configs
  (`imp01…imp35`). Note: `imp06` (the MIT IMP) was intentionally left — MIT ITS hosts use ITS's
  own NCP stack and attach via a separate mechanism. *(CHANGELOG 2026-06-09; commit `2320fdf`.)*
- **`@O` old-Telnet (socket 1) plumbing** through `do.sh`/`dotelnet.sh` so `@O <host>` selects
  old-Telnet (socket 1) instead of always opening new-Telnet (socket 23). *(commit `2320fdf`.)*
- **`pdp10-ka-fixed`** — a patched KA-10 emulator with the **KAIMP interrupt fix**. With it,
  **ITS answers network logins.** Lives at `mini/pdp10-ka-fixed` (and per-host copies). *(Civitae
  commit `d0b9b76`; binary is **not** in upstream — upstream ships the unfixed `pdp10-ka`.)*
- **Chaosnet enable** to stop the KA ITS 1652 kernel panic on the first NCP connection.
  *(Civitae commit `c94457b`.)*

## Result
- #70/134/198 MIT ITS and #126 HILTON-KA1 are **native-NCP-active** — they answer `@L`/`@O`
  over the simulated ARPANET (not a bridge). #126 in particular was a present-but-dead upstream
  stub that this work **completed**.
- This is the authentic-integration tier: ITS speaks its own period NCP on the IMP, exactly like
  TENEX is being made to (`docs/host69-ncp-login-investigation.md`).

## Where it lives / how to verify
- Emulator: `mini/pdp10-ka-fixed`; host dirs `mini/host70|host134|host198|host126`, launched by
  `mini/host*.sh` / `mini/hostctl.sh`. IMP configs in `mini/imp*.simh` (now `127.0.0.1`).
- Reproduce-ish: bring the lab up (`./arpanet-recover.sh recover`), then `@L 70` / `@L 134` /
  `@L 198` / `@L 126` should reach the ITS banner/login.
- Pending: there is **uncommitted WIP** on the old Civitae line (`mini/src/ncpd-ovREUSE/src/ncp.c`
  and friends) that differs from the droplet's current version — the droplet is authoritative; treat
  Civitae's copy as a history lookup only if a specific regression needs bisecting.
