#!/usr/bin/env bash
# patch-lan.sh - Unlock dsh's loopback-only features (settings / presets /
# credentials management) for LAN clients.
#
# Why: the browser bundle decides "am I local?" from the page URL
# (isLoopbackHostname(location.hostname)) and disables the settings plane for
# remote browsers. The server side accepts these RPCs when Host/Origin are
# loopback authorities - which proxy.js already rewrites - so flipping the
# CLIENT-side check is sufficient.
#
# The patched file is served from disk per request, so no rebuild is needed;
# a dsh upgrade restores the original and this script re-applies cleanly.
#
# WARNING: over LAN this means ANY device on the network can read/modify
# settings & credential state and drive the agent (command execution).
# Only use on a trusted LAN.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

NODE_REAL="$(readlink -f "$(command -v node)")"
TARGET="$(dirname "$(dirname "$NODE_REAL")")/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/lib/client.js"

[ -f "$TARGET" ] || { echo "[patch] target not found: $TARGET"; exit 1; }

if grep -q 'dsh-lan-patch' "$TARGET"; then
  echo "[patch] already applied"
  exit 0
fi

# The isLoopback expression changed across dsh releases (0.1.1: pageLocation ===
# void 0 || ...; 0.1.5: transport?.ownsHost === true || pageLocation === void 0 || ...).
# Match the whole expression up to isLoopbackHostname(...) so both work.
if ! grep -q 'isLoopbackHostname(pageLocation.hostname),' "$TARGET"; then
  echo "[patch] FAILED: expected code not found (dsh layout changed?)"
  exit 1
fi

cp -n "$TARGET" "$TARGET.orig" 2>/dev/null || true

perl -0pi -e 's{isLoopback:[^\n]*?isLoopbackHostname\(pageLocation\.hostname\),}{isLoopback: true, /*[dsh-lan-patch]*/}' "$TARGET"

if grep -q 'dsh-lan-patch' "$TARGET"; then
  echo "[patch] applied: $TARGET"
else
  echo "[patch] FAILED: substitution did not take effect"
  exit 1
fi
