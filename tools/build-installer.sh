#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD="${1:?提供含两个当前版本完整 tar.xz 的目录}"
OUTPUT="${2:?输出目录}"
VERSION="${3:-v0.3.0-preview}"
[[ "$VERSION" =~ ^v[0-9][A-Za-z0-9._-]*$ ]] || { echo '版本号格式无效'; exit 1; }
APP="$OUTPUT/终末地 Mac 安装器.app"
[ ! -e "$APP" ] || { echo '输出已存在，请选择新的输出目录'; exit 1; }
for mode in Vulkan DirectX11; do
  archive="$PAYLOAD/Wine_Endfield-$mode-$VERSION.tar.xz"
  [ -f "$archive" ] || { echo "缺少资源：$archive"; exit 1; }
  /usr/bin/tar -tf "$archive" | awk -v mode="$mode" '
    /^\// || /(^|\/)\.\.(\/|$)/ { bad=1 }
    $0 != mode && $0 != mode "/" && index($0, mode "/") != 1 { bad=1 }
    $0 ~ ("^" mode "/local(/|$)") { bad=1 }
    END { exit bad }' || { echo "资源目录结构无效：$archive"; exit 1; }
done
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos26.0 "$REPO/installer/Installer.swift" -o "$APP/Contents/MacOS/EndfieldInstaller"
cp "$REPO/installer/setup.sh" "$REPO/installer/run.sh" "$APP/Contents/Resources/"
cp "$REPO/installer/README.zh-CN.md" "$REPO/THIRD_PARTY.md" "$REPO/LICENSE" "$APP/Contents/Resources/"
manifest="$APP/Contents/Resources/payload-manifest.tsv"
printf 'format\t1\nversion\t%s\n' "$VERSION" > "$manifest"
for mode in Vulkan DirectX11; do
  name="Wine_Endfield-$mode-$VERSION.tar.xz"
  cp "$PAYLOAD/$name" "$APP/Contents/Resources/$name"
  hash="$(shasum -a 256 "$APP/Contents/Resources/$name" | awk '{print $1}')"
  printf 'payload\t%s\t%s\t%s\n' "$mode" "$name" "$hash" >> "$manifest"
done
plutil -create xml1 "$APP/Contents/Info.plist"
plutil -insert CFBundleExecutable -string EndfieldInstaller "$APP/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string io.wineendfield.installer "$APP/Contents/Info.plist"
plutil -insert CFBundleName -string '终末地 Mac 安装器' "$APP/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$APP/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "${VERSION#v}" "$APP/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 26.0 "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "$APP"
