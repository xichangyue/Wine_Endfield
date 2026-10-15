#!/bin/bash
# Read-only checks against an installation produced by setup.sh.
set -euo pipefail
DEST="$(cd "${1:?installation root}" && pwd)"
test -f "$DEST/.endfield-installer-v1"
test -f "$DEST/Launcher/Launcher.exe"
test -f "$DEST/payload-manifest.tsv"
if [ -f "$DEST/Launcher/.official-version" ]; then
  official="$(cat "$DEST/Launcher/.official-version")"
else
  official=1.5.0 # Existing v0.2.0 installer layout remains supported.
fi
[[ "$official" =~ ^[0-9][A-Za-z0-9._-]*$ ]]
test -f "$DEST/Launcher/$official/Games.exe"
test "$(readlink "$DEST/Launcher/games/Arknights Endfield")" = "$DEST/Game"
test "$(readlink "$DEST/Updater/local/prefix/drive_c/Endfield")" = "$DEST/Game"
test -f "$DEST/Updater/local/ready-v1"
for mode in Vulkan DirectX11; do
  [ -d "$DEST/$mode" ] || continue
  test -f "$DEST/$mode/local/ready-v1"
  test -f "$DEST/$mode/.payload-id"
  test -f "$DEST/$mode/RUNTIME-SHA256.txt"
  (cd "$DEST/$mode/runtime" && shasum -a 256 -c ../RUNTIME-SHA256.txt) > /dev/null
  if [ "$mode" = Vulkan ]; then test -f "$DEST/$mode/game-profile.sh"; fi
  test "$(readlink "$DEST/$mode/local/prefix/drive_c/Endfield")" = "$DEST/Game"
  echo "$mode shared mapping PASS"
done
for app in "$DEST/Apps/"*.app; do
  codesign --verify --strict "$app"
  "$app/Contents/MacOS/EndfieldInstaller" --check
done
echo 'Installed structure and app entry checks PASS'
