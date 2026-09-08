#!/bin/bash
# Build only modified Wine modules; install into an existing release separately.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:?用法：build-overlay.sh Vulkan或DirectX11 Wine源码压缩包}"
ARCHIVE="${2:?请指定wine-11.16-source.tar.gz}"
case "$MODE" in Vulkan|DirectX11) ;; *) exit 2 ;; esac
ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"
test "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" = 2b6d5cff784cb774f7f17b9a640b123ca8361d89c4280c0021b70bb6f3cd1b1c
command -v x86_64-w64-mingw32-clang >/dev/null
command -v bison >/dev/null
WORK="$REPO/$MODE/local/build-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$WORK/unix" "$WORK/pe"
tar -xf "$ARCHIVE" -C "$WORK"
SOURCE="$WORK/wine-wine-11.16"
patch -p1 -d "$SOURCE" < "$REPO/$MODE/source/wine-11.16.patch"
flags=(--build=x86_64-apple-darwin25.6.0 --host=x86_64-apple-darwin25.6.0 --enable-win64 --disable-tests --without-x --without-gstreamer --without-gnutls --without-freetype --without-sdl --without-vulkan)
(cd "$WORK/unix"; CC='/usr/bin/clang -arch x86_64' CXX='/usr/bin/clang++ -arch x86_64' "$SOURCE/configure" "${flags[@]}" --enable-archs=none)
(cd "$WORK/pe"; CC='/usr/bin/clang -arch x86_64' CXX='/usr/bin/clang++ -arch x86_64' "$SOURCE/configure" "${flags[@]}" --enable-archs=x86_64)
make -C "$WORK/unix" -j6 dlls/ntdll/ntdll.so server/wineserver
make -C "$WORK/pe" -j6 dlls/kernel32/x86_64-windows/kernel32.dll dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe
OUT="$WORK/overlay"
mkdir -p "$OUT/bin" "$OUT/lib/wine/x86_64-unix" "$OUT/lib/wine/x86_64-windows"
cp "$WORK/unix/dlls/ntdll/ntdll.so" "$OUT/lib/wine/x86_64-unix/"
cp "$WORK/unix/server/wineserver" "$OUT/bin/"
cp "$WORK/pe/dlls/kernel32/x86_64-windows/kernel32.dll" "$OUT/lib/wine/x86_64-windows/"
cp "$WORK/pe/dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe" "$OUT/lib/wine/x86_64-windows/"
if [ "$MODE" = DirectX11 ]; then
  make -C "$WORK/unix" -j6 dlls/winemac.drv/winemac.so
  cp "$WORK/unix/dlls/winemac.drv/winemac.so" "$OUT/lib/wine/x86_64-unix/"
fi
codesign --force --sign - "$OUT/bin/wineserver"
for module in "$OUT/lib/wine/x86_64-unix/"*.so; do codesign --force --sign - "$module"; done
echo "构建完成：$OUT"
echo "安装步骤见 BUILD.zh-CN.md。不会自动覆盖当前运行时。"
