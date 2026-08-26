#!/usr/bin/env bash
# dsh.sh - DeepSeek Harness 统一管理入口
# 用法: ./dsh.sh            -> 交互式菜单
#       ./dsh.sh <command>  -> 直接执行: start|stop|restart|status|log|upgrade
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

LOG="$DEPLOY_DIR/dsh.log"
PROXY_PORT="${PROXY_PORT:-3080}"

lan_ip() { ip -4 route get 1 2>/dev/null | awk '{print $7; exit}'; }

do_start()    { setsid bash "$SCRIPT_DIR/start.sh" > "$DEPLOY_DIR/start.out" 2>&1 < /dev/null & disown; sleep 8; cat "$DEPLOY_DIR/start.out"; }
do_stop()     { "$SCRIPT_DIR/stop.sh"; }
do_restart()  { do_stop; sleep 1; echo; do_start; }

do_status() {
  echo "=== 进程 ==="
  pgrep -af "dsh web" | grep -v grep || echo "dsh: 未运行"
  pgrep -af "proxy.js" | grep -v grep || echo "proxy: 未运行"
  echo
  local ip; ip="$(lan_ip)"
  if pgrep -f "proxy.js" >/dev/null 2>&1; then
    echo "=== 访问地址 ==="
    echo "本机:   https://127.0.0.1:${PROXY_PORT}"
    [ -n "$ip" ] && echo "局域网: https://${ip}:${PROXY_PORT}"
  fi
  echo
  echo "=== 版本 / 补丁 ==="
  dsh --version 2>/dev/null || echo "dsh 命令不可用"
  NODE_REAL="$(readlink -f "$(command -v node)")"
  PATCH_TARGET="$(dirname "$(dirname "$NODE_REAL")")/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/lib/client.js"
  grep -q 'isLoopback: true,' "$PATCH_TARGET" 2>/dev/null \
    && echo "LAN 补丁: 已应用" || echo "LAN 补丁: 未应用"
}

do_log()      { echo "(Ctrl+C 退出)"; tail -n 50 -f "$LOG"; }
do_upgrade()  { "$SCRIPT_DIR/upgrade.sh"; }

menu() {
  while true; do
    echo
    echo "======== DeepSeek Harness 管理台 ========"
    echo " 1) 启动        2) 停止        3) 重启"
    echo " 4) 状态        5) 查看日志    6) 升级"
    echo " 0) 退出"
    read -r -p "请选择: " c
    case "$c" in
      1) do_start ;;
      2) do_stop ;;
      3) do_restart ;;
      4) do_status ;;
      5) do_log ;;
      6) do_upgrade ;;
      0) exit 0 ;;
      *) echo "无效选择" ;;
    esac
  done
}

case "${1:-}" in
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_restart ;;
  status)  do_status ;;
  log)     do_log ;;
  upgrade) do_upgrade ;;
  "")      menu ;;
  *) echo "用法: $0 [start|stop|restart|status|log|upgrade]"; exit 1 ;;
esac
