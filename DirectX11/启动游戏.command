#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source ./common.sh
trap 'echo "如遇错误，请保留终端输出；按回车关闭。"; read -r _' EXIT
check_idle
prepare
if [ ! -L "$WINEPREFIX/drive_c/Endfield" ]; then
  if find_installed Endfield.exe; then
    SELECTED="$(dirname "$FOUND")"
    echo "自动找到游戏：$SELECTED"
  else
    echo "首次使用请先通过“安装官方启动器.command”安装启动器并下载游戏。"
    select_path '已下载完成、包含 Endfield.exe 的游戏文件夹'
  fi
  [ -f "$SELECTED/Endfield.exe" ] || { echo "目录内没有 Endfield.exe"; exit 1; }
  [ ! -e "$WINEPREFIX/drive_c/Endfield" ] || { echo "C:\Endfield 已存在，请先手动检查。"; exit 1; }
  ln -s "$SELECTED" "$WINEPREFIX/drive_c/Endfield"
fi
[ -f "$WINEPREFIX/drive_c/Endfield/Endfield.exe" ] || { echo "游戏路径已失效，请重新配置 local/prefix/drive_c/Endfield 链接。"; exit 1; }
cd "$WINEPREFIX/drive_c/Endfield"
export WINEDLLOVERRIDES='d3d11,dxgi,winemetal=b'
export ENDFIELD_DXMT_DRAWABLE_COUNT=2
ARG=-force-d3d11
"$WINE_ROOT/bin/wine" 'C:\Endfield\Endfield.exe' "$ARG" > "$STATE/logs/game-$(date +%Y%m%d-%H%M%S).log" 2>&1
