#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source ./common.sh
trap 'echo "请从“启动游戏”入口游玩，不要使用官方启动器的开始游戏。按回车关闭。"; read -r _' EXIT
check_idle
prepare
select_path '官方启动器 Launcher.exe'
[ -f "$SELECTED" ] || { echo "找不到启动器文件"; exit 1; }
cd "$(dirname "$SELECTED")"
export WINEDLLOVERRIDES='d3d11,dxgi,winemetal=b'
"$WINE_ROOT/bin/wine" "$SELECTED" > "$STATE/logs/launcher-$(date +%Y%m%d-%H%M%S).log" 2>&1
