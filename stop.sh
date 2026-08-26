#!/usr/bin/env bash
# stop.sh - Stop the backgrounded DeepSeek Harness web UI and LAN proxy.
set -uo pipefail

FOUND=0
if pgrep -f "dsh web" >/dev/null 2>&1; then FOUND=1; fi
if pgrep -f "proxy.js" >/dev/null 2>&1; then FOUND=1; fi

if [ "$FOUND" -eq 1 ]; then
  echo "Stopping DeepSeek Harness (dsh) and proxy..."
  pkill -f "dsh web" || true
  pkill -f "proxy.js" || true
  sleep 2
  pkill -9 -f "dsh web" || true
  pkill -9 -f "proxy.js" || true
  echo "Stopped."
else
  echo "No running instance found."
fi
