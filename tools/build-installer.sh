#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD="${1:?提供含两个 v0.1.0 完整 tar.xz 的目录}"
OUTPUT="${2:?输出目录}"
APP="$OUTPUT/终末地 Mac 安装器.app"
[ ! -e "$APP" ] || { echo '输出已存在，请选择新的输出目录'; exit 1; }
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos13.0 "$REPO/installer/Installer.swift" -o "$APP/Contents/MacOS/EndfieldInstaller"
cp "$REPO/installer/setup.sh" "$REPO/installer/run.sh" "$APP/Contents/Resources/"
cp "$REPO/installer/README.zh-CN.md" "$REPO/THIRD_PARTY.md" "$REPO/LICENSE" "$APP/Contents/Resources/"
for mode in Vulkan DirectX11; do
  cp "$PAYLOAD/Wine_Endfield-$mode-v0.1.0-experimental.tar.xz" "$APP/Contents/Resources/"
done
plutil -create xml1 "$APP/Contents/Info.plist"
plutil -insert CFBundleExecutable -string EndfieldInstaller "$APP/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string io.wineendfield.installer "$APP/Contents/Info.plist"
plutil -insert CFBundleName -string '终末地 Mac 安装器' "$APP/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$APP/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 0.2.0-preview "$APP/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 13.0 "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
