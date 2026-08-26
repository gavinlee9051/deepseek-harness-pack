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

LAN_IP="$(ip -4 route get 1 2>/dev/null | awk '{print $7; exit}')"
echo
echo "Local:    https://127.0.0.1:${PROXY_PORT}   (self-signed cert: accept the warning)"
if [ -n "$LAN_IP" ]; then
  echo "LAN:      https://${LAN_IP}:${PROXY_PORT}   (other devices on your network)"
fi
echo
echo "To stop:  $SCRIPT_DIR/stop.sh"
