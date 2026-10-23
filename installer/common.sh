#!/bin/bash
# Shared by the installer and the relocatable official-launcher entry.
fail() { echo "$*" >&2; exit 1; }
assert_platform() {
  [ "$(/usr/bin/uname -m)" = arm64 ] || fail '此运行库需要 Apple Silicon Mac。'
  local major
  major="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
  [[ "$major" =~ ^[0-9]+$ ]] && [ "$major" -ge 26 ] || fail '此运行库需要 macOS 26 或更新版本。'
  /usr/bin/arch -x86_64 /usr/bin/true || fail '请先按 macOS 提示安装 Rosetta 2。'
}
wine_busy() {
  local snapshot uid
  uid="$(/usr/bin/id -u)" || return 2
  snapshot="$(/bin/ps -ww -axo uid=,comm=)" || return 2
  [ -n "$snapshot" ] || return 2
  /usr/bin/awk -v uid="$uid" '
    $1 == uid { $1=""; sub(/^ +/, ""); n=$0; sub(/^.*\//, "", n); sub(/^.*\\/, "", n)
      if (n ~ /^(wine|wine64|wine-preloader|wine64-preloader|wineserver|wineboot)(-.*)?$/ || n ~ /\.[eE][xX][eE]$/) found=1 }
    END { exit found ? 0 : 1 }' <<< "$snapshot"
}
assert_idle() {
  local status=0
  wine_busy || status=$?
  case "$status" in
    1) ;;
    0) fail '请先正常退出游戏、官方启动器和其他 Wine 任务，再安装或启动。';;
    *) fail '无法核验 Wine 进程状态，已停止。';;
  esac
}
validate_path() {
  local path="$1" parent="$1" volume device info kind available
  [[ "$path" = /* && "$path" != / && "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]] || fail '请选择有效的完整安装路径。'
  [ ! -L "$path" ] || fail '安装目录本身不能是符号链接。'
  case "$path" in /Volumes/*)
    volume="${path#/Volumes/}"; volume="/Volumes/${volume%%/*}"
    /usr/sbin/diskutil info -plist "$volume" >/dev/null 2>&1 || fail '移动硬盘未挂载，请先连接并解锁磁盘。'
    ;;
  esac
  while [ ! -d "$parent" ]; do
    [ ! -e "$parent" ] || fail '安装路径的父级不是文件夹。'
    parent="$(dirname "$parent")"
  done
  device="$(/bin/df -Pk "$parent" | /usr/bin/awk 'NR==2 {print $1}')"
  info="$(/usr/sbin/diskutil info -plist "$device")" || fail '无法确认目标磁盘格式，请选择本地 APFS 或 Mac OS 扩展格式磁盘。'
  kind="$(/usr/bin/plutil -extract FilesystemType raw -o - - <<< "$info")" || fail '无法读取磁盘格式。'
  case "$kind" in apfs|hfs) ;; *) fail "目标磁盘格式为 ${kind}。Wine 环境需要 APFS 或 Mac OS 扩展格式；不支持直接安装到 exFAT、FAT 或 NTFS。不会格式化磁盘。";; esac
  [ "$(/usr/bin/plutil -extract WritableVolume raw -o - - <<< "$info")" = true ] || fail '目标磁盘为只读，请选择可写入的位置。'
  [ -w "$parent" ] || fail '没有安装目录的写入权限，请选择当前用户可写入的位置。'
}
load_environment() {
  local key
  # Match the frozen profile without inheriting experimental renderer overrides.
  for key in $(compgen -e); do
    case "$key" in WINE*|ENDFIELD_*|DYLD_*|MVK_*|MTL_*|VK_*|VULKAN_*|MOLTENVK_*|DXMT_*|QT_*|QTWEBENGINE_*|QSG_*|QML*|ROSETTA_*|LAB_COMBINED_*) unset "$key";; esac
  done
  source "$RECOVERY/environment.sh"
  export WINEPREFIX="$PREFIX" WINESERVER="$WINE_ROOT/bin/wineserver"
}
verify_payload() {
  local payload="$1"
  [ -d "$payload/runtime/Wine Devel.app/Contents/Resources/wine" ] || fail '缺少修复运行库。'
  for name in environment.sh CORE-SHA256.txt PROFILE-SHA256.txt RUNTIME-SHA256.txt fonts.reg; do
    [ -f "$payload/$name" ] && [ ! -L "$payload/$name" ] || fail "缺少运行配置：$name"
  done
  (cd "$payload" && /usr/bin/shasum -a 256 -c PROFILE-SHA256.txt) >/dev/null || fail '运行配置校验失败。'
  (cd "$payload/runtime" && /usr/bin/shasum -a 256 -c ../RUNTIME-SHA256.txt) >/dev/null || fail '运行库完整校验失败。'
}
verify_installation() {
  [ -f "$INSTALL_ROOT/.endfield-installer-v1" ] && [ ! -L "$INSTALL_ROOT/.endfield-installer-v1" ] || fail '这不是受管理的安装目录。'
  [ -f "$INSTALL_ROOT/Launcher/Launcher.exe" ] || fail '缺少官方启动器，请在原目录运行安装器修复。'
  [ -f "$PREFIX/system.reg" ] || fail 'Wine 环境尚未配置完成。'
  (cd "$RECOVERY" && /usr/bin/shasum -a 256 -c PROFILE-SHA256.txt) >/dev/null || fail '运行配置已变化，请重新安装修复。'
  (cd "$WINE_ROOT" && /usr/bin/shasum -a 256 -c "$RECOVERY/CORE-SHA256.txt") >/dev/null || fail '核心运行库校验失败，请重新安装修复。'
  local name
  for name in ntoskrnl.exe d3d11.dll dxgi.dll winemetal.dll; do
    /usr/bin/cmp -s "$WINE_ROOT/lib/wine/x86_64-windows/$name" "$PREFIX/drive_c/windows/system32/$name" || fail "环境组件不配套：${name}。请在原目录运行安装器修复。"
  done
  [ "$(readlink "$PREFIX/drive_c/Endfield")" = '../../../Game' ] && [ -d "$PREFIX/drive_c/Endfield" ] || fail '游戏映射已变化，请在原目录运行安装器修复。'
  [ "$(readlink "$PREFIX/drive_c/Hypergryph Launcher")" = '../../../Launcher' ] && [ -d "$PREFIX/drive_c/Hypergryph Launcher" ] || fail '启动器映射已变化。'
  [ "$(readlink "$INSTALL_ROOT/Launcher/games/Arknights Endfield")" = '../../Game' ] || fail '官方游戏下载位置已变化，请恢复默认目录或 C:\Endfield。'
  [ "$(readlink "$PREFIX/dosdevices/c:")" = '../drive_c' ] || fail 'Wine C: 映射已变化。'
}
