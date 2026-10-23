#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD="${1:?提供含 Recovery 完整 tar.xz 的目录}"
OUTPUT="${2:?输出目录}"
VERSION="${3:-v0.4.0-preview}"
[[ "$VERSION" =~ ^v[0-9][A-Za-z0-9._-]*$ ]] || { echo '版本号格式无效'; exit 1; }
PAYLOAD="$(cd "$PAYLOAD" && pwd)"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
APP="$OUTPUT/终末地 Mac 安装器.app"
ZIP="$OUTPUT/Wine_Endfield-Installer-${VERSION#v}.zip"
[ ! -e "$APP" ] && [ ! -e "$ZIP" ] || { echo '输出已存在，请选择新的输出目录'; exit 1; }
name="Wine_Endfield-Recovery-$VERSION.tar.xz"
archive="$PAYLOAD/$name"
[ -f "$archive" ] || { echo "缺少资源：$archive"; exit 1; }
for script in setup.sh run.sh common.sh cleanup.sh; do
  bash -n "$REPO/installer/$script"
done
# Do not follow links or allow archives to supply private data or unrelated roots.
python3 - "$archive" <<'PY'
import pathlib, posixpath, sys, tarfile
allowed = {'runtime', 'bin', 'licenses', 'environment.sh', 'RUNTIME-SHA256.txt', 'CORE-SHA256.txt',
           'PROFILE-SHA256.txt', 'fonts.reg', 'version.json', 'PACKAGE-NOTICE.txt'}
required = {'Recovery/runtime/Wine Devel.app/Contents/Resources/wine/bin/wine',
            'Recovery/runtime/Wine Devel.app/Contents/Resources/wine/bin/wineserver',
            'Recovery/bin/7zz', 'Recovery/environment.sh', 'Recovery/RUNTIME-SHA256.txt',
            'Recovery/CORE-SHA256.txt', 'Recovery/PROFILE-SHA256.txt', 'Recovery/fonts.reg'}
with tarfile.open(sys.argv[1], 'r:xz') as archive:
    entries = archive.getmembers()
    names = set()
    for entry in entries:
        path = pathlib.PurePosixPath(entry.name)
        assert not path.is_absolute() and '..' not in path.parts, entry.name
        assert path.parts and path.parts[0] == 'Recovery', entry.name
        assert len(path.parts) == 1 or path.parts[1] in allowed, entry.name
        assert entry.isfile() or entry.isdir() or entry.issym() or entry.islnk(), entry.name
        if entry.issym() or entry.islnk():
            assert not posixpath.isabs(entry.linkname), entry.name
            target = posixpath.normpath(posixpath.join(posixpath.dirname(entry.name), entry.linkname)
                                        if entry.issym() else entry.linkname)
            assert target.startswith('Recovery/'), (entry.name, entry.linkname)
        assert entry.name not in names, f'Duplicate archive entry: {entry.name}'
        names.add(entry.name)
    assert required <= names, f'Missing runtime entries: {required - names}'
print(f'Archive layout verified: {len(entries)} entries')
PY
BUILD="$(mktemp -d "$OUTPUT/.installer-build.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
FINAL_APP="$APP"
APP="$BUILD/终末地 Mac 安装器.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos26.0 "$REPO/installer/Installer.swift" -o "$APP/Contents/MacOS/EndfieldInstaller"
cp "$REPO/installer/setup.sh" "$REPO/installer/run.sh" "$REPO/installer/common.sh" "$REPO/installer/cleanup.sh" "$APP/Contents/Resources/"
cp "$REPO/installer/README.zh-CN.md" "$REPO/THIRD_PARTY.md" "$REPO/LICENSE" "$APP/Contents/Resources/"
cp "$REPO/VALIDATION.md" "$APP/Contents/Resources/"
[ ! -f "$REPO/installer/RELEASE_NOTES.md" ] || cp "$REPO/installer/RELEASE_NOTES.md" "$APP/Contents/Resources/"
manifest="$APP/Contents/Resources/payload-manifest.tsv"
printf 'format\t2\nversion\t%s\n' "$VERSION" > "$manifest"
cp "$archive" "$APP/Contents/Resources/$name"
hash="$(shasum -a 256 "$APP/Contents/Resources/$name" | awk '{print $1}')"
printf 'payload\tRecovery\t%s\t%s\n' "$name" "$hash" >> "$manifest"
plutil -create xml1 "$APP/Contents/Info.plist"
plutil -insert CFBundleExecutable -string EndfieldInstaller "$APP/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string io.wineendfield.installer "$APP/Contents/Info.plist"
plutil -insert CFBundleName -string '终末地 Mac 安装器' "$APP/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$APP/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "${VERSION#v}" "$APP/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 26.0 "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD/installer.zip"
/usr/bin/unzip -tq "$BUILD/installer.zip"
mv "$APP" "$FINAL_APP"
mv "$BUILD/installer.zip" "$ZIP"
(cd "$OUTPUT" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS.txt)
echo "$FINAL_APP"
echo "$ZIP"
