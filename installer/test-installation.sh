#!/bin/bash
# Read-only checks; never start Wine, create a prefix, or update the official game.
set -euo pipefail
DEST="$(cd "${1:?installation root}" && pwd)"
test -f "$DEST/.endfield-installer-v1"
test -f "$DEST/Launcher/Launcher.exe"
test -f "$DEST/payload-manifest.tsv"
/bin/bash "$DEST/run.sh" --check
test "$(readlink "$DEST/State/prefix/drive_c/Endfield")" = '../../../Game'
test "$(readlink "$DEST/State/prefix/drive_c/Hypergryph Launcher")" = '../../../Launcher'
test "$(readlink "$DEST/State/prefix/dosdevices/c:")" = '../drive_c'
test "$(readlink "$DEST/Launcher/games/Arknights Endfield")" = '../../Game'
test -d "$DEST/State/prefix/drive_c/Endfield"
test -f "$DEST/State/prefix/drive_c/Hypergryph Launcher/Launcher.exe"
(cd "$DEST/Recovery/runtime" && shasum -a 256 -c ../RUNTIME-SHA256.txt) > /dev/null
(cd "$DEST/Recovery" && shasum -a 256 -c PROFILE-SHA256.txt) > /dev/null
for name in '终末地' '终末地 Vulkan' '终末地 DX11' '终末地 更新与修复'; do
  app="$DEST/Apps/$name.app"
  if [ "$name" = '终末地' ]; then test -d "$app"; else [ -d "$app" ] || continue; fi
  codesign --verify --strict "$app"
  "$app/Contents/MacOS/EndfieldInstaller" --check
done
echo 'Installed runtime, relative mappings, and application entry checks PASS'
