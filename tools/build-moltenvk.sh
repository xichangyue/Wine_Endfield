#!/bin/bash
# Build the complete, already-patched source attachment without network fetches.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:?用法：build-moltenvk.sh MoltenVK-1.4.2-Endfield-v0.3.0-source.tar.xz [--check]}"
CHECK_ONLY="${2:-}"
[[ -z "$CHECK_ONLY" || "$CHECK_ONLY" == --check ]] || exit 2
ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"
EXPECTED=b24254c87e0219cf32ce1282a3190aadce2f923c555ed49517e69df235a4aa84
[[ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" == "$EXPECTED" ]] || {
  echo 'MoltenVK 源码附件 SHA-256 不匹配。' >&2; exit 2;
}
mkdir -p "$REPO/Vulkan/local"
WORK="$(mktemp -d "$REPO/Vulkan/local/moltenvk-build-XXXXXX")"
tar -xf "$ARCHIVE" -C "$WORK"
SOURCE="$WORK/MoltenVK-1.4.2-Endfield-v0.3.0-source"
(cd "$SOURCE"; shasum -a 256 -c SOURCE-SHA256.txt > "$WORK/source-check.log")
if [[ "$CHECK_ONLY" == --check ]]; then
  echo "源码附件与逐文件校验通过；未编译、未启动游戏。工作目录：$WORK"
  exit 0
fi
command -v xcodebuild >/dev/null
xcodebuild -version
(
  cd "$SOURCE"
  # Upstream ships these generated SPIRV-Tools headers in its tracked template.
  # Running fetchDependencies here would discard the admitted SPIRV-Cross patch.
  unzip -o -q Templates/spirv-tools/build.zip -d External/SPIRV-Tools
  export SKIP_PACKAGING=Y KEEP_CACHE=Y
  xcodebuild build -project ExternalDependencies.xcodeproj \
    -scheme ExternalDependencies-macOS -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath External/build/Intermediates/macos -jobs 2 -quiet
  # Follow upstream fetchDependencies' packaging steps after the source build.
  # Its helper scripts use optional variables, so avoid nounset within them.
  (
    set +u
    export PROJECT_DIR="$PWD" CONFIGURATION=Release SKIP_PACKAGING="" KEEP_CACHE=Y
    . ./Scripts/create_ext_lib_xcframeworks.sh
    . ./Scripts/package_ext_libs_finish.sh
  )
  xcodebuild build -project MoltenVKPackaging.xcodeproj \
    -scheme 'MoltenVK Package (macOS only)' -configuration Release \
    -destination 'generic/platform=macOS' -jobs 2 -quiet
)
ARTIFACT="$SOURCE/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
[[ -f "$ARTIFACT" ]] || { echo '未找到预期的 MoltenVK 产物。' >&2; exit 2; }
echo "构建完成：$ARTIFACT"
shasum -a 256 "$ARTIFACT"
echo '不会自动覆盖已验证运行时。不同 Xcode/SDK 或重新签名可改变二进制 SHA。'
