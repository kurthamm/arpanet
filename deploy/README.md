# Deployment Layout

This directory contains the production runtime units for the DigitalOcean
droplet.

The intent is to keep the hosted ARPANET stack reproducible and boring:

- one supervisor for the IMP/NOC layer;
- one unit per hosted PDP-10 host;
- one browser relay;
- one terminal launcher;
- one local static server.

The PiDP-10 replica is not managed here. It belongs to the separate
PiDP companion repository and its Pi-side runtime.

## Systemd units

The unit files live in `deploy/systemd/`:

- `arpanet-noc.service`
- `arpanet-host@.service`
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
sudo systemctl enable --now arpanet-host@6.service
sudo systemctl enable --now arpanet-host@70.service
sudo systemctl enable --now arpanet-host@126.service
sudo systemctl enable --now arpanet-terminal-client.service
sudo systemctl enable --now arpanet-simh-server.service
sudo systemctl enable --now arpanet-static.service
sudo systemctl enable --now cloudflared-arpanet.service
```

## Notes

- `arpanet-host@.service` is for the hosted trio only: `6`, `70`, and `126`.
- The browser launcher `do.sh` still routes `@L 41` / `@L 051` through
  source NCP `ncp31`, but host `41` itself is external and site-local.
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
