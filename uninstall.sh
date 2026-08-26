#!/usr/bin/env bash
# uninstall.sh - Stop the service and remove auto-start registrations.
# Does NOT uninstall dsh itself or delete your data/logs.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/stop.sh" || true

rm -f "$HOME/.config/autostart/dsh-harness.desktop" && echo "removed autostart entry"
rm -f "$HOME/.config/systemd/user/deepseek-harness.service" \
  && systemctl --user daemon-reload 2>/dev/null \
  && echo "removed systemd user service"

echo
echo "如需彻底清理，可手动执行:"
echo "  npm uninstall -g @deepseek-ai/dsh   # 卸载 dsh"
echo "  rm -rf $SCRIPT_DIR                  # 删除部署目录(含日志/证书)"
