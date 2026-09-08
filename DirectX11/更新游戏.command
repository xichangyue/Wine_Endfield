#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source ./common.sh
trap 'echo "请从“启动游戏”入口游玩，不要使用官方启动器的开始游戏。按回车关闭。"; read -r _' EXIT
check_idle
prepare
if find_installed Launcher.exe; then
  SELECTED="$FOUND"
  echo "自动找到已安装的官方启动器：$SELECTED"
else
  echo "未找到已安装的启动器。首次使用请先运行“安装官方启动器.command”；已有安装可手动指定。"
  select_path '已安装的官方启动器 Launcher.exe（不是下载的安装器）'
fi
[ -f "$SELECTED" ] || { echo "找不到启动器文件"; exit 1; }
cd "$(dirname "$SELECTED")"
export WINEDLLOVERRIDES='d3d11,dxgi,winemetal=b'
"$WINE_ROOT/bin/wine" "$SELECTED" > "$STATE/logs/launcher-$(date +%Y%m%d-%H%M%S).log" 2>&1
