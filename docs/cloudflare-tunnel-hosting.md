# Cloudflare Tunnel Hosting

This fork can be served through Cloudflare Tunnel at a normal HTTPS hostname.

## Working public URL

```text
https://arpanet.hamm.me/
```

Root redirects to:

```text
https://arpanet.hamm.me/arpanet_home.html
```

The terminal page is:

```text
https://arpanet.hamm.me/arpanet_terminal2.html
```

## Services on Civitae

The hosted page uses two local services:

```text
arpanet-static.service       http://127.0.0.1:8888
cloudflared-arpanet.service  Cloudflare Tunnel connector
```

The existing main Cloudflare service remains separate:

```text
cloudflared.service
```

## Tunnel routing

Dedicated tunnel:

```text
arpanet-page-20260611104028
bb4e811d-1731-4730-95b1-7d011e5a9cce
```

Hostname:

```text
arpanet.hamm.me
```

Ingress rules:

```yaml
- hostname: arpanet.hamm.me
  path: /ws*
  service: http://127.0.0.1:8080
- hostname: arpanet.hamm.me
  service: http://127.0.0.1:8888
- service: http_status:404
```

## Why `/ws` is used

The original terminal page expected the browser WebSocket server on port `8080`:

```text
wss://hostname:8080
```

That is not the right shape for a normal Cloudflare Tunnel-hosted HTTPS site. The page now uses:

```text
wss://arpanet.hamm.me/ws
```

Cloudflare routes `/ws*` to the local terminal WebSocket server on `127.0.0.1:8080`.

## Static server

Do not expose the repository with plain `python3 -m http.server`; it shows directory listings and can expose `.git` or local artifacts.

Use:

```text
web-terminals/static-server/serve_arpanet_public.py
```

It provides:

- `/` redirect to `/arpanet_home.html`.
- No directory listing.
- Blocking for `.git`, `PiDP Lab`, and `PIDP Computer Lab.zip`.

## Validation

```sh
curl -I https://arpanet.hamm.me/
curl -I https://arpanet.hamm.me/arpanet_terminal2.html
python3 - <<'PY'
import asyncio, websockets
async def main():
    async with websockets.connect('wss://arpanet.hamm.me/ws'):
        print('connected')
asyncio.run(main())
PY
```

Expected:

- `/` returns `302` to `/arpanet_home.html`.
- `/arpanet_terminal2.html` returns `200`.
- WSS connection to `/ws` succeeds.
