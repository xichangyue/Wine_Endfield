#!/bin/bash
# Read-only checks against an installation produced by setup.sh.
set -euo pipefail
DEST="$(cd "${1:?installation root}" && pwd)"
test -f "$DEST/.endfield-installer-v1"
test -f "$DEST/Launcher/Launcher.exe"
test -f "$DEST/Launcher/1.5.0/Games.exe"
test "$(readlink "$DEST/Launcher/games/Arknights Endfield")" = "$DEST/Game"
test "$(readlink "$DEST/Updater/local/prefix/drive_c/Endfield")" = "$DEST/Game"
test -f "$DEST/Updater/local/ready-v1"
for mode in Vulkan DirectX11; do
  [ -d "$DEST/$mode" ] || continue
  test -f "$DEST/$mode/local/ready-v1"
  test "$(readlink "$DEST/$mode/local/prefix/drive_c/Endfield")" = "$DEST/Game"
  echo "$mode shared mapping PASS"
done
for app in "$DEST/Apps/"*.app; do
  codesign --verify --strict "$app"
  "$app/Contents/MacOS/EndfieldInstaller" --check
done
echo 'Installed structure and app entry checks PASS'
