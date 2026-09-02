#!/usr/bin/env bash
# run.sh - Foreground launcher. Starts dsh (localhost only) then the LAN proxy.
# Suitable for systemd (ExecStart) and for start.sh (which backgrounds it).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

cd "$DEPLOY_DIR"

DSH_PORT="${DSH_PORT:-3081}"     # dsh internal port (localhost only)
PROXY_PORT="${PROXY_PORT:-3080}" # public LAN port served by the proxy

# dsh refuses 0.0.0.0 for safety, so it binds localhost. The proxy exposes it.
HOSTNAME_FQDN="$(hostname)"

# Trust both the internal authority (Host after proxy rewrite) and the public
# authorities (the Origin browsers send: LAN IP / hostname / localhost on the
# PUBLIC proxy port). Without the public ones dsh's browser-trust fence
# rejects /api calls with HTTP 403.
TRUSTED="127.0.0.1:${DSH_PORT} localhost:${DSH_PORT} ${HOSTNAME_FQDN}:${DSH_PORT}"
TRUSTED="$TRUSTED 127.0.0.1:${PROXY_PORT} localhost:${PROXY_PORT} ${HOSTNAME_FQDN}:${PROXY_PORT}"
LAN_IP="$(ip -4 route get 1 2>/dev/null | awk '{print $7; exit}')"
if [ -n "$LAN_IP" ]; then
  TRUSTED="$TRUSTED ${LAN_IP}:${DSH_PORT} ${LAN_IP}:${PROXY_PORT}"
fi

echo "[run] applying LAN feature patch..."
"$SCRIPT_DIR/patch-lan.sh" || echo "[run] WARNING: LAN patch failed, continuing"

echo "[run] applying archive feature patch..."
"$SCRIPT_DIR/patch-archive.sh" || echo "[run] WARNING: archive patch failed, continuing"

echo "[run] starting dsh web on 127.0.0.1:${DSH_PORT} ..."
dsh web \
  --host 127.0.0.1 \
  --port "$DSH_PORT" \
  --no-open \
  --trusted-host $TRUSTED &
DSH_PID=$!

# Wait for dsh to be ready.
for i in $(seq 1 30); do
  if node -e "require('net').connect(${DSH_PORT},'127.0.0.1').on('connect',p=>process.exit(0)).on('error',p=>process.exit(1))" 2>/dev/null; then
    break
  fi
  sleep 1
done

echo "[run] ensuring TLS cert for LAN proxy..."
"$SCRIPT_DIR/gen-cert.sh"

echo "[run] starting LAN proxy (HTTPS) on 0.0.0.0:${PROXY_PORT} ..."
exec node "$SCRIPT_DIR/proxy.js"
