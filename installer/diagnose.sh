#!/bin/bash
# Read-only support bundle for ACE/runtime troubleshooting. This script never
# starts Wine and only writes the resulting bundle below INSTALL_ROOT/logs.
set -euo pipefail
umask 077

case "$#" in
  0) requested_root="$(dirname "$0")" ;;
  2) [ "$1" = --root ] || { echo '用法：diagnose.sh [--root 安装目录]' >&2; exit 2; }; requested_root="$2" ;;
  *) echo '用法：diagnose.sh [--root 安装目录]' >&2; exit 2 ;;
esac
[ -d "$requested_root" ] && [ ! -L "$requested_root" ] || { echo '安装目录不存在或是符号链接。' >&2; exit 1; }
INSTALL_ROOT_LOGICAL="$(cd "$requested_root" && pwd -L)"
INSTALL_ROOT="$(cd "$requested_root" && pwd -P)"
[ -f "$INSTALL_ROOT/.endfield-installer-v1" ] && [ ! -L "$INSTALL_ROOT/.endfield-installer-v1" ] || {
  echo '这不是受管理的终末地安装目录。' >&2
  exit 1
}
[ ! -L "$INSTALL_ROOT/logs" ] || { echo '日志目录不能是符号链接。' >&2; exit 1; }
mkdir -p "$INSTALL_ROOT/logs"

stamp="$(date +%Y%m%d-%H%M%S)"
name="support-${stamp}-$$"
work="$INSTALL_ROOT/logs/$name"
zip="$INSTALL_ROOT/logs/$name.zip"
[ ! -e "$work" ] && [ ! -e "$zip" ] || { echo '诊断包名称冲突，请重试。' >&2; exit 1; }
mkdir -m 700 "$work"
completed=0
cleanup() {
  rm -rf "$work"
  [ "$completed" = 1 ] || rm -f "$zip"
}
trap cleanup EXIT

# Replace fixed path substrings without treating them as regular expressions.
# The generic /Users rule also removes a user name if Wine formatted a host
# path differently from the current shell.
sanitize() {
  /usr/bin/awk -v root="$INSTALL_ROOT" -v logical_root="$INSTALL_ROOT_LOGICAL" -v home="${HOME:-}" '
    function replace_fixed(text, from, to,    at, out) {
      if (from == "") return text
      out = ""
      while ((at = index(text, from)) != 0) {
        out = out substr(text, 1, at - 1) to
        text = substr(text, at + length(from))
      }
      return out text
    }
    function redact_secrets(text,    lower, keys, count, i, at, first) {
      keys[++count] = "token=";          keys[++count] = "token:"
      keys[++count] = "\"token\"";      keys[++count] = " token "
      keys[++count] = "authorization=";  keys[++count] = "authorization:"
      keys[++count] = "cookie=";         keys[++count] = "cookie:"
      keys[++count] = "set-cookie";      keys[++count] = "password="
      keys[++count] = "password:";       keys[++count] = "passwd="
      keys[++count] = "secret=";         keys[++count] = "access_token"
      keys[++count] = "refresh_token";   keys[++count] = "sessionid="
      keys[++count] = "session_id="
      lower = tolower(text)
      first = 0
      for (i = 1; i <= count; ++i) {
        at = index(lower, keys[i])
        if (at && (!first || at < first)) first = at
      }
      if (first) return substr(text, 1, first - 1) "<SECRET_FIELDS_REDACTED>"
      return text
    }
    {
      line = replace_fixed($0, root, "<INSTALL_ROOT>")
      line = replace_fixed(line, logical_root, "<INSTALL_ROOT>")
      line = replace_fixed(line, home, "<HOME>")
      gsub(/\/Users\/[^\/[:space:]\"]+/, "<HOME>", line)
      gsub(/[Zz]:\\[Uu][Ss][Ee][Rr][Ss]\\[^\\[:space:]\"]+/, "<HOME>", line)
      gsub(/[Zz]:\/[Uu][Ss][Ee][Rr][Ss]\/[^\/[:space:]\"]+/, "<HOME>", line)
      gsub(/[Cc]:\\[Uu][Ss][Ee][Rr][Ss]\\[^\\[:space:]\"]+/, "<HOME>", line)
      gsub(/[Cc]:\/[Uu][Ss][Ee][Rr][Ss]\/[^\/[:space:]\"]+/, "<HOME>", line)
      print redact_secrets(line)
    }
  '
}

metadata_value() {
  local file="$1"
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    /usr/bin/head -n 1 "$file"
  else
    printf '%s\n' unavailable
  fi
}

{
  printf 'bundle_format=1\n'
  printf 'created_local=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf 'macos_version=%s\n' "$(/usr/bin/sw_vers -productVersion 2>/dev/null || echo unavailable)"
  printf 'macos_build=%s\n' "$(/usr/bin/sw_vers -buildVersion 2>/dev/null || echo unavailable)"
  printf 'kernel_release=%s\n' "$(/usr/bin/uname -r 2>/dev/null || echo unavailable)"
  printf 'architecture=%s\n' "$(/usr/bin/uname -m 2>/dev/null || echo unavailable)"
  printf 'hardware_model=%s\n' "$(/usr/sbin/sysctl -n hw.model 2>/dev/null || echo unavailable)"
  printf 'cpu_brand=%s\n' "$(/usr/sbin/sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unavailable)"
  printf 'memory_bytes=%s\n' "$(/usr/sbin/sysctl -n hw.memsize 2>/dev/null || echo unavailable)"
  printf 'logical_cpu=%s\n' "$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null || echo unavailable)"
  if /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    printf 'rosetta_x86_64=yes\n'
  else
    printf 'rosetta_x86_64=no\n'
  fi
  printf 'filesystem=%s\n' "$(/usr/bin/stat -f %T "$INSTALL_ROOT" 2>/dev/null || echo unavailable)"
} | sanitize >"$work/system.txt"

payload_version="$(/usr/bin/awk -F '\t' '$1=="version" {print $2; exit}' "$INSTALL_ROOT/payload-manifest.tsv" 2>/dev/null || true)"
{
  printf 'payload_version=%s\n' "${payload_version:-unavailable}"
  printf 'installed_version=%s\n' "$(metadata_value "$INSTALL_ROOT/State/installed-version")"
  printf 'migration_source=%s\n' "$(metadata_value "$INSTALL_ROOT/State/migration-source")"
  printf 'official_launcher_version=%s\n' "$(metadata_value "$INSTALL_ROOT/Launcher/.official-version")"
} | sanitize >"$work/installation.txt"

printf 'category\tsize\tsha256\tpath\n' >"$work/core-files.tsv"
record_file() {
  local category="$1" file="$2" relative size hash
  [ -f "$file" ] && [ ! -L "$file" ] || return 0
  relative="${file#"$INSTALL_ROOT"/}"
  case "$relative" in *$'\n'*|*$'\r'*|*$'\t'*) return 0;; esac
  size="$(/usr/bin/stat -f %z "$file")"
  hash="$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')"
  printf '%s\t%s\t%s\t%s\n' "$category" "$size" "$hash" "$relative"
}

wine="$INSTALL_ROOT/Recovery/runtime/Wine Devel.app/Contents/Resources/wine"
{
  record_file runtime "$wine/bin/wine"
  record_file runtime "$wine/bin/wineserver"
  record_file runtime "$wine/lib/libMoltenVK.dylib"
  record_file runtime "$wine/share/wine/wine.inf"
  for component in ntoskrnl.exe wineboot.exe kernel32.dll lsass.exe sechost.dll secur32.dll msv1_0.dll d3d11.dll dxgi.dll winemetal.dll; do
    record_file runtime "$wine/lib/wine/x86_64-windows/$component"
    record_file prefix "$INSTALL_ROOT/State/prefix/drive_c/windows/system32/$component"
  done
  record_file launcher-build "$INSTALL_ROOT/Launcher/Launcher.exe"
  record_file game-build "$INSTALL_ROOT/Game/Endfield.exe"
  record_file game-build "$INSTALL_ROOT/Game/EndfieldBase.dll"
  record_file game-build "$INSTALL_ROOT/Game/verify_files.json"
  for component in environment.sh CORE-SHA256.txt PROFILE-SHA256.txt RUNTIME-SHA256.txt version.json; do
    record_file recovery-profile "$INSTALL_ROOT/Recovery/$component"
  done
  record_file entry "$INSTALL_ROOT/run.sh"
  record_file entry "$INSTALL_ROOT/common.sh"
  record_file entry "$INSTALL_ROOT/diagnose.sh"
  record_file entry "$INSTALL_ROOT/payload-manifest.tsv"
} >>"$work/core-files.tsv"

printf 'category\tsize\tsha256\tpath\n' >"$work/ace-files.tsv"
record_ace_tree() {
  local category="$1" directory="$2" file
  [ -d "$directory" ] && [ ! -L "$directory" ] || return 0
  while IFS= read -r -d '' file; do record_file "$category" "$file"; done \
    < <(/usr/bin/find "$directory" -type f -print0)
}
{
  record_ace_tree game "$INSTALL_ROOT/Game/AntiCheatExpert"
  record_ace_tree prefix "$INSTALL_ROOT/State/prefix/drive_c/Program Files/AntiCheatExpert"
  drivers="$INSTALL_ROOT/State/prefix/drive_c/windows/system32/drivers"
  if [ -d "$drivers" ] && [ ! -L "$drivers" ]; then
    for file in "$drivers"/*; do
      [ -f "$file" ] && [ ! -L "$file" ] || continue
      case "$(basename "$file")" in
        [Aa][Cc][Ee]-*.[Ss][Yy][Ss]) record_file prefix-driver "$file";;
      esac
    done
  fi
} >>"$work/ace-files.tsv"
/usr/bin/head -n 1 "$work/ace-files.tsv" >"$work/ace-files.sorted"
/usr/bin/tail -n +2 "$work/ace-files.tsv" | LC_ALL=C /usr/bin/sort >>"$work/ace-files.sorted"
mv "$work/ace-files.sorted" "$work/ace-files.tsv"

registry="$INSTALL_ROOT/State/prefix/system.reg"
if [ -f "$registry" ] && [ ! -L "$registry" ]; then
  printf '%s\n' 'service_dynamic_status=not_collected_offline' >"$work/ace-services.txt"
  /usr/bin/awk '
    /^\[/ {
      lower = tolower($0)
      keep = (lower ~ /\\\\services\\\\(ace-|anticheatexpert|tace)/)
      if (keep) print $0
      next
    }
    keep && /^"(DisplayName|ImagePath|Type|Start|ErrorControl|DependOnService|Group)"=/ {
      line = $0
      if (line ~ /^"ImagePath"=/ && toupper(line) ~ /Z:/) line = "\"ImagePath\"=\"<HOST_PATH_REDACTED>\""
      print line
    }
    keep && /^"ObjectName"=/ {
      if (tolower($0) == "\"objectname\"=\"localsystem\"") print $0
      else print "\"ObjectName\"=\"<ACCOUNT_REDACTED>\""
    }
  ' "$registry" | sanitize >>"$work/ace-services.txt"
else
  printf '%s\n' 'service_dynamic_status=not_collected_offline' 'system.reg unavailable' >"$work/ace-services.txt"
fi

sessions="$work/.sessions"
: >"$sessions"
for candidate in "$INSTALL_ROOT"/logs/session-*/run.log; do
  [ -f "$candidate" ] && [ ! -L "$candidate" ] || continue
  session_dir="$(dirname "$candidate")"
  [ -d "$session_dir" ] && [ ! -L "$session_dir" ] || continue
  case "$candidate" in *$'\n'*|*$'\r'*|*$'\t'*) continue;; esac
  mtime="$(/usr/bin/stat -f %m "$candidate" 2>/dev/null || echo 0)"
  printf '%020d\t%s\n' "$mtime" "$candidate" >>"$sessions"
done

session_count=0
while IFS=$'\t' read -r mtime candidate; do
  [ -n "$candidate" ] || continue
  session_count=$((session_count + 1))
  session_dir="$(dirname "$candidate")"
  result="$session_dir/result.json"
  {
    printf '=== session %d ===\n' "$session_count"
    printf 'source=%s\n' "$candidate"
    printf 'mtime_unix=%s\n' "$((10#$mtime))"
    if [ -f "$result" ] && [ ! -L "$result" ]; then
      LC_ALL=C /usr/bin/grep -Eo '"(bootstrap_exit|server_exit|app_exit|wait_exit|forced_cleanup|lock_released)"[[:space:]]*:[[:space:]]*(true|false|null|-?[0-9]+)' "$result" | /usr/bin/sed -E 's/^"([^"]+)"[[:space:]]*:[[:space:]]*/result_\1=/' || true
    else
      printf '%s\n' 'result=unavailable'
    fi
    /usr/bin/tail -n 50000 "$candidate" | /usr/bin/awk '
      {
        lower=tolower($0)
        if (lower ~ /(ace-|anticheat|tace|ntoskrnl|driverinit|startservice|createservice|openservice|controlservice|keipigenericcall|groupsystemaffinity|bugcheck|1-1720|1000015145)/) print substr($0, 1, 4096)
      }
    ' | /usr/bin/tail -n 2000
  } | sanitize >>"$work/recent-ace-errors.log"
done < <(LC_ALL=C /usr/bin/sort -r "$sessions" | /usr/bin/head -n 5)
rm -f "$sessions"
if [ "$session_count" -eq 0 ]; then
  printf '%s\n' 'No session run.log was found.' >"$work/recent-ace-errors.log"
fi

cat >"$work/README.txt" <<'EOF'
此诊断包用于比较 ACE 驱动加载和 Wine 运行环境。

包含：系统与芯片摘要、安装/迁移版本、固定核心文件哈希、ACE 文件哈希、ACE 服务关键字段、最近保留的五次运行日志中的 ACE/ntoskrnl/服务相关行。
动态服务状态不会在离线诊断中查询，因为诊断不会启动 Wine；支持包会记录各会话已有的退出结果。
不打包：账号或令牌文件、完整 Wine prefix、游戏资源内容、完整运行日志、设备序列号。仅读取固定核心文件和 ACE 文件的字节以计算大小及哈希。筛选日志中的常见令牌、授权、Cookie 与密码字段会从字段起整段遮盖；安装根目录、用户名与用户主目录会替换为占位符。
EOF

/bin/chmod 600 "$work"/*
/usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent "$work" "$zip"
/usr/bin/unzip -tq "$zip" >/dev/null
/bin/chmod 600 "$zip"
rm -rf "$work"
completed=1
trap - EXIT
printf 'DIAGNOSTIC_ZIP=%s\n' "$zip"
