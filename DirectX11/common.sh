#!/bin/bash
set -euo pipefail
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
  if [ ! -d "$ROOT/runtime" ] && [ ! -d "$ROOT/overlay" ]; then
    echo "缺少编译产物，请下载 GitHub Releases 中对应的安装包（源码 ZIP 不含二进制）。" >&2; exit 1
  fi
  /usr/bin/arch -x86_64 /usr/bin/true || { echo "需要安装 Apple Rosetta 2。"; exit 1; }
  if [ -d "$ROOT/runtime" ]; then
    (cd "$ROOT/runtime" && shasum -a 256 -c ../RUNTIME-SHA256.txt)
  else
  (cd "$ROOT/overlay" && shasum -a 256 -c ../OVERLAY-SHA256.txt)
  fetch wine.tar.xz 6f9af818b7af6001aeed7818cb32bf0155598c5ea4e3b33380a03cf814e033cd https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.16/wine-devel-11.16-osx64.tar.xz
  mkdir -p "$STATE/runtime"
  tar -xf "$STATE/downloads/wine.tar.xz" -C "$STATE/runtime"
  if [ "$MODE" = DirectX11 ]; then
    fetch dxmt.tar.gz 8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz
    mkdir -p "$STATE/dxmt"
    tar -xf "$STATE/downloads/dxmt.tar.gz" -C "$STATE/dxmt"
    for dll in d3d11.dll dxgi.dll winemetal.dll; do
      cp "$STATE/dxmt/v0.80/x86_64-windows/$dll" "$WINE_ROOT/lib/wine/x86_64-windows/$dll"
    done
    cp "$STATE/dxmt/v0.80/x86_64-unix/winemetal.so" "$WINE_ROOT/lib/wine/x86_64-unix/winemetal.so"
  else
    fetch moltenvk.tar f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-macos.tar
    mkdir -p "$STATE/moltenvk"
    tar -xf "$STATE/downloads/moltenvk.tar" -C "$STATE/moltenvk"
    cp "$STATE/moltenvk/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" "$WINE_ROOT/lib/libMoltenVK.dylib"
    codesign --force --sign - "$WINE_ROOT/lib/libMoltenVK.dylib"
  fi
  cp -R "$ROOT/overlay/." "$WINE_ROOT/"
  fi
  "$WINE_ROOT/bin/wineboot" -u
  # Ensure the extra DXMT builtin is visible to a newly-created prefix.
  if [ "$MODE" = DirectX11 ]; then
    cp "$WINE_ROOT/lib/wine/x86_64-windows/winemetal.dll" "$WINEPREFIX/drive_c/windows/system32/winemetal.dll"
  fi
  "$WINE_ROOT/bin/wine" reg add 'HKCU\Software\Wine\Fonts\Replacements' /v 'Microsoft YaHei' /t REG_MULTI_SZ /d 'Heiti SC' /f
  touch "$STATE/ready-v1"
}
check_idle() {
  if pgrep -f '^C:\\Endfield\\Endfield\.exe([[:space:]]|$)' >/dev/null; then
    echo "请先正常退出游戏，不能同时启动两个版本或在游戏运行时更新。" >&2; exit 1
  fi
}
select_path() {
  local kind="$1" path
  echo "请粘贴$kind的完整路径，然后回车（不要添加引号或反斜杠转义）："
  IFS= read -r path
  [ -n "$path" ] || exit 1
  SELECTED="$path"
}
