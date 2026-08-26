# DeepSeek Harness LAN Deployment Pack

[中文](README.md) | **English**

Deploy [DeepSeek Harness (dsh)](https://github.com/deepseek-ai/deepseek-harness)'s Web UI as a local service and expose it to your **LAN** through an HTTPS reverse proxy, with one-click start/stop/upgrade management and an unlock patch for loopback-only features.

> ⚠️ **Security notice**: this pack lifts dsh's restrictions for remote browsers (see "Design background").
> Once deployed, **any device** on the LAN can use the host's agent capabilities (including command execution)
> and read/modify settings & credential state. **Trusted networks only.**
> For production, wait for dsh's official auth layer or access via an SSH tunnel only.

## Features

- One-click install: handles Node.js / nvm / dsh automatically
- LAN accessible: HTTPS reverse proxy (self-signed cert, auto-reissued when your IP changes)
- Full functionality over LAN: settings / agent presets / credentials usable from remote browsers (patched, reversible)
- Unified management CLI: interactive menu + subcommands (start/stop/restart/status/log/upgrade)
- Auto-start on login (desktop entry) plus an optional systemd --user service
- Upgrade-proof: the LAN patch re-applies automatically on every start after dsh upgrades

## Quick start

```bash
git clone https://github.com/gavinlee9051/deepseek-harness-pack.git
cd deepseek-harness-pack
bash install.sh
```

When done, open the printed URLs:

- Local: `https://127.0.0.1:3080`
- LAN: `https://<host-LAN-IP>:3080`

The first visit shows a certificate warning (self-signed); proceed past it.

## Daily usage

```bash
./dsh.sh            # interactive management menu
./dsh.sh status     # processes / URLs / version / patch state
./dsh.sh restart    # restart
./dsh.sh upgrade    # upgrade dsh, restart, re-apply patch
./dsh.sh log        # live logs
```

| Script | Purpose |
|---|---|
| `install.sh` | one-click deployment |
| `dsh.sh` | unified management CLI |
| `start.sh` / `stop.sh` | start / stop |
| `run.sh` | foreground launcher (for systemd) |
| `upgrade.sh` | upgrade dsh, restart, re-apply patch |
| `patch-lan.sh` | idempotent LAN-unlock patch |
| `gen-cert.sh` | self-signed TLS cert create/renew |
| `uninstall.sh` | stop service, remove auto-start registrations |

## Architecture

```
Browser (any device)
   │  https://<LAN-IP>:3080
   ▼
proxy.js (HTTPS, 0.0.0.0:3080)   ← self-signed cert cert/
   │  rewrites Host / Origin / Referer → 127.0.0.1:3081
   ▼
dsh web (HTTP, listens on 127.0.0.1:3081 only)
```

Override ports via the `PROXY_PORT` / `DSH_PORT` environment variables.

## Design background: why the proxy and the patch exist

Deployment runs into three layers of dsh security mechanisms; this pack solves each one
(and documents why it has to be done this way):

1. **Refuses to bind `0.0.0.0`**
   `dsh web --host 0.0.0.0` fails with "intentionally not supported yet for safety".
   → dsh stays localhost-only; a separate reverse proxy exposes it.

2. **Browser-trust fence + secure contexts**
   - The fence requires `Origin.host === Host.host`, and privileged RPCs additionally
     require a loopback Host authority — otherwise every `/api` call gets HTTP 403.
     `--trusted-host` only affects the Host check, it cannot satisfy Origin matching.
     → the proxy rewrites `Host` / `Origin` / `Referer` to the internal authority.
   - `crypto.randomUUID()` and other WebCrypto APIs only exist in secure contexts
     (HTTPS or localhost). Plain HTTP against a LAN IP makes the frontend fail with
     "crypto.randomUUID is not a function".
     → the proxy serves HTTPS (self-signed).

3. **Settings plane is loopback-only (by design)**
   The browser bundle decides "am I local?" purely from the page URL and disables
   settings/presets/credentials for non-loopback pages; the server additionally hard-codes
   those methods as loopback-only ("until a real authentication layer exists", per source).
   → `patch-lan.sh` flips the client-side `isLoopback` decision (original file kept as
   `.orig`; restore with `cp client.js.orig client.js` and restart). Combined with the
   proxy's header rewriting, full functionality works over LAN.

## FAQ

- **Certificate warning on first visit?** Expected (self-signed); trust it. The cert is
  re-signed automatically on next start if your IP changes.
- **Blank page or odd behavior?** Hard refresh (Ctrl+Shift+R); then check `./dsh.sh log`.
- **Patch lost after upgrading dsh?** It re-applies on every start. A `[patch] FAILED`
  message means the new version changed internals — please open an issue.
- **Firewall?** If ufw is active with deny-by-default: `sudo ufw allow 3080/tcp`.
- **Start before login?** `systemctl --user enable --now deepseek-harness.service`
  (headless persistence also needs `sudo loginctl enable-linger $USER`).

## License

MIT. dsh itself is [DeepSeek AI](https://github.com/deepseek-ai/deepseek-harness)'s MIT project;
this repository only contains deployment helper scripts.
