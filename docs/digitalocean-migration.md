# DigitalOcean Migration and Runtime Fortification

This document describes how to migrate Kurt's ARPANET deployment from the shared Civitae server to a dedicated DigitalOcean droplet, and how to reduce the fragility observed during browser-terminal and host-lifecycle testing.

The goal is a reproducible, hardened deployment for the hosted ARPANET platform while keeping the physical PiDP-10 integration separate and optional.

## Scope

This document covers the DigitalOcean-hosted ARPANET platform:

- Hosted MIT-MULTICS host `6`, hosted ITS PDP-10 hosts `70`, `126`, `134`, `198`, and Stanford/SU-AI host `11`.
- The simulated IMP network under `mini/`.
- The hosted browser terminal relay.
- Cloudflare Tunnel and Tailscale access.
- Runtime supervision and health checks.

This document does not move PiDP-10 host `41` into the main hosted lifecycle. Host `41` is a physical external node and remains managed by the PiDP companion repository and the Pi-side runtime.

## Target Server

Initial target server:

- Provider: DigitalOcean Droplet.
- Hostname: `ARPANet`.
- Public IP: `192.241.140.201`.
- OS: Ubuntu 24.04 LTS.
- Size: 2 vCPU / 4 GiB RAM class.
- Admin user: `deltaprism`.
- Repository path: `/home/deltaprism/arpanet`.

The droplet is intended to become the production ARPANET host. Civitae should be treated as source/reference only after migration begins.

## Security Posture

The droplet should start locked down:

- UFW enabled.
- Default incoming policy: deny.
- Default outgoing policy: allow.
- Direct inbound public services: SSH only during setup.
- Public web access: Cloudflare Tunnel only.
- Private operator/admin access: SSH and Tailscale.
- No direct public ARPANET, IMP, NCP, WebSocket, or emulator ports unless explicitly justified later.

Current baseline commands used during setup:

```sh
sudo apt-get update
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw --force enable
```

The `deltaprism` user should have passwordless sudo for administration:

```sh
sudo usermod -aG sudo deltaprism
echo 'deltaprism ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-deltaprism-nopasswd
sudo chmod 440 /etc/sudoers.d/90-deltaprism-nopasswd
sudo visudo -cf /etc/sudoers.d/90-deltaprism-nopasswd
```

## Required Packages

Minimum packages installed or expected on the droplet:

```sh
sudo apt-get install -y \
  git build-essential make gcc g++ pkg-config \
  python3 python3-venv python3-pip \
  screen tmux curl ca-certificates unzip zip rsync \
  lsof net-tools bubblewrap \
  libpcap-dev libvdeplug-dev libsdl2-dev libpng-dev \
  libedit-dev zlib1g-dev libpcre3
```

`libpcre3` is required by the checked-in `h316ov` binary. Without it, the IMPs appear to start and immediately crash with:

```text
./h316ov: error while loading shared libraries: libpcre.so.3: cannot open shared object file
```

## Repository Setup

Clone Kurt's fork and the migration branch:

```sh
cd /home/deltaprism
git clone --recurse-submodules --branch main https://github.com/kurthamm/arpanet.git arpanet
cd /home/deltaprism/arpanet
git submodule update --init --recursive
```

Python virtual environments are needed for the terminal relay components:

```sh
cd /home/deltaprism/arpanet
python3 -m venv web-terminals/simh-server/venv
web-terminals/simh-server/venv/bin/pip install --upgrade pip websockets
python3 -m venv web-terminals/terminal-client/venv
web-terminals/terminal-client/venv/bin/pip install --upgrade pip websockets
```

## Codex Remote Access

For Codex App remote work, the remote host needs the Codex CLI installed, authenticated, and available on the remote user's login-shell `PATH`.

Install on the droplet:

```sh
curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
sudo ln -sf /home/deltaprism/.local/bin/codex /usr/local/bin/codex
codex --version
codex login status
```

If the host is headless, copy an existing authenticated Codex cache only if the account owner explicitly approves it:

```sh
mkdir -p ~/.codex
chmod 700 ~/.codex
# copy auth.json securely to ~/.codex/auth.json
chmod 600 ~/.codex/auth.json
codex login status
```

## Runtime Ownership Model

Treat each host as an independent system attached to the IMP network:

| Host | Octal | Location | Lifecycle owner |
| --- | --- | --- | --- |
| `1` | `001` | DigitalOcean hosted UCLA-NMC Sigma 7 CP-V path | Dedicated `host01-sigma/host01-sigmactl.sh` |
| `6` | `006` | DigitalOcean hosted MIT-MULTICS DPS8M/MR12.8 path | Dedicated `host06-multicsctl.sh` |
| `70` | `106` | DigitalOcean hosted MIT-DM PDP-10 | Main ARPANET repo tooling |
| `126` | `176` | DigitalOcean hosted HILTON-KA1 conference-site PDP-10 | Main ARPANET repo tooling |
| `134` | `206` | DigitalOcean hosted MIT-AI PDP-10 | Main ARPANET repo tooling |
| `198` | `306` | DigitalOcean hosted MIT-ML PDP-10 | Main ARPANET repo tooling |
| `11` | `013` | DigitalOcean hosted Stanford/SU-AI WAITS PDP-10 | Dedicated `host11ctl.sh` / `arpanet-host11.service` |
| `41` | `051` | Physical PiDP-10 replica | PiDP companion repo / Pi-side tooling |

The browser terminal may connect to these hosts, but it must not restart or
mutate any host.

`mini/hostctl.sh` is scoped only to hosted ITS hosts `70`, `126`, `134`, and `198`.
Stanford/SU-AI host `11` uses `mini/host11ctl.sh`. UCLA-NMC host `1` uses
`mini/host01-sigma/host01-sigmactl.sh`. MIT-MULTICS host `6` uses
`mini/host06-multicsctl.sh`. Do not extend the PDP-10 tool to manage PiDP-10
host `41`.

## Known Fragility

The original runtime relies heavily on `screen` and broad process cleanup. This creates several failure modes:

- Duplicate emulators or NCP daemons can bind or race on the same ports.
- `screen -X quit` can leave child processes behind.
- Manual restarts can create duplicate `ncpdov` sessions beside NOC-owned `ncpdov` processes.
- Browser terminal sessions can leave stale `ncp-telnet` processes.
- Startup timing matters: hosts and NCP daemons can start before IMPs are fully converged.
- Site-specific PiDP/Tailscale changes can leak into upstream-friendly files if not kept separate.
- The hosted host `tk` listeners must be unique per host; `134`, `70`, `126`, and `198` now use `18012`, `17012`, `10012`, and `19012` respectively.
- Browser access to hosted hosts `6`, `70`, `126`, `134`, `198`, and PiDP host `41` uses simulator terminal lines. ARPANET reachability is validated separately with NCP ping and the IMP62/IMP41 link.
- Browser access to UCLA-NMC host `1` uses the SIMH Sigma 7 CP-V mux on
  localhost TCP `4003`. It is not yet a working recovered UCLA-NMC SEX/NCP
  attachment.
- Stanford/SU-AI PARRY depends on restored WAITS packs from Lars Brinkhoff's
  `sailing-on-arpanet` restoration. Use `mini/host11-restore-parry.sh --restart`
  if a fresh WAITS archive loses the PARRY support files.

The target deployment should keep vintage software behavior fixed and improve only the modern orchestration around it.

## Immediate Migration Blocker

During initial droplet testing:

- `h316ov` initially crashed because `libpcre3` was missing.
- After installing `libpcre3`, IMP processes reached `RUNNING` in the NOC.
- Hosted PDP-10s `70`, `126`, `134`, and `198` booted into ITS.
- NCP pings to hosted ITS hosts require separate validation after startup.
- A duplicate NCP condition was found: NOC-owned `ncpdov` processes existed alongside manual `screen`-owned `ncpXX` sessions.
- The PiDP link is loaded from the ignored local override `mini/imp62.local.simh` when present; the tracked `mini/imp62.simh` stays generic.
- Later validation showed NCP echo could pass while ARPANET TELNET sessions were not a repeat-safe browser path for some hosted images. Hosted browser sessions are kept separate from ARPANET TELNET validation.

Before further diagnosis, remove only the manual `ncpXX` screen sessions and leave NOC-owned `ncpdov` processes intact.

Diagnostic commands:

```sh
cd /home/deltaprism/arpanet/mini
screen -ls
ps -eo pid,ppid,pgid,sid,stat,args | grep '[n]cpdov' | sort -k6,6
sudo ss -lunp | grep ncpdov
```

Cleanup command for manual NCP screen sessions:

```sh
cd /home/deltaprism/arpanet/mini
screen -ls | awk '/[.]ncp[0-9]+[[:space:]]/ {split($1,a,"."); print a[2]}' | while read -r session; do
  [ -n "$session" ] && screen -S "$session" -X quit || true
done
```

Then verify that only one `ncpdov` instance owns each NCP socket and retest:

```sh
cd /home/deltaprism/arpanet/mini
for host in 31 6 70 126 134 198; do
  echo "=== $host ==="
  timeout 20 env NCP=ncp31 ./ncp-ping -c1 "$host" || echo "FAIL-$host"
done
```

If NCP still fails, diagnose from the NOC and IMP logs. Do not restart unrelated hosts or change PiDP host `41` as part of this hosted-host diagnosis.

## Target Service Model

The final deployment should replace ad-hoc production `screen` starts with explicit systemd units.

Recommended service split:

- `arpanet-noc.service`: starts and supervises the NOC/IMP network.
- `arpanet-host01-sigma.service`: UCLA-NMC host `1` Sigma 7 CP-V path.
- `arpanet-host@70.service`: hosted PDP-10 host `70`.
- `arpanet-host@126.service`: hosted PDP-10 host `126`.
- `arpanet-host@134.service`: hosted PDP-10 host `134`.
- `arpanet-host@198.service`: hosted PDP-10 host `198`.
- `arpanet-host06-multics.service`: MIT-MULTICS host `6`.
- `arpanet-host11.service`: Stanford/SU-AI WAITS host `11`.
- `arpanet-terminal-client.service`: browser WebSocket relay on localhost.
- `arpanet-simh-server.service`: session launcher connected to the relay.
- `arpanet-static.service`: local static HTTP server for the public site.
- `cloudflared-arpanet.service`: Cloudflare Tunnel ingress.

Each unit should have a single ownership boundary. Restarting one hosted PDP-10 should not restart the other hosted PDP-10s, Stanford host `11`, the PiDP-10, or the entire IMP network unless explicitly required.

## Service Safety Requirements

Before starting a hosted host service:

- Check that the expected screen/session/process is absent.
- Check that the host's TCP/UDP ports are not owned by an old PDP-10 simulator.
- Restore clean disk packs from the tracked clean-pack directory.
- Start the simulator.
- Verify NCP reachability.

Before starting terminal services:

- Check for stale relay-owned `ncp-telnet` processes.
- Check for stale relay-owned `ncp-telnet` and `local-host-terminal.py` processes.
- Kill only relay-owned stale sessions, not arbitrary terminal processes.
- Ensure the relay binds locally for Cloudflare Tunnel ingress.

Before starting Cloudflare Tunnel:

- Confirm static site responds on localhost.
- Confirm WebSocket relay responds on localhost.
- Confirm `.git` and known local artifacts are blocked by the static server.

## Health Audit

Use `mini/arpanet-health.sh` as the operator-level health check. It should remain read-only.

Expected checks:

- Hosted hosts `70`, `126`, `134`, and `198` have exactly one simulator owner each.
- NCP ping works for hosted hosts.
- PiDP host `41` is checked only when its Tailscale/IMP link is intentionally configured.
- No duplicate `ncpdov` processes own the same NCP path.
- No stale browser `ncp-telnet` or `local-host-terminal.py` process remains after sessions close.
- Terminal relay and static server are reachable locally.
- Site-local runtime changes are visible and documented.

## Cloudflare and Tailscale

Start with private and tunneled access only:

- Use Tailscale for operator/admin/private-node paths.
- Use Cloudflare Tunnel for public browser access.
- Keep UFW closed to direct public terminal, WebSocket, NCP, IMP, and emulator ports.

Cloudflare Tunnel should route:

- `https://arpanet.hamm.me/` -> local static server.
- `wss://arpanet.hamm.me/ws` -> local browser terminal WebSocket relay.

Do not expose the Codex app-server transport directly on the public network.

## Acceptance Tests

The migration is not complete until all of these pass on the DigitalOcean droplet:

```sh
cd /home/deltaprism/arpanet/mini
./hostctl.sh verify all
./host01-sigma/host01-sigmactl.sh verify
for host in 70 126 134 198; do timeout 20 env NCP=ncp31 ./ncp-ping -c1 "$host"; done
timeout 20 env NCP=ncp16 ./ncp-ping -c1 11
```

Browser terminal tests:

- Open the hosted terminal page through the Cloudflare hostname.
- Start a terminal session.
- Run `@L 1` and reach the Sigma CP-V login salutation.
- Run `@L 134` and reach the MIT-AI ITS banner/login behavior.
- Run `@L 70` and reach the ITS banner/login behavior.
- Run `@L 126` and reach the HILTON-KA1 ITS banner/login behavior.
- Run `@L 198` and reach the MIT-ML ITS banner/login behavior.
- Run `@L 11` and reach Stanford WAITS through the `waitsconnect` ARPANET TELNET bridge, landing at `CON-TELLOGIN`.
- From `@L 11`, log in with `1,REG`, run `R PARRY`, answer the setup prompts,
  and reach PARRY's `READY:` conversation prompt.
- Confirm closing/reopening the browser session does not leave stale relay-owned `ncp-telnet` or `local-host-terminal.py` processes.

Public site tests:

- Home page returns HTTP 200.
- Terminal page returns HTTP 200.
- `/ws` upgrades through Cloudflare Tunnel.
- `.git` paths return 404.
- Large local artifacts and private working directories are not served.

PiDP tests should be separate and run only after hosted hosts are stable:

- Tailscale path between droplet and Pi is active.
- IMP62 to IMP41 UDP path is configured as site-local runtime config.
- NCP ping to `41` works.
- Browser `@L 41` behavior is tested without restarting hosted hosts. If NCP ping works but historical NCP TELNET stalls at `TELNET to host 051.`, keep the browser route on the PiDP SIMH terminal line and diagnose the Pi-side TELNET/TELSER path separately in the companion repository.

## Rollback and Reference

Civitae should remain available as a read-only reference until the droplet is proven stable. Do not continue making production fixes on Civitae during the migration unless explicitly required for comparison.

If the droplet deployment fails, preserve logs and runtime evidence before cleanup:

```sh
cd /home/deltaprism/arpanet/mini
screen -ls
ps -eo pid,ppid,pgid,sid,stat,args | egrep 'h316|pdp10|ncp|terminal|simh|cloudflared'
sudo ss -lntup
./arpanet-health.sh || true
```

Then stop using controlled repo tooling, not broad process deletion.

## Documentation Rule

Future documentation should describe reproducible setup, operation, and troubleshooting. It should not be written as a diary of failed attempts. Failed attempts belong only when they identify a durable operational hazard, such as duplicate `ncpdov` sessions or missing `libpcre3`.
