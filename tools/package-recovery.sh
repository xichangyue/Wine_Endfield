#!/bin/bash
# Build the locally verified recovery runtime without any Wine prefix or game data.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FROZEN="${1:?提供固定版目录（含 runtime、environment.json 和 version.json）}"
OUT="${2:?提供新的输出目录}"
VERSION="${3:-v0.4.0-recovery}"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || { echo '版本号格式无效' >&2; exit 2; }
FROZEN="$(cd "$FROZEN" && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
TARGET="$OUT/Wine_Endfield-Recovery-$VERSION.tar.xz"
[ ! -e "$TARGET" ] || { echo "输出已存在，拒绝覆盖：$TARGET" >&2; exit 1; }
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/endfield-recovery-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
PAYLOAD="$STAGE/Recovery"
mkdir -p "$PAYLOAD/runtime" "$PAYLOAD/bin" "$PAYLOAD/licenses"

# Verify the entire frozen app, including links, before copying it to the package.
python3 - "$FROZEN" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
app = root / 'runtime/Wine Devel.app'
assert app.is_dir() and not app.is_symlink(), 'Missing physical frozen Wine app'
records = {r['path']: r for r in json.loads((root / 'runtime-manifest.json').read_text())['files']
           if r['path'].startswith('Wine Devel.app/')}
seen = set()
for p in app.rglob('*'):
    relative = str(p.relative_to(root / 'runtime'))
    if p.is_symlink():
        assert p.resolve(strict=True).is_relative_to(app.resolve()), f'External runtime link: {relative}'
        assert records[relative].get('symlink') == p.readlink().as_posix(), f'Changed link: {relative}'
    elif p.is_file():
        assert hashlib.sha256(p.read_bytes()).hexdigest() == records[relative].get('sha256'), f'Changed file: {relative}'
    elif p.is_dir():
        continue
    else:
        raise RuntimeError(f'Unsupported runtime entry: {relative}')
    seen.add(relative)
assert seen == set(records), 'Frozen runtime inventory mismatch'
version = json.loads((root / 'version.json').read_text())
for relative, digest in version['pins'].items():
    p = root / version['runtime_relative'] / relative
    assert hashlib.sha256(p.read_bytes()).hexdigest() == digest, f'Pin mismatch: {relative}'
print(f'Frozen runtime verified: {len(seen)} files and links')
PY

/usr/bin/ditto --noextattr --norsrc "$FROZEN/runtime/Wine Devel.app" "$PAYLOAD/runtime/Wine Devel.app"
cp "$REPO/Vulkan/bin/7zz" "$PAYLOAD/bin/7zz"
/usr/bin/ditto --noextattr --norsrc "$REPO/Vulkan/licenses" "$PAYLOAD/licenses"
/usr/bin/ditto --noextattr --norsrc "$REPO/DirectX11/licenses" "$PAYLOAD/licenses"
/usr/bin/ditto --noextattr --norsrc "$REPO/Recovery/licenses" "$PAYLOAD/licenses"
cp "$FROZEN/version.json" "$PAYLOAD/version.json"
cp "$REPO/DirectX11/fonts.reg" "$PAYLOAD/fonts.reg"
cp "$REPO/LICENSE" "$PAYLOAD/licenses/Installer-MIT.txt"
cat > "$PAYLOAD/PACKAGE-NOTICE.txt" <<'EOF'
Endfield Mac recovery runtime — v0.4.0-recovery

This package contains the locally verified Wine compatibility runtime and the
unmodified 7-Zip utility. It contains no game, official launcher, Wine prefix,
account data, user cache, or private session logs.

Wine and its modified components remain under LGPL-2.1-or-later. MoltenVK and
SPIRV-Cross retain Apache-2.0 and their dependencies' original licenses. DXMT
retains MIT and its dependencies' licenses. 7-Zip retains its upstream LGPL,
BSD and unRAR terms. See licenses/ and the original upstream distributions.

Corresponding source is provided with this release:
  Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz
  MoltenVK-1.4.2-Endfield-v0.3.0-source.tar.xz
  dxmt-v0.80-source.tar.gz
  7z2603-src.tar.xz

https://github.com/xichangyue/Wine_Endfield/releases/tag/v0.4.0-recovery

The Wine source archive contains the complete modified source, module-specific
source variants, build instructions and provenance. The earlier v0.3 Wine
patches do not describe all binaries in this release. MoltenVK is unchanged
from the project's v0.3 release; DXMT and 7-Zip retain their upstream bytes.
Additional upstream dependencies, sources and license terms are documented in
the repository's THIRD_PARTY.md and Recovery/source/ provenance records.
EOF

python3 - "$FROZEN" "$PAYLOAD" <<'PY'
import hashlib, json, pathlib, re, shlex, sys
frozen, payload = map(pathlib.Path, sys.argv[1:])
environment = json.loads((frozen / 'environment.json').read_text())
lines = ['#!/bin/bash', '# Generated from the verified frozen environment; SESSION is supplied by run.sh.']
for key, value in environment.items():
    assert re.fullmatch('[A-Z][A-Z0-9_]*', key), key
    if '__SESSION__' in value:
        assert value.startswith('__SESSION__/') and value.count('__SESSION__') == 1, value
        suffix = value[len('__SESSION__'):]
        assert re.fullmatch('/[A-Za-z0-9_./-]+', suffix), value
        encoded = '"${SESSION:?SESSION is required}' + suffix + '"'
    else:
        encoded = shlex.quote(value)
    lines.append(f'export {key}={encoded}')
(payload / 'environment.sh').write_text('\n'.join(lines) + '\n')
version = json.loads((frozen / 'version.json').read_text())
(payload / 'CORE-SHA256.txt').write_text(''.join(f'{digest}  ./{relative}\n'
                                             for relative, digest in version['pins'].items()))
checksums = []
for path in sorted((payload / 'runtime').rglob('*')):
    if path.is_symlink():
        assert path.resolve(strict=True).is_relative_to(payload.resolve()), str(path)
    elif path.is_file():
        relative = path.relative_to(payload / 'runtime').as_posix()
        assert '\n' not in relative and '\r' not in relative and '\\' not in relative
        checksums.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  ./{relative}')
(payload / 'RUNTIME-SHA256.txt').write_text('\n'.join(checksums) + '\n')
(payload / 'PROFILE-SHA256.txt').write_text(''.join(
    f'{hashlib.sha256((payload / name).read_bytes()).hexdigest()}  ./{name}\n'
    for name in ('environment.sh', 'fonts.reg', 'version.json', 'CORE-SHA256.txt')))
print(f'Packaged {len(environment)} environment settings; {len(checksums)} runtime file hashes')
PY

(cd "$PAYLOAD/runtime" && shasum -a 256 -c ../RUNTIME-SHA256.txt > /dev/null)
bash -n "$PAYLOAD/environment.sh"
PARTIAL="$STAGE/payload.tar.xz"
if command -v xz >/dev/null 2>&1; then
  COPYFILE_DISABLE=1 /usr/bin/tar -cf - -C "$STAGE" Recovery | xz -T2 -3 > "$PARTIAL"
else
  COPYFILE_DISABLE=1 /usr/bin/tar -cJf "$PARTIAL" -C "$STAGE" Recovery
fi
# Stage and rename only after archive creation succeeds, so a failed build is retryable.
mv "$PARTIAL" "$TARGET"
(cd "$OUT" && shasum -a 256 "$(basename "$TARGET")" > "$(basename "$TARGET").sha256")
echo "$TARGET"
