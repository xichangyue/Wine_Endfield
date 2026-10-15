#!/bin/bash
set -euo pipefail
RES="${1:?resources}"; DEST="${2:?destination}"; EXE="${3:?official exe}"; MODES="${4:?modes}"
fail() { echo "$*" >&2; exit 1; }
case "$MODES" in Vulkan|DirectX11|Vulkan,DirectX11) ;; *) fail '无效模式';; esac
[[ "$DEST" = /* && "$DEST" != / && "$DEST" != *$'\n'* ]] || fail '安装目录无效'
[ ! -L "$DEST" ] || fail '安装目录不能是符号链接'
[ -f "$EXE" ] || fail '找不到官方安装器'
major="$(/usr/bin/sw_vers -productVersion | cut -d. -f1)"
[[ "$major" =~ ^[0-9]+$ ]] && [ "$major" -ge 26 ] || fail '此预编译运行时需要 macOS 26 或更新版本。'
/usr/bin/arch -x86_64 /usr/bin/true || fail '请先按 macOS 提示安装 Rosetta 2'
assert_idle() {
  local process_snapshot current_uid busy
  current_uid="$(/usr/bin/id -u)" || fail '无法确认当前用户，停止安装。'
  process_snapshot="$(/bin/ps -axo uid=,comm=)" || fail '无法读取进程列表，停止安装。'
  [ -n "$process_snapshot" ] || fail '进程列表为空，停止安装。'
  busy="$(/usr/bin/awk -v uid="$current_uid" '
    $1 == uid { $1=""; sub(/^ +/, ""); n=$0; sub(/^.*\//, "", n)
      if (n ~ /^(wine|wine64|wine-preloader|wine64-preloader|wineserver|wineboot)(-.*)?$/ ||
          n ~ /(^|\\)(Endfield|Launcher|Games|PlatformProcess|QtWebEngineProcess)\.exe$/) found=1 }
    END { print found+0 }' <<< "$process_snapshot")" || fail '无法核验运行中的进程，停止安装。'
  case "$busy" in
    0) ;;
    1) fail '请先退出游戏、网页、官方启动器及其他 Wine 任务，再安装或升级。';;
    *) fail '进程检查返回无效结果，停止安装。';;
  esac
}
assert_idle
manifest="$RES/payload-manifest.tsv"
[ -f "$manifest" ] || fail '缺少资源清单'
awk -F '\t' '
  $1 == "format" && NF == 2 && $2 == "1" { f++; next }
  $1 == "version" && NF == 2 && $2 ~ /^v[0-9][A-Za-z0-9._-]*$/ { v++; next }
  $1 == "payload" && NF == 4 && ($2 == "Vulkan" || $2 == "DirectX11") && $4 ~ /^[0-9a-f]+$/ && length($4) == 64 { p[$2]++; next }
  { bad=1 }
  END { exit bad || f != 1 || v != 1 || p["Vulkan"] != 1 || p["DirectX11"] != 1 }' "$manifest" || fail '资源清单格式无效'
version="$(awk -F '\t' '$1 == "version" {print $2}' "$manifest")"
if [ -e "$DEST" ] && [ ! -f "$DEST/.endfield-installer-v1" ]; then
  fail '所选安装目录已存在且不是本安装器管理的目录。请选择新的目录，不会覆盖原文件。'
fi
mkdir -p "$DEST"
touch "$DEST/.endfield-installer-v1"
mkdir "$DEST/.setup-lock" || fail '另一个安装任务正在运行，或上次异常退出留下 .setup-lock。请确认任务已退出后再处理。'
work=""; installed=(); metadataTouched=(); committed=0
cleanup() {
  local result=$? mode i
  trap - EXIT
  # macOS Bash 3.2 can report zero to EXIT after an unbound-variable error.
  if [ "$committed" != 1 ] && [ "$result" = 0 ]; then result=1; fi
  if [ "$committed" = 0 ] && [ -n "$work" ]; then
    for (( i=${#metadataTouched[@]}-1; i>=0; i-- )); do
      name="${metadataTouched[$i]}"
      rm -rf "$DEST/$name"
      if [ -e "$work/metadata-backup/$name" ] || [ -L "$work/metadata-backup/$name" ]; then
        mv "$work/metadata-backup/$name" "$DEST/$name"
      fi
    done
    for (( i=${#installed[@]}-1; i>=0; i-- )); do
      mode="${installed[$i]}"
      if [ -d "$work/backup/$mode" ]; then
        [ ! -d "$DEST/$mode/local" ] || mv "$DEST/$mode/local" "$work/backup/$mode/local"
        rm -rf "$DEST/$mode"
        mv "$work/backup/$mode" "$DEST/$mode"
      elif [ -d "$DEST/$mode" ]; then
        # A failed fresh install retains its prefix/cache for a retry.
        if [ -d "$DEST/$mode/local" ]; then
          mkdir -p "$work/retry/$mode"
          mv "$DEST/$mode/local" "$work/retry/$mode/local"
        fi
        rm -rf "$DEST/$mode"
        if [ -d "$work/retry/$mode" ]; then mv "$work/retry/$mode" "$DEST/$mode"; fi
      fi
    done
  fi
  # A successful upgrade keeps old runtime files, including unknown user additions.
  if [ "$committed" = 1 ] && [ -n "$work" ]; then
    for mode in Vulkan DirectX11; do
      if [ -d "$work/backup/$mode" ]; then
        mkdir -p "$DEST/.runtime-backups"
        backup="$DEST/.runtime-backups/$(date +%Y%m%d-%H%M%S)-$mode-$$"
        mv "$work/backup/$mode" "$backup"
        echo "旧运行时保留在：${backup}（用户 local 已保留在当前版本）"
      fi
    done
  fi
  [ -z "$work" ] || rm -rf "$work"
  rmdir "$DEST/.setup-lock" || true
  exit "$result"
}
trap cleanup EXIT
for name in logs Apps Game Launcher Updater Vulkan DirectX11 .runtime-backups; do
  [ ! -L "$DEST/$name" ] || fail "受保护目录不能是符号链接：$name"
  [ ! -e "$DEST/$name" ] || [ -d "$DEST/$name" ] || fail "受保护目录不是文件夹：$name"
done
mkdir -p "$DEST/logs" "$DEST/Apps" "$DEST/Game"
work="$(mktemp -d "$DEST/.setup-work.XXXXXX")"
mkdir "$work/backup"
IFS=, read -r -a choices <<< "$MODES"
# Validate and stage every selected payload before replacing any installed runtime.
for mode in "${choices[@]}"; do
  echo "正在校验 $mode $version 运行时……"
  name="$(awk -F '\t' -v m="$mode" '$1 == "payload" && $2 == m {print $3}' "$manifest")"
  hash="$(awk -F '\t' -v m="$mode" '$1 == "payload" && $2 == m {print $4}' "$manifest")"
  [ "$name" = "Wine_Endfield-$mode-$version.tar.xz" ] || fail '资源文件名与版本不一致'
  archive="$RES/$name"
  [ -f "$archive" ] && [ "$(shasum -a 256 "$archive" | awk '{print $1}')" = "$hash" ] || fail '安装器资源校验失败'
  /usr/bin/tar -tf "$archive" | awk -v mode="$mode" '
    /^\// || /(^|\/)\.\.(\/|$)/ { bad=1 }
    $0 != mode && $0 != mode "/" && index($0, mode "/") != 1 { bad=1 }
    $0 ~ ("^" mode "/local(/|$)") { bad=1 }
    END { exit bad }' || fail '资源包含无效目录'
  mkdir "$work/$mode"
  /usr/bin/tar -xf "$archive" -C "$work/$mode"
  staged="$work/$mode/$mode"
  [ -f "$staged/common.sh" ] && [ -d "$staged/runtime" ] && [ -f "$staged/RUNTIME-SHA256.txt" ] && [ -x "$staged/bin/7zz" ] || fail '运行时资源不完整'
  [ ! -L "$staged/common.sh" ] && [ ! -L "$staged/runtime" ] && [ ! -L "$staged/RUNTIME-SHA256.txt" ] || fail '运行时核心资源不能是符号链接'
  if [ "$mode" = Vulkan ]; then
    [ -f "$staged/game-profile.sh" ] && [ ! -L "$staged/game-profile.sh" ] || fail '缺少 Vulkan 游戏配置'
  fi
  [ ! -e "$staged/local" ] && [ ! -L "$staged/local" ] || fail '运行时不能携带用户环境'
  (cd "$staged/runtime" && shasum -a 256 -c ../RUNTIME-SHA256.txt) > "$DEST/logs/verify-$mode.log" 2>&1 || fail "$mode 运行时内部校验失败，请查看 logs/verify-$mode.log"
  if [ -d "$DEST/$mode" ]; then
    [ ! -L "$DEST/$mode/local" ] || fail "$mode/local 不能是符号链接"
    [ ! -e "$DEST/$mode/local" ] || [ -d "$DEST/$mode/local" ] || fail "$mode/local 不是文件夹"
  fi
done
assert_idle
for mode in "${choices[@]}"; do
  hash="$(awk -F '\t' -v m="$mode" '$1 == "payload" && $2 == m {print $4}' "$manifest")"
  if [ -f "$DEST/$mode/.payload-id" ] && [ "$(cat "$DEST/$mode/.payload-id")" = "$version $hash" ]; then
    echo "$mode 运行时已是当前版本，将保留环境。"; continue
  fi
  echo "正在安装 $mode ${version}（保留 local 环境与缓存）……"
  if [ -d "$DEST/$mode" ]; then mv "$DEST/$mode" "$work/backup/$mode"; fi
  installed+=("$mode")
  mv "$work/$mode/$mode" "$DEST/$mode"
  if [ -d "$work/backup/$mode/local" ]; then mv "$work/backup/$mode/local" "$DEST/$mode/local"; fi
  printf '%s %s\n' "$version" "$hash" > "$DEST/$mode/.payload-id"
done
for mode in "${choices[@]}"; do
  # Do not put this subshell in an `if`/`||` condition: that would disable
  # errexit inside prepare(), allowing a failed wineboot to be marked ready.
  (
    source "$DEST/$mode/common.sh"
    prepare
    link="$WINEPREFIX/drive_c/Endfield"
    if [ -L "$link" ]; then
      [ "$(readlink "$link")" = "$DEST/Game" ] || fail '游戏映射与共享目录不一致，停止安装'
    elif [ -e "$link" ]; then fail '游戏目录已存在，不会覆盖'
    else ln -s "$DEST/Game" "$link"; fi
    "$WINE_ROOT/bin/wineserver" -w
  ) >> "$DEST/logs/setup-$mode.log" 2>&1
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
  if [ -L "$link" ]; then
    [ "$(readlink "$link")" = "$DEST/Game" ] || fail '启动器游戏映射不一致'
  elif [ -e "$link" ]; then fail '启动器游戏目录已存在，不会覆盖'
  else ln -s "$DEST/Game" "$link"; fi
  "$WINE_ROOT/bin/wineserver" -w
) >> "$DEST/logs/setup-updater.log" 2>&1
if [ ! -f "$DEST/Launcher/Launcher.exe" ]; then
  echo '正在读取用户提供的官方安装器（不自动接受协议）……'
  seven="$DEST/$updater/bin/7zz"
  [ "$(shasum -a 256 "$seven" | awk '{print $1}')" = 74b0910e50ea44d9760a57fada2192cfd530ba8bffbe7b47c412a464b796cabf ] || fail '7-Zip 资源校验失败'
  officialStage="$work/official"; mkdir "$officialStage"
  "$seven" x "$EXE" "-o$officialStage" '$0/*' -y > "$DEST/logs/extract.log" 2>&1
  payloads=()
  if [ -d "$officialStage/\$0" ]; then
    for item in "$officialStage/\$0/"*; do
      if [ -d "$item" ] && [ -f "$item/Launcher.exe" ] && [ -f "$item/Games.exe" ]; then payloads+=("$item"); fi
    done
  fi
  [ "${#payloads[@]}" = 1 ] || fail '安装包结构不支持：需要唯一包含 Launcher.exe 与 Games.exe 的官方版本目录'
  payload="${payloads[0]}"; officialVersion="$(basename "$payload")"
  [[ "$officialVersion" =~ ^[0-9][A-Za-z0-9._-]*$ ]] || fail '官方安装包版本目录无效'
  mkdir -p "$DEST/Launcher"
  [ ! -e "$DEST/Launcher/$officialVersion" ] || fail '官方启动器版本目录已有内容，不会覆盖'
  mv "$payload" "$DEST/Launcher/$officialVersion"
  cp "$DEST/Launcher/$officialVersion/Launcher.exe" "$DEST/Launcher/Launcher.exe"
  printf '%s\n' "$officialVersion" > "$DEST/Launcher/.official-version"
fi
mkdir -p "$DEST/Launcher/games"
gameLink="$DEST/Launcher/games/Arknights Endfield"
if [ -L "$gameLink" ]; then
  [ "$(readlink "$gameLink")" = "$DEST/Game" ] || fail '启动器下载映射与共享目录不一致'
elif [ -e "$gameLink" ]; then fail '启动器下载目录已有内容，不会覆盖'
else ln -s "$DEST/Game" "$gameLink"; fi
mkdir "$work/new-metadata" "$work/metadata-backup"
cp "$RES/run.sh" "$work/new-metadata/run.sh"
cp "$manifest" "$work/new-metadata/payload-manifest.tsv"
mkdir "$work/new-metadata/Apps"
cp -R "$DEST/Apps/." "$work/new-metadata/Apps/"
for mode in Vulkan DirectX11 Update; do
  [ "$mode" = Update ] || [ -d "$DEST/$mode" ] || continue
  case "$mode" in Vulkan) name='终末地 Vulkan';; DirectX11) name='终末地 DX11';; Update) name='终末地 更新与修复';; esac
  app="$work/new-metadata/Apps/$name.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  cp "$RES/../MacOS/EndfieldInstaller" "$app/Contents/MacOS/EndfieldInstaller"
  plist="$app/Contents/Info.plist"
  rm -f "$plist"
  plutil -create xml1 "$plist"
  plutil -insert CFBundleExecutable -string EndfieldInstaller "$plist"
  plutil -insert CFBundleIdentifier -string "io.wineendfield.installed.$mode" "$plist"
  plutil -insert CFBundleName -string "$name" "$plist"
  plutil -insert CFBundlePackageType -string APPL "$plist"
  plutil -insert CFBundleShortVersionString -string "${version#v}" "$plist"
  plutil -insert LSMinimumSystemVersion -string 26.0 "$plist"
  plutil -insert InstallRoot -string "$DEST" "$plist"
  plutil -insert LaunchMode -string "$mode" "$plist"
  codesign --force --sign - "$app"
  codesign --verify --strict "$app"
done
for name in Apps run.sh payload-manifest.tsv; do
  if [ -e "$DEST/$name" ] || [ -L "$DEST/$name" ]; then mv "$DEST/$name" "$work/metadata-backup/$name"; fi
  metadataTouched+=("$name")
  mv "$work/new-metadata/$name" "$DEST/$name"
done
committed=1
echo "环境 $version 安装完成。游戏尚需在官方启动器中下载、解压和校验。"
