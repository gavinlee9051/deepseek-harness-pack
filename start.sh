#!/usr/bin/env bash
# start.sh - One-click launcher. Backgrounds dsh + proxy and prints access URLs.
# Safe to run repeatedly: it stops any previous instance first.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

LOG="$DEPLOY_DIR/dsh.log"
DSH_PORT="${DSH_PORT:-3081}"
PROXY_PORT="${PROXY_PORT:-3080}"

# Stop any running instance.
if pgrep -f "dsh web" >/dev/null 2>&1 || pgrep -f "proxy.js" >/dev/null 2>&1; then
  echo "Stopping existing instance..."
  pkill -f "dsh web" || true
  pkill -f "proxy.js" || true
  sleep 2
fi

echo "Starting DeepSeek Harness (dsh) + LAN proxy..."
nohup "$SCRIPT_DIR/run.sh" >>"$LOG" 2>&1 &
echo "Launched (pid $!). Logs: $LOG"

# dsh 0.1.5+ prints a one-time auth URL (?token=...) to stdout. Surface it
# through the proxy so the browser can sign in from localhost or LAN.
TOKEN=""
for _ in $(seq 1 20); do
  TOKEN="$(grep -o 'token=[A-Za-z0-9_-]*' "$LOG" 2>/dev/null | tail -1 | cut -d= -f2)"
  [ -n "$TOKEN" ] && break
  sleep 0.5
done
SUFFIX="/"
[ -n "$TOKEN" ] && SUFFIX="/?token=$TOKEN"

LAN_IP="$(ip -4 route get 1 2>/dev/null | awk '{print $7; exit}')"
echo
echo "Local:    https://127.0.0.1:${PROXY_PORT}${SUFFIX}   (self-signed cert: accept the warning)"
if [ -n "$LAN_IP" ]; then
  echo "LAN:      https://${LAN_IP}:${PROXY_PORT}${SUFFIX}   (other devices on your network)"
fi
[ -n "$TOKEN" ] && echo "(open this URL once per start to sign in; the token rotates on restart)"
echo
echo "To stop:  $SCRIPT_DIR/stop.sh"
