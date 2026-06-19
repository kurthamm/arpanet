# BBN-TENEX Host #69 Lab

This directory is the isolated bring-up workspace for BBN-TENEX at ARPANET
host `#69` / octal `105`, attached to BBN IMP `05`, host index `1`.

This is not a public live host yet. The route remains disabled until a real
TENEX system boots and accepts real logins.

## Historical Identity

- IMP: `05`
- Host index: `1`
- Host number: `69`
- Octal: `105`
- Host name: `BBN-TENEX`
- Topology ports: `21051/21052`

## Emulator Direction

Use the project SIMH PDP-10 KA/KI path first. It supports the required TENEX
hardware features:

```text
set cpu 512k
set cpu bbn
set pmp enable
set pmp0 type=3330-2
set imp enable
set imp bbn
```

The primary unresolved problem is constructing or restoring a bootable TENEX
disk image, not browser routing.

## Public Rollout Gate

Do not connect this directory to `mini/arpanet`, the browser terminal, the
active host cards, or 2026 scenarios until validation proves:

1. TENEX boots.
2. A real EXEC prompt is reached.
3. A real user login works.
4. At least the basic 1972 BBN-TENEX scenario transcript works.

See `docs/host69-bbn-tenex-plan.md` for the evidence and full plan.

