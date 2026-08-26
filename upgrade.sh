#!/usr/bin/env bash
# upgrade.sh - One-click upgrade of @deepseek-ai/dsh, then restart.
# run.sh re-applies the LAN patch automatically on every start.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

if ! command -v node >/dev/null 2>&1; then
  echo "node not found; install Node.js first (see README)."
  exit 1
fi

echo "=== 当前版本 ==="
dsh --version 2>/dev/null || echo "(未安装?)"

echo "=== 升级 @deepseek-ai/dsh ==="
npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh

echo "=== 升级后版本 ==="
dsh --version

echo "=== 重启服务（自动重打局域网补丁）==="
"$SCRIPT_DIR/stop.sh" || true
sleep 1
setsid bash "$SCRIPT_DIR/start.sh" > "$SCRIPT_DIR/start.out" 2>&1 < /dev/null &
disown
sleep 8
cat "$SCRIPT_DIR/start.out"

echo "完成。如浏览器行为异常，请强制刷新页面(Ctrl+Shift+R)。"
