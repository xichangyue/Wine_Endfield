#!/bin/bash
set -euo pipefail
RES="${1:?resources}"; DEST="${2:?destination}"; EXE="${3:?official exe}"; MODES="${4:?modes}"
case "$MODES" in Vulkan|DirectX11|Vulkan,DirectX11) ;; *) echo '无效模式'; exit 1;; esac
[[ "$DEST" = /* && "$DEST" != / ]] || exit 1
[ -f "$EXE" ] || { echo '找不到官方安装器'; exit 1; }
/usr/bin/arch -x86_64 /usr/bin/true || { echo '请先按 macOS 提示安装 Rosetta 2'; exit 1; }
if [ -e "$DEST" ] && [ ! -f "$DEST/.endfield-installer-v1" ]; then
  echo '所选安装目录已存在且不是本安装器管理的目录。请选择新的目录，不会覆盖原文件。'; exit 1
fi
mkdir -p "$DEST"
touch "$DEST/.endfield-installer-v1"
mkdir "$DEST/.setup-lock" || { echo '另一个安装任务正在运行，或上次异常退出留下 .setup-lock。请确认任务已退出后再处理。'; exit 1; }
trap 'rmdir "$DEST/.setup-lock"' EXIT
mkdir -p "$DEST/logs" "$DEST/Apps" "$DEST/Game"
IFS=, read -r -a choices <<< "$MODES"
for mode in "${choices[@]}"; do
  echo "正在校验并安装 $mode 运行时……"
  case "$mode" in
    Vulkan) hash=a36e8723ceaa2a54336f179b71c2aa107e2c609d333b60a041823dff5400c2a1;;
    DirectX11) hash=550209a463e5a1b1e18f5b0b08286ce8749f74ddaf977f05b1f016a26b6531e1;;
  esac
  archive="$RES/Wine_Endfield-$mode-v0.1.0-experimental.tar.xz"
  [ "$(shasum -a 256 "$archive" | awk '{print $1}')" = "$hash" ] || { echo '安装器资源校验失败'; exit 1; }
  if [ ! -d "$DEST/$mode" ]; then
    stage="$(mktemp -d "$DEST/unpack.XXXXXX")"
    tar -xf "$archive" -C "$stage"
    mv "$stage/$mode" "$DEST/$mode"
    rmdir "$stage"
  fi
  (
    source "$DEST/$mode/common.sh"
    prepare
    link="$WINEPREFIX/drive_c/Endfield"
    if [ -L "$link" ]; then
      [ "$(readlink "$link")" = "$DEST/Game" ] || { echo '游戏映射与共享目录不一致，停止安装'; exit 1; }
    elif [ -e "$link" ]; then
      echo '游戏目录已存在，不会覆盖'; exit 1
    else ln -s "$DEST/Game" "$link"; fi
    "$WINE_ROOT/bin/wineserver" -w
  ) >> "$DEST/logs/setup-$mode.log" 2>&1 || { echo "$mode 配置失败，请查看 logs/setup-$mode.log"; exit 1; }
done
updater=Vulkan
[ ! -d "$DEST/DirectX11" ] || updater=DirectX11
echo '正在配置独立的官方启动器环境……'
(
  source "$DEST/$updater/common.sh"
  STATE="$DEST/Updater/local"; export WINEPREFIX="$STATE/prefix"
  mkdir -p "$STATE/logs"
  prepare
  link="$WINEPREFIX/drive_c/Endfield"
  if [ ! -e "$link" ] && [ ! -L "$link" ]; then ln -s "$DEST/Game" "$link"; fi
  "$WINE_ROOT/bin/wineserver" -w
) >> "$DEST/logs/setup-updater.log" 2>&1 || { echo '启动器环境配置失败，请查看 logs/setup-updater.log'; exit 1; }
if [ ! -f "$DEST/Launcher/Launcher.exe" ]; then
  echo '正在读取用户提供的官方安装器（不自动接受协议）……'
  seven="$DEST/$updater/bin/7zz"
  [ "$(shasum -a 256 "$seven" | awk '{print $1}')" = 74b0910e50ea44d9760a57fada2192cfd530ba8bffbe7b47c412a464b796cabf ] || exit 1
  stage="$(mktemp -d "$DEST/official.XXXXXX")"
  "$seven" x "$EXE" "-o$stage" '$0/1.5.0/*' -y > "$DEST/logs/extract.log" 2>&1
  payload="$stage/"'$0/1.5.0'
  [ -f "$payload/Launcher.exe" ] && [ -f "$payload/Games.exe" ] || { echo '安装包结构不支持：目前已验证官方 1.5.0 安装器'; exit 1; }
  mkdir -p "$DEST/Launcher"
  mv "$payload" "$DEST/Launcher/1.5.0"
  cp "$DEST/Launcher/1.5.0/Launcher.exe" "$DEST/Launcher/Launcher.exe"
fi
mkdir -p "$DEST/Launcher/games"
gameLink="$DEST/Launcher/games/Arknights Endfield"
if [ -L "$gameLink" ]; then
  [ "$(readlink "$gameLink")" = "$DEST/Game" ] || exit 1
elif [ -e "$gameLink" ]; then echo '启动器下载目录已有内容，不会覆盖'; exit 1
else ln -s "$DEST/Game" "$gameLink"; fi
cp "$RES/run.sh" "$DEST/run.sh"
for mode in Vulkan DirectX11 Update; do
  [ "$mode" = Update ] || [ -d "$DEST/$mode" ] || continue
  case "$mode" in Vulkan) name='终末地 Vulkan';; DirectX11) name='终末地 DX11';; Update) name='终末地 更新与修复';; esac
  app="$DEST/Apps/$name.app"
  mkdir -p "$app/Contents/MacOS"
  cp "$RES/../MacOS/EndfieldInstaller" "$app/Contents/MacOS/EndfieldInstaller"
  plist="$app/Contents/Info.plist"
  plutil -create xml1 "$plist"
  plutil -insert CFBundleExecutable -string EndfieldInstaller "$plist"
  plutil -insert CFBundleIdentifier -string "io.wineendfield.installed.$mode" "$plist"
  plutil -insert CFBundleName -string "$name" "$plist"
  plutil -insert CFBundlePackageType -string APPL "$plist"
  plutil -insert InstallRoot -string "$DEST" "$plist"
  plutil -insert LaunchMode -string "$mode" "$plist"
  codesign --force --sign - "$app"
done
echo '环境安装完成。游戏尚需在官方启动器中下载、解压和校验。'
