#!/bin/bash
set -euo pipefail
# Match the tested profile rather than inheriting graphics/debug overrides.
for profile_option in ${!ENDFIELD_@} ${!MVK_CONFIG_@} ${!MTL_@} ${!WINE@} ${!DXMT_@} ${!QT_@} ${!QSG_@} ${!QML@} ${!DYLD_@} ${!VK_@} ${!VULKAN_@} ${!MOLTENVK_@}; do
  unset "$profile_option"
done
unset profile_option
if [ "$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)" -lt 26 ]; then
  echo '此预编译运行时需要 macOS 26 或更新版本。' >&2; exit 1
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="$(basename "$ROOT")"
STATE="$ROOT/local"
WINE_ROOT="$ROOT/runtime/Wine Devel.app/Contents/Resources/wine"
if [ ! -d "$ROOT/runtime" ]; then WINE_ROOT="$STATE/runtime/Wine Devel.app/Contents/Resources/wine"; fi
export WINEPREFIX="$STATE/prefix"
export WINEMSYNC=1 WINEDEBUG=-all,err+all
export MTL_DEBUG_LAYER=0 MTL_SHADER_VALIDATION=0
unset DXMT_CONFIG DXMT_CONFIG_FILE DXMT_METALFX_SPATIAL_SWAPCHAIN
unset QT_QUICK_BACKEND QT_OPENGL QTWEBENGINE_CHROMIUM_FLAGS
unset ENDFIELD_FRAME_STATS ENDFIELD_METAL_DIAGNOSTICS
mkdir -p "$STATE/downloads" "$STATE/logs"
fetch() {
  local name="$1" hash="$2" url="$3"
  local dest="$STATE/downloads/$name"
  if [ ! -f "$dest" ]; then
    curl --fail --location --retry 3 --proto '=https' "$url" -o "$dest.part"
    mv "$dest.part" "$dest"
  fi
  if [ "$(shasum -a 256 "$dest" | awk '{print $1}')" != "$hash" ]; then
    echo "下载校验失败：$dest。请移走该文件后重试。" >&2; exit 1
  fi
}
prepare() {
  [ -f "$STATE/ready-v1" ] && return
  if [ ! -d "$ROOT/runtime" ]; then
    echo '请下载同版本 Release 的完整运行时包；Git 源码 ZIP 不含二进制。' >&2; exit 1
  fi
  /usr/bin/arch -x86_64 /usr/bin/true || { echo '需要安装 Apple Rosetta 2。'; exit 1; }
  (cd "$ROOT/runtime" && shasum -a 256 -c ../RUNTIME-SHA256.txt)
  "$WINE_ROOT/bin/wineboot" -u
  # Ensure the extra DXMT builtin is visible to a newly-created prefix.
  if [ "$MODE" = DirectX11 ]; then
    cp "$WINE_ROOT/lib/wine/x86_64-windows/winemetal.dll" "$WINEPREFIX/drive_c/windows/system32/winemetal.dll"
  fi
  "$WINE_ROOT/bin/wine" reg import "$ROOT/fonts.reg"
  touch "$STATE/ready-v1"
}
check_idle() {
  local processes
  processes="$(/bin/ps -axo comm=)" || {
    echo 'Cannot verify Wine process state; refusing to launch.' >&2
    exit 2
  }
  if /usr/bin/grep -Eq '(^|/)(Endfield\.exe|wineserver|wineserver64)$|^C:\\Endfield\\Endfield\.exe$' <<< "$processes"; then
    echo 'Endfield or a Wine server is already running; refusing a second launch.' >&2
    exit 1
  fi
}

select_path() {
  local kind="$1" path
  echo "请粘贴$kind的完整路径，然后回车（不要添加引号或反斜杠转义）："
  IFS= read -r path
  [ -n "$path" ] || exit 1
  SELECTED="$path"
}
find_installed() {
  local name="$1" item
  local matches=()
  if [ "$name" = Launcher.exe ] && [ -f "$WINEPREFIX/drive_c/HypergryphLauncher/Launcher.exe" ]; then
    FOUND="$WINEPREFIX/drive_c/HypergryphLauncher/Launcher.exe"; return 0
  fi
  while IFS= read -r -d '' item; do matches+=("$item"); done < <(find "$WINEPREFIX/drive_c" -type f -iname "$name" -print0)
  if [ "${#matches[@]}" = 0 ] && [ "$name" = Endfield.exe ]; then
    local other=DirectX11
    [ "$MODE" != DirectX11 ] || other=Vulkan
    if [ -d "$ROOT/../$other/local/prefix/drive_c" ]; then
      while IFS= read -r -d '' item; do matches+=("$item"); done < <(find "$ROOT/../$other/local/prefix/drive_c" -type f -iname "$name" -print0)
    fi
  fi
  if [ "${#matches[@]}" = 1 ]; then FOUND="${matches[0]}"; return 0; fi
  return 1
}
launcher_environment() {
  if [ "$MODE" = DirectX11 ]; then
    export WINEDLLOVERRIDES='d3d11,dxgi,winemetal=b'
  else
    export WINEQT_QUICK_BACKEND=software
  fi
}

source "$ROOT/game-profile.sh"
