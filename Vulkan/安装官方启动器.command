#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source ./common.sh
trap 'echo "安装后可通过“更新游戏”重新打开官方启动器。按回车关闭。"; read -r _' EXIT
check_idle
prepare
if find_installed Launcher.exe; then
  echo "已找到启动器：$FOUND"
  echo "无需重复安装，请运行“更新游戏.command”。"
  exit 0
fi
select_path '从游戏官网下载的启动器安装器 EXE'
[ -f "$SELECTED" ] || { echo "找不到安装器文件"; exit 1; }
case "$SELECTED" in *.exe|*.EXE) ;; *) echo "请选择 Windows EXE 安装器"; exit 1 ;; esac
EXTRACTOR="$ROOT/bin/7zz"
[ -x "$EXTRACTOR" ] || { echo "缺少解包组件，请使用完整 Release 包。"; exit 1; }
[ "$(shasum -a 256 "$EXTRACTOR" | awk '{print $1}')" = 74b0910e50ea44d9760a57fada2192cfd530ba8bffbe7b47c412a464b796cabf ] || { echo "解包组件校验失败"; exit 1; }
STAGE="$(mktemp -d "$STATE/launcher-extract.XXXXXX")"
echo "正在提取官方安装包原始文件，不运行不兼容的32位安装界面。"
"$EXTRACTOR" x "$SELECTED" "-o$STAGE" '$0/*' -y > "$STATE/logs/extract-launcher-$(date +%Y%m%d-%H%M%S).log" 2>&1
PAYLOADS=()
if [ -d "$STAGE/\$0" ]; then
  for item in "$STAGE/\$0/"*; do
    if [ -d "$item" ] && [ -f "$item/Launcher.exe" ] && [ -f "$item/Games.exe" ]; then PAYLOADS+=("$item"); fi
  done
fi
[ "${#PAYLOADS[@]}" = 1 ] || { echo "安装包结构不支持，需要唯一包含 Launcher.exe 和 Games.exe 的版本目录。提取结果保留在 $STAGE"; exit 1; }
PAYLOAD="${PAYLOADS[0]}"
OFFICIAL_VERSION="$(basename "$PAYLOAD")"
[[ "$OFFICIAL_VERSION" =~ ^[0-9][A-Za-z0-9._-]*$ ]] || { echo '无效官方版本目录'; exit 1; }
DEST="$WINEPREFIX/drive_c/HypergryphLauncher"
[ ! -e "$DEST" ] || { echo "目标目录已存在，请先检查 $DEST，避免覆盖已有安装。"; exit 1; }
mkdir -p "$DEST"
cp -R "$PAYLOAD" "$DEST/$OFFICIAL_VERSION"
cp "$DEST/$OFFICIAL_VERSION/Launcher.exe" "$DEST/Launcher.exe"
echo "官方启动器已准备好。请在启动器中自行确认协议并下载游戏，下载后退出启动器，再运行“启动游戏”。"
exec /bin/bash "$ROOT/更新游戏.command"
