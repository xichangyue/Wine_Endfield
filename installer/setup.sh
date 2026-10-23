#!/bin/bash
set -euo pipefail
RES="${1:?resources}"; DEST="${2:?destination}"; EXE="${3:-}"
RES="$(cd "$RES" && pwd -P)"
source "$RES/common.sh"
stage='检查系统与安装位置'; detail_log=''
report_failure() {
  local result="$1"
  [ "$result" != 0 ] || return 0
  printf '\n安装失败阶段：%s（退出码 %s）\n' "$stage" "$result" >&2
  if [ -n "$detail_log" ] && [ -f "$detail_log" ]; then
    printf '详细日志：%s\n' "$detail_log" >&2
    /usr/bin/tail -n 25 "$detail_log" >&2 || true
  fi
  echo '安装诊断结束。' >&2
}
trap 'report_failure "$?"' EXIT
printf '系统信息：macOS %s；架构 %s\n' "$(/usr/bin/sw_vers -productVersion)" "$(/usr/bin/uname -m)"
assert_platform
validate_path "$DEST"
assert_idle
# Only empty folders or installations owned by our previous installers may be used.
if [ -e "$DEST" ]; then
  [ -d "$DEST" ] || fail '安装位置不是文件夹。'
  if [ ! -f "$DEST/.endfield-installer-v1" ]; then
    [ -z "$(/bin/ls -A "$DEST")" ] || fail '所选目录有其他文件且不是本安装器管理的安装。请选择空文件夹，或 v0.2/v0.3 安装器创建的原目录。'
  fi
fi
[ ! -L "$DEST/.endfield-installer-v1" ] || fail '安装标记不能是符号链接。'
if [ ! -f "$DEST/Launcher/Launcher.exe" ]; then
  [ -f "$EXE" ] || fail '新安装需要从官网下载的 Windows 官方启动器 EXE。'
fi
# The native helper uses the same flock file as v0.2/v0.3 applications.
if [ "${ENDFIELD_LOCK_HELD:-}" != 1 ]; then
  mkdir -p "$DEST"
  touch "$DEST/.endfield-installer-v1"
  DEST="$(cd "$DEST" && pwd -P)"
  exec "$RES/../MacOS/EndfieldInstaller" --with-lock "$DEST" "$RES/setup.sh" "$RES" "$DEST" "$EXE"
fi
DEST="$(cd "$DEST" && pwd -P)"
stage='检查安装目录与资源清单'
for name in Recovery State Game Launcher Updater Vulkan DirectX11 Apps logs .runtime-backups; do
  [ ! -L "$DEST/$name" ] || fail "受保护目录不能是符号链接：$name"
  [ ! -e "$DEST/$name" ] || [ -d "$DEST/$name" ] || fail "受保护目录不是文件夹：$name"
done
for name in run.sh common.sh payload-manifest.tsv; do
  [ ! -L "$DEST/$name" ] || fail "安装元数据不能是符号链接：$name"
done
[ ! -L "$DEST/Launcher/games" ] || fail '官方启动器 games 目录不能是符号链接。'
manifest="$RES/payload-manifest.tsv"
/usr/bin/awk -F '\t' '
  $1=="format" && NF==2 && $2=="2" {f++;next}
  $1=="version" && NF==2 && $2 ~ /^v[0-9][A-Za-z0-9._-]*$/ {v++;next}
  $1=="payload" && NF==4 && $2=="Recovery" && $4 ~ /^[0-9a-f]+$/ && length($4)==64 {p++;next}
  {bad=1} END {exit bad || f!=1 || v!=1 || p!=1}' "$manifest" || fail '安装资源清单无效。'
version="$(awk -F '\t' '$1=="version" {print $2}' "$manifest")"
printf '安装器版本：%s\n' "$version"
archive_name="$(awk -F '\t' '$1=="payload" {print $3}' "$manifest")"
archive_hash="$(awk -F '\t' '$1=="payload" {print $4}' "$manifest")"
[ "$archive_name" = "Wine_Endfield-Recovery-$version.tar.xz" ] || fail '资源文件名与版本不一致。'
archive="$RES/$archive_name"
[ -f "$archive" ] && [ "$(/usr/bin/shasum -a 256 "$archive" | awk '{print $1}')" = "$archive_hash" ] || fail '安装包资源校验失败，请重新获取完整安装器。'
/usr/bin/tar -tf "$archive" | /usr/bin/awk '
  /^\// || /(^|\/)\.\.(\/|$)/ {bad=1}
  $0!="Recovery" && $0!="Recovery/" && index($0,"Recovery/")!=1 {bad=1}
  /^Recovery\/(local|prefix|State|Game|Launcher)(\/|$)/ {bad=1}
  END {exit bad}' || fail '资源目录结构不正确。'
source_state=''
for state in "$DEST/State" "$DEST/Updater/local" "$DEST/DirectX11/local" "$DEST/Vulkan/local"; do
  if [ -f "$state/prefix/system.reg" ]; then
    [ ! -L "$state" ] && [ ! -L "$state/prefix" ] || fail '旧 Wine 环境不能是符号链接。'
    for part in drive_c drive_c/windows drive_c/windows/system32 dosdevices system.reg user.reg userdef.reg; do
      [ ! -L "$state/prefix/$part" ] || fail "旧 Wine 系统路径不能是符号链接：$part"
    done
    source_state="$state"; break
  fi
done
required_kb=$(( $(/usr/bin/stat -f %z "$archive") / 1024 * 4 + 1048576 ))
if [ -n "$source_state" ]; then required_kb=$(( required_kb + $(/usr/bin/du -sk "$source_state" | awk '{print $1}') )); fi
free_kb="$(/bin/df -Pk "$DEST" | awk 'NR==2 {print $4}')"
[ "$free_kb" -ge "$required_kb" ] || fail "空间不足：安装及备份至少需要约 $(( (required_kb+1048575)/1048576 )) GB 可用空间；游戏资源另外由官方启动器检查。"
mkdir -p "$DEST/logs"
work="$(mktemp -d "$DEST/.setup-work.XXXXXX")"
mkdir "$work/new" "$work/backup"
touched=(); committed=0; launcher_link_changed=0; old_launcher_link=''; game_created=0; wine_started=0
cleanup() {
  local result=$? i name busy_status=0 cleanup_note=''
  trap - EXIT
  if [ "$committed" != 1 ] && [ "$result" = 0 ]; then result=1; fi
  report_failure "$result"
  if [ "$wine_started" = 1 ]; then
    wine_busy || busy_status=$?
    if [ "$busy_status" != 1 ]; then
      echo "Wine 尚未完全退出，保留准备目录供排查：${work}；未切换安装。请正常退出后重试。" >&2
      exit 1
    fi
  fi
  if [ "$committed" = 0 ]; then
    if [ "$launcher_link_changed" = 1 ]; then
      rm -f "$DEST/Launcher/games/Arknights Endfield"
      [ -z "$old_launcher_link" ] || ln -s "$old_launcher_link" "$DEST/Launcher/games/Arknights Endfield"
    fi
    for (( i=${#touched[@]}-1; i>=0; i-- )); do
      name="${touched[$i]}"
      rm -rf "$DEST/$name"
      [ ! -e "$work/backup/$name" ] && [ ! -L "$work/backup/$name" ] || mv "$work/backup/$name" "$DEST/$name"
    done
    [ "$game_created" != 1 ] || rmdir "$DEST/Game" 2>/dev/null || true
    echo '安装未完成，原有运行环境已保留或恢复；可在同一目录重试。' >&2
  elif [ -n "$(/bin/ls -A "$work/backup")" ]; then
    backup="$DEST/.runtime-backups/$(date +%Y%m%d-%H%M%S)-$$"
    if mkdir -p "$DEST/.runtime-backups" && touch "$work/backup/.endfield-backup-v1" && mv "$work/backup" "$backup"; then
      echo "已暂存待清理的旧版本：$backup"
    else
      cleanup_note="清理提醒：新环境已安装成功，旧版本暂存失败，已保留安装现场：$work"
    fi
  fi
  if [ "$committed" = 1 ] && [ "$result" = 0 ]; then
    if [ -z "$cleanup_note" ] && ! rm -rf "$work"; then
      cleanup_note="清理提醒：新环境已安装成功，安装临时目录未完全删除：$work"
    fi
    # Cleanup is deliberately after the commit and backup move. Its failure
    # must not roll back an otherwise valid installation.
    if ! /bin/bash "$RES/cleanup.sh" "$DEST" >"$DEST/logs/installer-cleanup.log" 2>&1; then
      echo '清理提醒：新环境已安装成功，旧版本清理或清理日志写入失败。'
      echo '清理提醒：新环境已安装成功，部分旧文件未能清理。详见 logs/installer-cleanup.log。' >>"$DEST/logs/installer-cleanup.log" || true
    fi
    if [ -n "$cleanup_note" ]; then
      echo "$cleanup_note"
      echo "$cleanup_note" >>"$DEST/logs/installer-cleanup.log" || true
    fi
    cat "$DEST/logs/installer-cleanup.log" || true
    echo "环境 $version 安装完成。请在官方启动器点击开始游戏；未勾选 DX11 使用 Vulkan，勾选使用 DX11。"
  else
    rm -rf "$work"
  fi
  exit "$result"
}
trap cleanup EXIT

stage='解压修复运行库'
echo "正在校验并准备修复运行库 ${version}……"
/usr/bin/tar -xf "$archive" -C "$work/new"
RECOVERY="$work/new/Recovery"
stage='校验修复运行库'; detail_log="$DEST/logs/installer-verify.log"
(verify_payload "$RECOVERY") >"$detail_log" 2>&1
stage='检查旧环境与游戏映射'; detail_log=''
[ -x "$RECOVERY/bin/7zz" ] || fail '缺少官方安装包解压工具。'
printf '%s %s\n' "$version" "$archive_hash" > "$RECOVERY/.payload-id"

# Remember only roots explicitly recorded by our old applications, so a moved
# v0.2/v0.3 installation can replace its own obsolete absolute game mapping.
old_roots=("$DEST")
for app in '终末地 Vulkan' '终末地 DX11' '终末地 更新与修复' '终末地'; do
  plist="$DEST/Apps/$app.app/Contents/Info.plist"
  if [ -f "$plist" ]; then
    id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
    case "$id" in io.wineendfield.installed.*)
      previous="$(/usr/libexec/PlistBuddy -c 'Print :InstallRoot' "$plist" 2>/dev/null || true)"
      [ -z "$previous" ] || old_roots+=("$previous");;
    *) fail "已有同名应用不属于本安装器，不会覆盖：$app";; esac
  fi
done
check_old_link() {
  local path="$1" kind="$2" target old
  if [ -L "$path" ]; then
    target="$(readlink "$path")"
    case "$kind:$target" in 'Game:../../../Game'|'Game:../../Game'|'Launcher:../../../Launcher') return 0;; esac
    for old in "${old_roots[@]}"; do [ "$target" != "$old/$kind" ] || return 0; done
    fail "已有映射指向其他位置，不会自动替换：$path → $target"
  elif [ -e "$path" ]; then
    fail "映射位置已有实体文件或目录，不会覆盖：$path"
  fi
}
check_old_link "$DEST/Launcher/games/Arknights Endfield" Game
if [ ! -d "$DEST/Game" ]; then mkdir "$DEST/Game"; game_created=1; fi
launcher="$DEST/Launcher"
if [ ! -f "$launcher/Launcher.exe" ]; then
  stage='提取官方启动器'
  echo '正在读取用户提供的官方启动器……'
  seven="$RECOVERY/bin/7zz"
  [ "$(/usr/bin/shasum -a 256 "$seven" | awk '{print $1}')" = 74b0910e50ea44d9760a57fada2192cfd530ba8bffbe7b47c412a464b796cabf ] || fail '7-Zip 资源校验失败。'
  mkdir "$work/official"
  detail_log="$DEST/logs/installer-extract.log"
  "$seven" x "$EXE" "-o$work/official" '$0/*' -y >"$detail_log" 2>&1
  detail_log=''
  payloads=()
  for item in "$work/official/\$0/"*; do
    [ ! -d "$item" ] || [ ! -f "$item/Launcher.exe" ] || [ ! -f "$item/Games.exe" ] || payloads+=("$item")
  done
  [ "${#payloads[@]}" = 1 ] || fail '官方安装包结构不支持：需要唯一包含 Launcher.exe 与 Games.exe 的版本目录。'
  official_version="$(basename "${payloads[0]}")"
  [[ "$official_version" =~ ^[0-9][A-Za-z0-9._-]*$ ]] || fail '官方版本目录无效。'
  mkdir "$work/new/Launcher"
  mv "${payloads[0]}" "$work/new/Launcher/$official_version"
  cp "$work/new/Launcher/$official_version/Launcher.exe" "$work/new/Launcher/Launcher.exe"
  printf '%s\n' "$official_version" >"$work/new/Launcher/.official-version"
  launcher="$work/new/Launcher"
fi

stage='准备 Wine 用户环境'; detail_log=''
echo '正在准备统一 Wine 环境；已有游戏和旧环境保持保留……'
if [ -n "$source_state" ]; then
  /usr/bin/ditto "$source_state" "$work/new/State"
else
  mkdir -p "$work/new/State/prefix"
fi
PREFIX="$work/new/State/prefix"
WINE_ROOT="$RECOVERY/runtime/Wine Devel.app/Contents/Resources/wine"
SESSION="$work/session"; mkdir -p "$SESSION/capture" "$PREFIX/drive_c"
mkdir -p "$PREFIX/dosdevices"
if [ -L "$PREFIX/dosdevices/c:" ]; then rm "$PREFIX/dosdevices/c:"
elif [ -e "$PREFIX/dosdevices/c:" ]; then fail 'Wine C: 映射位置已有实体目录。'; fi
ln -s '../drive_c' "$PREFIX/dosdevices/c:"
for pair in Endfield 'Hypergryph Launcher'; do
  kind=Game; [ "$pair" != 'Hypergryph Launcher' ] || kind=Launcher
  check_old_link "$PREFIX/drive_c/$pair" "$kind"
  [ ! -L "$PREFIX/drive_c/$pair" ] || rm "$PREFIX/drive_c/$pair"
done
ln -s "$DEST/Game" "$PREFIX/drive_c/Endfield"
ln -s "$launcher" "$PREFIX/drive_c/Hypergryph Launcher"
load_environment
stage='初始化 Wine 环境'; detail_log="$DEST/logs/installer-prefix.log"
: >"$detail_log"
wine_started=1
# These optional .NET/HTML add-ons are not needed by the Qt launcher or Unity.
# Suppress their interactive first-prefix downloads only during initialization;
# run.sh still loads the exact frozen game profile without these overrides.
WINEDLLOVERRIDES="$WINEDLLOVERRIDES;mscoree,mshtml=" "$WINE_ROOT/bin/wine" wineboot.exe -u >>"$DEST/logs/installer-prefix.log" 2>&1
"$WINE_ROOT/bin/wineserver" -w >>"$DEST/logs/installer-prefix.log" 2>&1
# These builtin PE files must match the frozen Unix side, including on upgrades.
stage='配对 Wine 系统组件'; detail_log=''
mkdir -p "$PREFIX/drive_c/windows/system32"
for dll in ntoskrnl.exe d3d11.dll dxgi.dll winemetal.dll; do
  rm -f "$PREFIX/drive_c/windows/system32/$dll"
  cp "$WINE_ROOT/lib/wine/x86_64-windows/$dll" "$PREFIX/drive_c/windows/system32/$dll"
done
stage='配置 Wine 字体'; detail_log="$DEST/logs/installer-prefix.log"
"$WINE_ROOT/bin/wine" reg.exe import "$RECOVERY/fonts.reg" >>"$DEST/logs/installer-prefix.log" 2>&1
"$WINE_ROOT/bin/wineserver" -w >>"$DEST/logs/installer-prefix.log" 2>&1
# Official Chinese launcher protocol, using a stable Windows path on every disk.
cat >"$work/launcher-protocol.reg" <<'REG'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\Software\Classes\hypergryphlauncher-abYeZZ16BPluCFyT]
@="URL:Hypergryph Launcher"
"URL Protocol"=""
[HKEY_LOCAL_MACHINE\Software\Classes\hypergryphlauncher-abYeZZ16BPluCFyT\DefaultIcon]
@="\"C:\\Hypergryph Launcher\\Launcher.exe\",0"
[HKEY_LOCAL_MACHINE\Software\Classes\hypergryphlauncher-abYeZZ16BPluCFyT\shell\open\command]
@="\"C:\\Hypergryph Launcher\\Launcher.exe\" \"%1\""
REG
stage='注册官方启动器协议'
"$WINE_ROOT/bin/wine" reg.exe import "$work/launcher-protocol.reg" >>"$DEST/logs/installer-prefix.log" 2>&1
"$WINE_ROOT/bin/wineserver" -w >>"$DEST/logs/installer-prefix.log" 2>&1
assert_idle
wine_started=0
stage='核验 Wine 环境与相对路径'; detail_log=''
for dll in ntoskrnl.exe d3d11.dll dxgi.dll winemetal.dll; do
  /usr/bin/cmp -s "$WINE_ROOT/lib/wine/x86_64-windows/$dll" "$PREFIX/drive_c/windows/system32/$dll" || fail "Wine 环境配对失败：$dll"
done
rm "$PREFIX/drive_c/Endfield" "$PREFIX/drive_c/Hypergryph Launcher"
ln -s '../../../Game' "$PREFIX/drive_c/Endfield"
ln -s '../../../Launcher' "$PREFIX/drive_c/Hypergryph Launcher"
[ -L "$PREFIX/dosdevices/c:" ] || fail 'Wine C: 映射未创建。'
rm "$PREFIX/dosdevices/c:"
ln -s '../drive_c' "$PREFIX/dosdevices/c:"
# Preparation must not leave links into the disposable transaction directory.
while IFS= read -r -d '' link; do
  case "$(readlink "$link")" in "$work"/*) fail "Wine 环境留下临时路径映射：$link";; esac
done < <(/usr/bin/find "$work/new/State" -type l -print0)
printf '%s\n' "$version" >"$work/new/State/installed-version"

stage='创建与签名应用入口'
cp "$RES/run.sh" "$RES/common.sh" "$manifest" "$work/new/"
mkdir "$work/new/Apps"
[ ! -d "$DEST/Apps" ] || /usr/bin/ditto "$DEST/Apps" "$work/new/Apps"
app_names=('终末地')
for name in '终末地 Vulkan' '终末地 DX11' '终末地 更新与修复'; do
  [ ! -d "$DEST/Apps/$name.app" ] || app_names+=("$name")
done
for name in "${app_names[@]}"; do
  app="$work/new/Apps/$name.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  cp "$RES/../MacOS/EndfieldInstaller" "$app/Contents/MacOS/EndfieldInstaller"
  plist="$app/Contents/Info.plist"
  /usr/bin/plutil -create xml1 "$plist"
  /usr/bin/plutil -insert CFBundleExecutable -string EndfieldInstaller "$plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string io.wineendfield.installed.Launcher "$plist"
  /usr/bin/plutil -insert CFBundleName -string "$name" "$plist"
  /usr/bin/plutil -insert CFBundlePackageType -string APPL "$plist"
  /usr/bin/plutil -insert CFBundleShortVersionString -string "${version#v}" "$plist"
  /usr/bin/plutil -insert LSMinimumSystemVersion -string 26.0 "$plist"
  /usr/bin/plutil -insert InstallRoot -string "$DEST" "$plist"
  /usr/bin/plutil -insert LaunchMode -string Launcher "$plist"
  /usr/bin/codesign --force --sign - "$app"
  /usr/bin/codesign --verify --strict "$app"
done

assert_idle
# Commit only after all extraction, Wine initialization and signing succeeded.
stage='切换到新版本'
for name in Recovery State run.sh common.sh payload-manifest.tsv Apps Launcher; do
  [ -e "$work/new/$name" ] || continue
  if [ -e "$DEST/$name" ]; then mv "$DEST/$name" "$work/backup/$name"; fi
  touched+=("$name")
  mv "$work/new/$name" "$DEST/$name"
done
mkdir -p "$DEST/Launcher/games"
if [ -L "$DEST/Launcher/games/Arknights Endfield" ]; then
  old_launcher_link="$(readlink "$DEST/Launcher/games/Arknights Endfield")"
  rm "$DEST/Launcher/games/Arknights Endfield"
fi
launcher_link_changed=1
ln -s '../../Game' "$DEST/Launcher/games/Arknights Endfield"
INSTALL_ROOT="$DEST"; RECOVERY="$DEST/Recovery"; PREFIX="$DEST/State/prefix"
WINE_ROOT="$RECOVERY/runtime/Wine Devel.app/Contents/Resources/wine"
stage='验证安装结果'
verify_installation
committed=1
echo "环境 $version 已完成配置与校验，正在自动清理旧版本残留……"
