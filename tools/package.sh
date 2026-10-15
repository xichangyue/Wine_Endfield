#!/bin/bash
# Package audited runtime directories only; never copy a Wine prefix.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?请提供版本号}"
OUT="${2:?请提供输出目录}"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || { echo '无效版本号' >&2; exit 2; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/endfield-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
for mode in Vulkan DirectX11; do
  mkdir -p "$STAGE/$mode"
  cp "$REPO/$mode/common.sh" "$REPO/$mode/"*.command "$REPO/$mode/"*.reg "$REPO/$mode/README.md" "$STAGE/$mode/"
  if [ "$mode" = Vulkan ]; then cp "$REPO/$mode/game-profile.sh" "$STAGE/$mode/"; fi
  cp "$REPO/README.md" "$STAGE/$mode/使用说明.md"
  cp "$REPO/BUILD.zh-CN.md" "$REPO/THIRD_PARTY.md" "$REPO/LICENSE" "$STAGE/$mode/"
  cp -R "$REPO/$mode/source" "$REPO/$mode/licenses" "$REPO/$mode/runtime" "$REPO/$mode/bin" "$STAGE/$mode/"
  cp "$REPO/$mode/RUNTIME-SHA256.txt" "$STAGE/$mode/"
  test ! -e "$STAGE/$mode/local"
  test ! -e "$STAGE/$mode/.git"
  (cd "$STAGE/$mode/runtime" && shasum -a 256 -c ../RUNTIME-SHA256.txt > /dev/null)
  target="$OUT/Wine_Endfield-$mode-$VERSION.tar.xz"
  test ! -e "$target" || { echo "输出已存在，拒绝覆盖：$target" >&2; exit 1; }
  if command -v xz >/dev/null 2>&1; then
    COPYFILE_DISABLE=1 /usr/bin/tar -cf - -C "$STAGE" "$mode" | xz -T2 -3 > "$target"
  else
    COPYFILE_DISABLE=1 /usr/bin/tar -cJf "$target" -C "$STAGE" "$mode"
  fi
done
echo '完整运行时包已生成；发布前还需源码附件与 SHA256SUMS。'
