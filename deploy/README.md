# Deployment Layout

This directory contains the production runtime units for the DigitalOcean
droplet.

The intent is to keep the hosted ARPANET stack reproducible and boring:

- one supervisor for the IMP/NOC layer;
- one unit per hosted PDP-10 host lane;
- one browser relay;
- one terminal launcher;
- one local static server.

The PiDP-10 replica is not managed here. It belongs to the separate
PiDP companion repository and its Pi-side runtime.

## Systemd units

The unit files live in `deploy/systemd/`:

- `arpanet-noc.service`
- `arpanet-host@.service` — ITS hosts only (`70`, `126`, `134`, `198`)
- `arpanet-host06-multics.service` — MIT-MULTICS host `6` (DPS8M; NOT the ITS template)
- `arpanet-host11.service`
- `arpanet-reconcile.service` — post-boot self-heal (re-marry hosts to their IMPs)
- `arpanet-fep.service`
- `arpanet-terminal-client.service`
- `arpanet-simh-server.service`
- `arpanet-static.service`
- `cloudflared-arpanet.service`

## Install

Copy the units into place on the droplet:

```sh
sudo install -m 0644 deploy/systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
```

Enable the hosted stack:

```sh
sudo systemctl enable --now arpanet-noc.service
sudo systemctl enable --now arpanet-fep.service
# MIT-MULTICS host 6 runs DPS8M via its own unit -- NOT arpanet-host@6 (that is the
# ITS PDP-10 KA template, which has no host-6 config and must stay masked):
sudo systemctl mask arpanet-host@6.service
sudo systemctl enable --now arpanet-host06-multics.service
# ITS PDP-10 hosts (MIT-DMS, HILTON-KA1, MIT-AI, MIT-ML):
sudo systemctl enable --now arpanet-host@70.service
sudo systemctl enable --now arpanet-host@126.service
sudo systemctl enable --now arpanet-host@134.service
sudo systemctl enable --now arpanet-host@198.service
sudo systemctl enable --now arpanet-host11.service
# Post-boot self-heal (re-marries any host whose IMP interface lost the boot race):
sudo systemctl enable --now arpanet-reconcile.service
sudo systemctl enable --now arpanet-terminal-client.service
sudo systemctl enable --now arpanet-simh-server.service
sudo systemctl enable --now arpanet-static.service
sudo systemctl enable --now cloudflared-arpanet.service
```

## Notes

- `arpanet-host@.service` is for the ITS PDP-10 hosts only: `70`, `126`, `134`,
  `198`. It uses a per-host lock (`/tmp/arpanet-hostctl-%i.lock`) so hosts start in
  parallel and one slow/broken host can never starve another. **Host `6` is NOT an
  ITS host** — it is MIT-MULTICS (DPS8M) and has its own `arpanet-host06-multics.service`;
  `arpanet-host@6` must stay masked.
- `arpanet-reconcile.service` runs once after the host lanes at boot. An ITS host is
  only "on the net" once it has NCP-married its IMP; the busiest IMP (imp06, four MIT
  hosts) can lose the boot-race attaching its last host interface. Reconcile detects a
  host whose IMP-side interface is detached and restarts that IMP with all host peers
  present (crash-safe), then re-boots its hosts to marry. A healthy boot is a fast no-op.
- `arpanet-fep.service` starts the front-end-processor bridges (`fepctl.sh`) for
  hosts that route through the IMP network without a native NCP (UCLA Sigma #1,
  MIT Multics #6, UCLA-CCN OS/360 #65). It `After=`/`Requires=arpanet-noc` and
  runs `mini/fep-wait-and-start.sh`, which waits (bounded 60 s) for the NCP
  sockets named in `mini/fep-hosts.conf` before `fepctl.sh start all`. A host
  whose backing simulator is not running on this box is skipped, not fatal, so
  the unit comes up cleanly with whatever hosts are present.
- `arpanet-host11.service` is for Stanford/SU-AI host `11`, which runs WAITS
  and uses the dedicated `mini/host11ctl.sh` lifecycle.
- Host services are adopt-safe: if a host is already running and passes NCP
  verification, starting the service records the unit active without stopping
  the working runtime.
- The browser launcher `do.sh` routes `@L 41` / `@L 051` to the external
  PiDP SIMH MTY terminal over Tailscale. Host `41` ARPANET reachability is
  validated separately through the IMP62/IMP41 link.
- Cloudflare Tunnel is kept in its own unit so the public edge can restart
  independently of the hosted IMP/NOC and browser relay services.
- Tailscale remains a separate operator setup step and is not managed by these
  units.

## Cloudflare Tunnel Setup

The Cloudflare tunnel unit expects a local config file at
`/etc/cloudflared/arpanet.yml`. A template lives at
`deploy/cloudflared/arpanet.yml.example`.

Install the template on the droplet, then replace the tunnel UUID / credentials
path with the real values created during `cloudflared tunnel create`.

The service runs as `deltaprism`, so the credentials JSON must be readable by
that user and should not be world-readable:

```sh
sudo install -d -m 0755 /etc/cloudflared
sudo install -m 0600 -o deltaprism -g deltaprism <tunnel-uuid>.json /etc/cloudflared/<tunnel-uuid>.json
sudo install -m 0644 deploy/systemd/cloudflared-arpanet.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared-arpanet.service
```
