#!/bin/bash
# Standalone launcher for the read-only ACE support bundle collector.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"

if [ "$#" -eq 1 ]; then
  root="$1"
elif [ "$#" -eq 0 ]; then
  root="$(/usr/bin/osascript <<'APPLESCRIPT'
try
  POSIX path of (choose folder with prompt "选择终末地 Mac 安装目录（其中应有 Apps、State 和 logs）")
on error number -128
  return ""
end try
APPLESCRIPT
)"
  [ -n "$root" ] || exit 0
else
  echo '可双击后选择安装目录，或将一个安装目录拖到此文件上。' >&2
  exit 2
fi

output="$(/bin/bash "$here/diagnose.sh" --root "$root")"
printf '%s\n' "$output"
zip="$(printf '%s\n' "$output" | /usr/bin/awk -F= '$1=="DIAGNOSTIC_ZIP" {print substr($0, index($0,"=")+1); exit}')"
[ -n "$zip" ] && [ -f "$zip" ] && [ ! -L "$zip" ] || {
  echo '诊断脚本没有返回有效的支持包。' >&2
  exit 1
}
if [ "${ENDFIELD_DIAGNOSTIC_NO_REVEAL:-0}" != 1 ]; then
  /usr/bin/open -R "$zip"
fi
