# DeepSeek Harness LAN Deployment Pack

[中文](README.md) | **English**

Deploy [DeepSeek Harness (dsh)](https://github.com/deepseek-ai/deepseek-harness)'s Web UI as a local service and expose it to your **LAN** through an HTTPS reverse proxy, with one-click install / start-stop / upgrade and an unlock patch for loopback-only features.

This repository ships two platform variants with the same architecture and unlock mechanics:

| Platform | Location | Notes |
|---|---|---|
| Linux / macOS (bash) | repository root | one-click install + systemd / desktop auto-start; see this page |
| Windows (PowerShell) | [`win/`](win/README.md) | one-click install + management CLI; see [win/README.md](win/README.md) |

> ⚠️ **Security notice**: this pack lifts dsh's restrictions for remote browsers (see "Design background").
> Once deployed, **any device** on the LAN can use the host's agent capabilities (including command execution)
> and read/modify settings & credential state. **Trusted networks only.**
> For production, wait for dsh's official auth layer or access via an SSH tunnel only.

## Features

- LAN accessible: HTTPS reverse proxy (self-signed cert, auto-reissued when your IP changes)
- Full functionality over LAN: settings / agent presets / credentials usable from remote browsers (patched, reversible)
- Session archive (archive / restore / delete sessions): applied automatically together with the unlock patch (`patches/archive-core-rc2.mjs`, from gavinlee9051/dsh-modern-skin)
- Unified management CLI: interactive menu + subcommands (start/stop/restart/status/log/upgrade)
- Upgrade-proof: the patches re-apply automatically on every start after dsh upgrades (the archive patch skips with a note on unsupported versions)
- Linux additionally: auto Node.js/nvm setup, desktop auto-start + optional systemd --user service

## Quick start

### Linux / macOS

```bash
git clone https://github.com/gavinlee9051/deepseek-harness-pack.git
cd deepseek-harness-pack
bash install.sh            # or: bash install.sh --no-autostart
```

### Windows

```bat
git clone https://github.com/gavinlee9051/deepseek-harness-pack.git
cd deepseek-harness-pack\win
powershell -ExecutionPolicy Bypass -File install.ps1
```

When done, open the printed URLs:

- Local: `https://127.0.0.1:3080`
- LAN: `https://<host-LAN-IP>:3080`

The first visit shows a certificate warning (self-signed); proceed past it. Then add a model provider
(such as DeepSeek) and paste your API key in Settings.

## Daily usage

### Linux / macOS

```bash
./dsh.sh            # interactive management menu
./dsh.sh status     # processes / URLs / version / patch state
./dsh.sh restart    # restart
./dsh.sh upgrade    # upgrade dsh, restart, re-apply patch
./dsh.sh log        # live logs
```

### Windows

Open a terminal in the `win` folder:

```bat
dsh-manage.cmd               interactive menu (1 start 2 stop 3 restart 4 status 5 log 6 upgrade 7 open web)
dsh-manage.cmd status        processes / URLs / version / patch state
dsh-manage.cmd restart       restart
dsh-manage.cmd upgrade       upgrade dsh, restart, re-apply patch
dsh-manage.cmd log           live logs (Ctrl+C to exit)
dsh-manage.cmd open          print the token login URL and open it in the browser
```

## Scripts

### Linux / macOS (repository root)

| Script | Purpose |
|---|---|
| `install.sh` | one-click deployment |
| `dsh.sh` | unified management CLI |
| `start.sh` / `stop.sh` | start / stop |
| `run.sh` | foreground launcher (for systemd) |
| `upgrade.sh` | upgrade dsh, restart, re-apply patch |
| `patch-lan.sh` | idempotent LAN-unlock patch |
| `patch-archive.sh` | session-archive feature patch (idempotent, auto-applied) |
| `patches/` | core patch definitions (`archive-core-rc2.mjs`, etc.) |
| `gen-cert.sh` | self-signed TLS cert create/renew |
| `uninstall.sh` | stop service, remove auto-start registrations |

### Windows (`win/`)

| Script | Purpose |
|---|---|
| `win/install.ps1` | one-click deployment (checks Node -> global dsh install -> start) |
| `win/dsh.ps1` | unified management CLI (includes patch / cert logic) |
| `win/dsh-manage.cmd` | cmd wrapper around `dsh.ps1` |
| `win/proxy.js` | HTTPS reverse proxy (0.0.0.0:3080 -> 127.0.0.1:3081), rewrites Host/Origin/Referer |
| `win/uninstall.ps1` | stop service; optionally remove global package / ~/.dsh data |

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
   → the client-side `isLoopback` decision is flipped (original file kept as `.orig`;
   restore and restart to revert). Combined with the proxy's header rewriting, full
   functionality works over LAN. Platform difference: Linux uses `patch-lan.sh`;
   Windows applies it automatically on start via `win/dsh.ps1`.

### Session archive feature

This repo bundles the **archive-session** core feature (core only, no skin styling)
from [dsh-modern-skin](https://github.com/gavinlee9051/dsh-modern-skin): the dsh
sidebar gains an "Archived" section and sessions can be archived / restored /
deleted. It is implemented as anchor replacements over compiled files of several
dsh core packages (`patches/archive-core-rc2.mjs`). Linux applies it via
`patch-archive.sh`, Windows via `win/dsh.ps1`, both idempotently on **every start**
(re-applied automatically after upgrades).

- **Version pinning**: the patch is validated against `dsh 0.1.1-rc.2`;
  `status` reports the "archive patch" state. If dsh is upgraded to another
  version the start scripts **skip it with a note** (so incompatible code is
  never half-edited) until the patch is updated for the new anchors.
- **Revert**: `npm install -g @deepseek-ai/dsh` followed by a restart restores
  the official build.

## FAQ

- **Certificate warning on first visit?** Expected (self-signed); trust it. The cert is
  re-signed automatically on next start if your IP changes.
- **Blank page or odd behavior?** Hard refresh (Ctrl+Shift+R); then check `./dsh.sh log`
  (Windows: `dsh-manage.cmd log`).
- **Patch lost after upgrading dsh?** It re-applies on every start. A `[patch] FAILED`
  message or "patch NOT applied" in status means the new version changed internals —
  please open an issue.
- **Firewall (Linux)?** If ufw is active with deny-by-default: `sudo ufw allow 3080/tcp`.
- **Firewall (Windows)?** Allow inbound TCP 3080.
- **Start at boot?** Linux: `systemctl --user enable --now deepseek-harness.service`
  (headless persistence also needs `sudo loginctl enable-linger $USER`); Windows: not
  registered by default — point Task Scheduler / the Startup folder at `win\dsh.ps1 start`.

## License

MIT. dsh itself is [DeepSeek AI](https://github.com/deepseek-ai/deepseek-harness)'s MIT project;
this repository only contains deployment helper scripts.
