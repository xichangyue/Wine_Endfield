#!/bin/bash
set -euo pipefail
INSTALL_ROOT="$(cd "$(dirname "$0")" && pwd)"
action="${1:?mode}"
case "$action" in Vulkan|DirectX11) selected="$action";; Update)
  selected=Vulkan; [ ! -d "$INSTALL_ROOT/DirectX11" ] || selected=DirectX11;; *) exit 1;; esac
source "$INSTALL_ROOT/$selected/common.sh"
check_idle
if [ "$action" = Update ]; then
  STATE="$INSTALL_ROOT/Updater/local"; export WINEPREFIX="$STATE/prefix"
  launcher_environment
  cd "$INSTALL_ROOT/Launcher"
  "$WINE_ROOT/bin/wine" ./Launcher.exe
else
  [ "$(readlink "$INSTALL_ROOT/Launcher/games/Arknights Endfield")" = "$INSTALL_ROOT/Game" ] || {
    echo '官方安装目录映射已变化。请检查共享目录，不会启动可能过期的另一份游戏。'; exit 2;
  }
  [ -f "$INSTALL_ROOT/Game/Endfield.exe" ] && [ -d "$INSTALL_ROOT/Game/Endfield_Data" ] || {
    echo '游戏尚未下载完成，或安装路径发生变化。请先打开“更新与修复”，在默认目录下载并完成官方校验。'; exit 2;
  }
  cd "$WINEPREFIX/drive_c/Endfield"
  if [ "$action" = Vulkan ]; then
    export WINEDLLOVERRIDES='vulkan-1,winevulkan=b'
    export MVK_CONFIG_USE_MTLHEAP=0 MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1
    export MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION=0 MVK_CONFIG_PERFORMANCE_TRACKING=0
    unset MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS MVK_CONFIG_FAST_MATH_ENABLED
    flag=-force-vulkan
  else
    export WINEDLLOVERRIDES='d3d11,dxgi,winemetal=b' ENDFIELD_DXMT_DRAWABLE_COUNT=2
    flag=-force-d3d11
  fi
  "$WINE_ROOT/bin/wine" 'C:\Endfield\Endfield.exe' "$flag"
fi
# Launcher.exe can return before Games.exe; retain the application lock until Wine finishes.
"$WINE_ROOT/bin/wineserver" -w
