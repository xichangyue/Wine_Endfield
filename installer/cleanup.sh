#!/bin/bash
# Called by setup.sh only after the new installation has committed and Wine exited.
# Delete identified, obsolete installer-owned content; never follow directory links.
set -uo pipefail
ROOT="${1:?installation root}"
problem=0; removed=0; reclaimed_kb=0
warn() { printf '清理提醒：%s\n' "$*" >&2; }
stop() { warn "$*"; exit 1; }
[[ "$ROOT" = /* && "$ROOT" != / && "$ROOT" != *$'\n'* && "$ROOT" != *$'\r'* && "$ROOT" != *$'\t'* ]] || stop '安装目录无效，未清理。'
[ -d "$ROOT" ] && [ ! -L "$ROOT" ] || stop '安装目录不是实体文件夹，未清理。'
ROOT="$(cd "$ROOT" && pwd -P)" || exit 1
for item in .endfield-installer-v1 payload-manifest.tsv common.sh Recovery/.payload-id State/prefix/system.reg; do
  [ -f "$ROOT/$item" ] && [ ! -L "$ROOT/$item" ] || stop "缺少已安装版本的标记：$item；未清理。"
done
for item in Recovery State State/prefix; do
  [ -d "$ROOT/$item" ] && [ ! -L "$ROOT/$item" ] || stop "当前环境路径异常：$item；未清理。"
done
/usr/bin/awk -F '\t' '$1=="format"&&$2=="2"{f++} $1=="version"&&$2~/^v[0-9][A-Za-z0-9._-]*$/{v++} END{exit f!=1||v!=1}' "$ROOT/payload-manifest.tsv" || stop '当前环境尚未升级到新版，未清理。'
/usr/bin/awk 'NF==2&&$1~/^v[0-9][A-Za-z0-9._-]*$/&&$2~/^[0-9a-f]+$/&&length($2)==64{good++} END{exit NR!=1||good!=1}' "$ROOT/Recovery/.payload-id" || stop '当前运行库标记无效，未清理。'
source "$ROOT/common.sh"
fail() { stop "$*"; }
assert_idle
printf '正在自动清理旧版本运行库、未采用的环境与缓存……\n'

# Every candidate must have real directory ancestors within the managed root.
safe_path() {
  local path="$1" parent
  case "$path" in "$ROOT"/*) ;; *) warn "路径超出安装目录，保留：$path"; return 1;; esac
  parent="$path"
  while [ "$parent" != "$ROOT" ]; do
    if [ -L "$parent" ]; then warn "保留符号链接，不访问其目标：${parent#"$ROOT"/}"; return 1; fi
    parent="$(dirname "$parent")"
  done
}

# A real game directory in an old Wine prefix is not a disposable cache. Links
# such as drive_c/Endfield -> ROOT/Game are not traversed by find or rm.
safe_content() {
  local path="$1" game devices own_device
  safe_path "$path" || return 1
  [ -d "$path" ] || return 0
  if ! game="$(/usr/bin/find -P -x "$path" \( \( -type f -iname 'Endfield.exe' \) -o \( -type d \( -iname 'Endfield_Data' -o -ipath '*/drive_c/Endfield' -o -iname 'Arknights Endfield' \) \) \) -print 2>&1)"; then
    warn "无法检查目录，保留：${path#"$ROOT"/}（$game）"; problem=1; return 1
  fi
  [ -z "$game" ] || { warn "发现实体游戏文件或目录，整体保留：${path#"$ROOT"/}"; return 1; }
  own_device="$(/usr/bin/stat -f %d "$path")" || { problem=1; return 1; }
  devices="$(/usr/bin/find -P -x "$path" -type d -exec /usr/bin/stat -f %d {} + | /usr/bin/sort -u)" || { warn "无法检查磁盘边界，保留：${path#"$ROOT"/}"; problem=1; return 1; }
  [ "$devices" = "$own_device" ] || { warn "目录内有其他挂载磁盘，保留：${path#"$ROOT"/}"; return 1; }
}

remove_owned() {
  local path="$1" size
  [ -e "$path" ] || [ -L "$path" ] || return 0
  safe_content "$path" || return 0
  size="$(/usr/bin/du -sk "$path" | /usr/bin/awk '{print $1}')" || { warn "无法读取大小，保留：${path#"$ROOT"/}"; problem=1; return 0; }
  if /bin/rm -rf "$path"; then
    removed=$((removed + 1)); reclaimed_kb=$((reclaimed_kb + size))
    printf '已清理：%s\n' "${path#"$ROOT"/}"
  else
    warn "清理未完成，已保留可重试的剩余内容：${path#"$ROOT"/}"; problem=1
  fi
}

finish_directory() {
  local path="$1"
  [ -d "$path" ] && [ ! -L "$path" ] || return 0
  if [ -z "$(/bin/ls -A "$path")" ]; then
    /bin/rmdir "$path" || { warn "无法删除空目录：${path#"$ROOT"/}"; problem=1; }
  else
    warn "保留未识别的自定义内容或受保护文件：${path#"$ROOT"/}"
  fi
}

valid_payload_id() {
  [ -f "$1/.payload-id" ] && [ ! -L "$1/.payload-id" ] || return 1
  /usr/bin/awk 'NF==2&&$1~/^v[0-9][A-Za-z0-9._-]*$/&&$2~/^[0-9a-f]+$/&&length($2)==64{good++} END{exit NR!=1||good!=1}' "$1/.payload-id"
}

valid_hash_manifest() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  /usr/bin/awk '{h=substr($0,1,64);p=substr($0,67); if(h!~/^[0-9a-f]+$/||length(h)!=64||substr($0,65,2)!="  "||p==""||p~/^\//||p~/(^|\/)\.\.(\/|$)/) bad=1} END{exit !NR||bad}' "$1"
}

# The published runtime manifest lists regular files. If a user added a file
# inside runtime/overlay, retain that tree rather than silently erasing it.
clean_manifest_tree() {
  local path="$1" manifest="$2" extra
  [ -e "$path" ] || [ -L "$path" ] || return 0
  safe_path "$path" || return 0
  valid_hash_manifest "$manifest" || { warn "缺少有效运行库清单，保留：${path#"$ROOT"/}"; return 0; }
  extra="$(/usr/bin/find -P -x "$path" -type f -print | /usr/bin/awk -v root="$path/" 'NR==FNR{p=substr($0,67);sub(/^\.\//,"",p);known[root p]=1;next} !($0 in known)&&$0!~/\/\.DS_Store$/&&!extra{print;extra=1}' "$manifest" -)" || { warn "无法检查运行库清单，保留：${path#"$ROOT"/}"; problem=1; return 0; }
  [ -z "$extra" ] || { warn "运行库含清单以外的自定义文件，保留：${path#"$ROOT"/}"; return 0; }
  remove_owned "$path"
}

clean_metadata() {
  local path="$1" item
  for item in source/wine-11.16.patch source/spirv-cross-device-barrier.patch source/moltenvk-1.4.2-endfield.patch source/SOURCE-PROVENANCE.json \
      licenses/7zip-License.txt licenses/DXMT-MIT.txt licenses/DXVK-MIT.txt licenses/Installer-MIT.txt licenses/MoltenVK-Apache-2.0.txt \
      licenses/Wine-AUTHORS.txt licenses/Wine-LICENSE.txt licenses/Wine-LGPL-2.1.txt \
      licenses/DXMT-dependencies/CC0-1.0.txt licenses/DXMT-dependencies/DXBCParser-MIT.txt licenses/DXMT-dependencies/DXVK-zlib.txt \
      licenses/DXMT-dependencies/LLVM-15.0.7-BLAKE3-LICENSE.txt licenses/DXMT-dependencies/LLVM-15.0.7-ConvertUTF-NOTICE.txt \
      licenses/DXMT-dependencies/LLVM-15.0.7-LICENSE.txt licenses/DXMT-dependencies/LLVM-15.0.7-MD5-NOTICE.txt \
      licenses/DXMT-dependencies/LLVM-15.0.7-SHA1-NOTICE.txt licenses/DXMT-dependencies/LLVM-15.0.7-SHA256-NOTICE.txt \
      licenses/DXMT-dependencies/LLVM-15.0.7-regex-COPYRIGHT.txt licenses/DXMT-dependencies/LLVM-15.0.7-xxhash-NOTICE.txt \
      licenses/DXMT-dependencies/MinGW-directx-COPYING.txt licenses/DXMT-dependencies/README.txt \
      licenses/DXMT-dependencies/SHA256-NOTICE.txt licenses/DXMT-dependencies/generator-NOTICE.txt \
      licenses/MoltenVK-dependencies/Vulkan-Tools/LICENSE.txt licenses/MoltenVK-dependencies/Vulkan-Tools/LICENSES/Apache-2.0.txt \
      licenses/MoltenVK-dependencies/Vulkan-Headers/LICENSE.md licenses/MoltenVK-dependencies/Vulkan-Headers/LICENSES/MIT.txt licenses/MoltenVK-dependencies/Vulkan-Headers/LICENSES/Apache-2.0.txt \
      licenses/MoltenVK-dependencies/cereal/LICENSE licenses/MoltenVK-dependencies/Volk/LICENSE.md licenses/MoltenVK-dependencies/SPIRV-Tools/LICENSE \
      licenses/MoltenVK-dependencies/SPIRV-Headers/LICENSE licenses/MoltenVK-dependencies/SPIRV-Headers/LICENSES/MIT.txt \
      licenses/MoltenVK-dependencies/SPIRV-Headers/LICENSES/CC-BY-4.0.txt licenses/MoltenVK-dependencies/SPIRV-Cross/LICENSE \
      licenses/MoltenVK-dependencies/SPIRV-Cross/LICENSES/Apache-2.0.txt licenses/MoltenVK-dependencies/SPIRV-Cross/LICENSES/MIT.txt \
      licenses/MoltenVK-dependencies/SPIRV-Cross/LICENSES/CC-BY-4.0.txt licenses/MoltenVK-dependencies/SPIRV-Cross/LICENSES/LicenseRef-KhronosFreeUse.txt; do
    remove_owned "$path/$item"
  done
  for item in source licenses; do
    [ -d "$path/$item" ] && safe_path "$path/$item" || continue
    /usr/bin/find -P -x "$path/$item" -depth -type d -empty -delete || { warn "无法删除空目录：${path#"$ROOT"/}/$item"; problem=1; }
    finish_directory "$path/$item"
  done
}

clean_state() {
  local path="$1" item
  [ -d "$path" ] || [ -L "$path" ] || return 0
  safe_content "$path" || return 0
  if ! { [ -f "$path/prefix/system.reg" ] && [ ! -L "$path/prefix/system.reg" ]; } && ! { [ -f "$path/ready-v1" ] && [ ! -L "$path/ready-v1" ]; }; then
    warn "无法识别旧 Wine 环境，保留：${path#"$ROOT"/}"; return 0
  fi
  for item in prefix cache downloads logs runtime dxmt moltenvk ready-v1 installed-version .DS_Store; do remove_owned "$path/$item"; done
  finish_directory "$path"
}

clean_mode() {
  local path="$1" item
  [ -d "$path" ] || [ -L "$path" ] || return 0
  safe_path "$path" || return 0
  # Early v0.2 installers did not write .payload-id; their runtime manifest and
  # configuration files still identify the managed payload unambiguously.
  if [ -e "$path/.payload-id" ] || [ -L "$path/.payload-id" ]; then
    valid_payload_id "$path" || { warn "旧运行库标记无效，保留：${path#"$ROOT"/}"; return 0; }
  elif ! { valid_hash_manifest "$path/RUNTIME-SHA256.txt" && [ -f "$path/common.sh" ] && [ ! -L "$path/common.sh" ] && [ -f "$path/fonts.reg" ] && [ ! -L "$path/fonts.reg" ]; }; then
    warn "无法识别旧运行库归属，保留：${path#"$ROOT"/}"; return 0
  fi
  clean_state "$path/local"
  clean_manifest_tree "$path/runtime" "$path/RUNTIME-SHA256.txt"
  clean_manifest_tree "$path/overlay" "$path/OVERLAY-SHA256.txt"
  for item in game-profile.sh README.md BUILD.zh-CN.md THIRD_PARTY.md LICENSE 使用说明.md 启动游戏.command 安装官方启动器.command 更新游戏.command bin/7zz .DS_Store; do remove_owned "$path/$item"; done
  clean_metadata "$path"
  # Keep ownership evidence for a later automatic retry if a game, custom
  # content or an I/O failure prevented removing any old managed subtree.
  if [ ! -e "$path/runtime" ] && [ ! -L "$path/runtime" ] && [ ! -e "$path/overlay" ] && [ ! -L "$path/overlay" ] && [ ! -e "$path/local" ] && [ ! -L "$path/local" ]; then
    remove_owned "$path/RUNTIME-SHA256.txt"; remove_owned "$path/OVERLAY-SHA256.txt"
    remove_owned "$path/.payload-id"; remove_owned "$path/common.sh"; remove_owned "$path/fonts.reg"
  fi
  finish_directory "$path/bin"
  finish_directory "$path"
}

clean_recovery() {
  local path="$1" item
  [ -d "$path" ] || [ -L "$path" ] || return 0
  safe_path "$path" || return 0
  valid_payload_id "$path" || { warn "无法识别旧修复运行库，保留：${path#"$ROOT"/}"; return 0; }
  clean_manifest_tree "$path/runtime" "$path/RUNTIME-SHA256.txt"
  for item in environment.sh CORE-SHA256.txt PROFILE-SHA256.txt fonts.reg version.json PACKAGE-NOTICE.txt bin/7zz .DS_Store; do remove_owned "$path/$item"; done
  clean_metadata "$path"
  if [ ! -e "$path/runtime" ] && [ ! -L "$path/runtime" ]; then
    remove_owned "$path/RUNTIME-SHA256.txt"; remove_owned "$path/.payload-id"
  fi
  finish_directory "$path/bin"; finish_directory "$path"
}

clean_backup_apps() {
  local path="$1" app plist id
  [ -d "$path" ] || [ -L "$path" ] || return 0
  safe_path "$path" || return 0
  for app in "$path/终末地.app" "$path/终末地 Vulkan.app" "$path/终末地 DX11.app" "$path/终末地 更新与修复.app"; do
    [ -d "$app" ] && [ ! -L "$app" ] || continue
    plist="$app/Contents/Info.plist"
    [ -f "$plist" ] && [ ! -L "$plist" ] || continue
    safe_path "$plist" || continue
    id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null)" || continue
    case "$id" in io.wineendfield.installed.*) remove_owned "$app";; esac
  done
  remove_owned "$path/.DS_Store"; finish_directory "$path"
}

owned_snapshot() {
  local path="$1"
  if [ -f "$path/.endfield-backup-v1" ] && [ ! -L "$path/.endfield-backup-v1" ] && [ ! -s "$path/.endfield-backup-v1" ]; then return 0; fi
  [ -f "$path/payload-manifest.tsv" ] && [ ! -L "$path/payload-manifest.tsv" ] || return 1
  /usr/bin/awk -F '\t' '$1=="format"&&($2=="1"||$2=="2"){f++} $1=="version"&&$2~/^v[0-9][A-Za-z0-9._-]*$/{v++} END{exit f!=1||v!=1}' "$path/payload-manifest.tsv"
}

for mode in Vulkan DirectX11; do clean_mode "$ROOT/$mode"; done
if [ -d "$ROOT/Updater" ] || [ -L "$ROOT/Updater" ]; then
  if safe_path "$ROOT/Updater"; then clean_state "$ROOT/Updater/local"; remove_owned "$ROOT/Updater/.DS_Store"; finish_directory "$ROOT/Updater"; fi
fi

# Only names emitted by the v0.2/v0.3 installer and app are obsolete here.
# Current installer diagnostics, session directories and user logs stay intact.
if [ -d "$ROOT/logs" ] || [ -L "$ROOT/logs" ]; then
  if safe_path "$ROOT/logs"; then
    for log in "$ROOT/logs/"*; do
      [ -f "$log" ] && [ ! -L "$log" ] || continue
      name="$(basename "$log")"
      case "$name" in
        setup-Vulkan.log|setup-DirectX11.log|setup-updater.log|verify-Vulkan.log|verify-DirectX11.log|extract.log) remove_owned "$log";;
        *) if [[ "$name" =~ ^installer-[0-9]+\.log$ ]] || [[ "$name" =~ ^run-(Vulkan|DirectX11|Update)-[0-9]+\.log$ ]]; then remove_owned "$log"; fi;;
      esac
    done
  fi
fi

if [ -d "$ROOT/.runtime-backups" ] || [ -L "$ROOT/.runtime-backups" ]; then
  if safe_path "$ROOT/.runtime-backups"; then
    for backup in "$ROOT/.runtime-backups/"*; do
      [ -e "$backup" ] || [ -L "$backup" ] || continue
      safe_path "$backup" || continue
      name="$(basename "$backup")"
      if [[ "$name" =~ ^[0-9]{8}-[0-9]{6}-(Vulkan|DirectX11)-[0-9]+$ ]]; then
        clean_mode "$backup"
      elif [[ "$name" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]] && owned_snapshot "$backup"; then
        clean_recovery "$backup/Recovery"; clean_state "$backup/State"; clean_backup_apps "$backup/Apps"
        for item in run.sh common.sh .DS_Store; do remove_owned "$backup/$item"; done
        # Keep the ownership manifest while anything remains, allowing retry.
        remaining="$(/usr/bin/find -P "$backup" -mindepth 1 -maxdepth 1 ! -name payload-manifest.tsv ! -name .endfield-backup-v1 -print)" || { problem=1; continue; }
        if [ -z "$remaining" ]; then remove_owned "$backup/payload-manifest.tsv"; remove_owned "$backup/.endfield-backup-v1"; fi
        finish_directory "$backup"
      else
        warn "保留无法识别的备份：${backup#"$ROOT"/}"
      fi
    done
    remove_owned "$ROOT/.runtime-backups/.DS_Store"; finish_directory "$ROOT/.runtime-backups"
  fi
fi

# Old setup directories can contain a failed transaction or a still-relevant
# recovery copy. Never infer their ownership or liveness from a name alone.
for leftover in "$ROOT/.setup-work."*; do
  [ -e "$leftover" ] || [ -L "$leftover" ] || continue
  warn "保留以前安装中断的现场：${leftover#"$ROOT"/}"
done
printf '清理完成：已移除 %s 项旧内容（原目录占用约 %s MiB）；当前环境、游戏和官方启动器保留。\n' "$removed" "$((reclaimed_kb / 1024))"
exit "$problem"
