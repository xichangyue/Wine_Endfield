#!/bin/bash
# Package audited runtime directories only; never copy a Wine prefix.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?请提供版本号}"
OUT="${2:?请提供输出目录}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
STAGE="$(mktemp -d)"
echo "临时打包目录：$STAGE"
for mode in Vulkan DirectX11; do
  mkdir -p "$STAGE/$mode"
  cp "$REPO/$mode/common.sh" "$REPO/$mode/"*.command "$REPO/$mode/README.md" "$STAGE/$mode/"
  cp "$REPO/README.md" "$STAGE/$mode/使用说明.md"
  cp "$REPO/BUILD.zh-CN.md" "$REPO/THIRD_PARTY.md" "$REPO/LICENSE" "$STAGE/$mode/"
  cp -R "$REPO/$mode/source" "$REPO/$mode/licenses" "$REPO/$mode/runtime" "$STAGE/$mode/"
  cp "$REPO/$mode/RUNTIME-SHA256.txt" "$STAGE/$mode/"
  test ! -e "$STAGE/$mode/local"
  target="$OUT/Wine_Endfield-$mode-$VERSION.tar.xz"
  test ! -e "$target" || { echo "输出已存在，拒绝覆盖：$target"; exit 1; }
  COPYFILE_DISABLE=1 /usr/bin/tar -cJf "$target" -C "$STAGE" "$mode"
done
echo "完整运行时包已生成；发布前还需源码附件与 SHA256SUMS。"
