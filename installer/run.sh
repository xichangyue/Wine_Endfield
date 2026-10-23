#!/bin/bash
set -euo pipefail
INSTALL_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
source "$INSTALL_ROOT/common.sh"
# Legacy shortcuts remain compatible, but never override the official checkbox.
case "${1:-Launcher}" in Launcher|Update|Vulkan|DirectX11|--check) ;; *) fail '未知启动操作。';; esac
RECOVERY="$INSTALL_ROOT/Recovery"
WINE_ROOT="$RECOVERY/runtime/Wine Devel.app/Contents/Resources/wine"
PREFIX="$INSTALL_ROOT/State/prefix"
assert_platform
validate_path "$INSTALL_ROOT"
verify_installation
if [ "${1:-}" = --check ]; then
  echo '配置检查通过：官方启动器，未勾选 DX11 为 Vulkan，勾选为 DX11/DXMT。'
  exit 0
fi
if [ "${ENDFIELD_LOCK_HELD:-}" != 1 ]; then
  exec "$INSTALL_ROOT/Apps/终末地.app/Contents/MacOS/EndfieldInstaller" --with-lock "$INSTALL_ROOT" "$INSTALL_ROOT/run.sh" Launcher
fi
assert_idle
mkdir -p "$INSTALL_ROOT/logs"
SESSION="$(mktemp -d "$INSTALL_ROOT/logs/session-$(date +%Y%m%d-%H%M%S).XXXXXX")"
mkdir "$SESSION/capture"
# Keep only the last four completed sessions plus the new session.
completed=()
for dir in "$INSTALL_ROOT"/logs/session-*; do
  [ -d "$dir" ] && [ ! -L "$dir" ] && [ -f "$dir/completed" ] && completed+=("$dir")
done
for (( i=0; i<${#completed[@]}-4; i++ )); do rm -rf "${completed[$i]}"; done
load_environment
status=0
cd "$INSTALL_ROOT/Launcher"
echo "正在打开官方启动器。本次日志：$SESSION/run.log"
"$WINE_ROOT/bin/wine" 'C:\Hypergryph Launcher\Launcher.exe' >"$SESSION/run.log" 2>&1 || status=$?
# Launcher.exe may return before Games.exe or the game; keep the lock until Wine ends.
"$WINE_ROOT/bin/wineserver" -w >>"$SESSION/run.log" 2>&1 || status=$?
printf '%s\n' "$status" >"$SESSION/completed"
exit "$status"
