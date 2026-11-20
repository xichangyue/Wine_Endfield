#!/bin/bash
# Rebuild one module family from its retained historical source variant.
# Build paths are mapped to a neutral source root and debug-only path records
# are removed before staging. The script does not install files, run Wine, or
# overwrite a playable environment.
set -euo pipefail
archive="${1:?Usage: build-recovery-wine.sh SOURCE.tar.xz MODULE NEW_OUTPUT_DIRECTORY [--check]}"
module="${2:?Module: ntdll, ntoskrnl, ntoskrnl-ace, ace-runtime, ace-runtime-v2, ace-runtime-v3, wineserver, winemac, kernel32, auth}"
output="${3:?Specify a new output directory}"
case "$module" in
  ntdll|ntoskrnl|wineserver|auth) variant="$module" ;;
  ntoskrnl-ace|ace-runtime|ace-runtime-v2|ace-runtime-v3) variant=ntoskrnl ;;
  winemac|kernel32) variant=desktop ;;
  *) echo 'Unknown module' >&2; exit 2 ;;
esac
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
[ ! -e "$output" ] || { echo 'Output directory already exists' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
tar -xf "$archive" -C "$output"
package=''
for entry in "$output"/*; do
  [ -d "$entry" ] || continue
  [ -z "$package" ] || { echo 'Source archive must contain one top-level directory' >&2; exit 1; }
  package="$entry"
done
[ -n "$package" ] && [ -f "$package/SOURCE-SHA256.txt" ] && [ -d "$package/wine" ] || {
  echo 'Source archive layout is invalid' >&2
  exit 1
}
(cd "$package" && shasum -a 256 --check SOURCE-SHA256.txt > "$output/source-check.log")
source="$package/wine"
case "$source" in
  *[[:space:]]*)
    echo 'Source/output path must not contain whitespace; compiler prefix-map flags cannot encode it safely' >&2
    exit 1
    ;;
esac
patch --batch -E -p1 -d "$source" -i "$package/variants/$variant.patch" > "$output/variant-patch.log"
(cd "$source" && shasum -a 256 --check "$package/variants/$variant-SHA256.txt" > "$output/variant-check.log")
if [ "$module" = ntoskrnl-ace ]; then
  compat="$package/compat"
  [ -f "$compat/ace-core-three-imports.patch" ] || compat="$script_dir/../Recovery/source/compat"
  compat_patch="$compat/ace-core-three-imports.patch"
  compat_manifest="$compat/ace-core-three-imports-SHA256.txt"
  [ "$(shasum -a 256 "$compat_patch" | awk '{print $1}')" = c53d424e19171dc870c03ddf1fe5e98d52c483375893083e4c5edac867743ccf ] || {
    echo 'ACE compatibility patch hash mismatch' >&2
    exit 1
  }
  [ "$(shasum -a 256 "$compat_manifest" | awk '{print $1}')" = a9bdbb80b1b6853df964a0ac732acab52527c9e188965d150b40bd9f20b6c763 ] || {
    echo 'ACE compatibility source manifest hash mismatch' >&2
    exit 1
  }
  patch --batch -E -p1 -d "$source" -i "$compat_patch" > "$output/ace-compat-patch.log"
  (cd "$source" && shasum -a 256 --check "$compat_manifest" > "$output/ace-compat-check.log")
fi
if [ "$module" = ace-runtime ] || [ "$module" = ace-runtime-v2 ] || [ "$module" = ace-runtime-v3 ]; then
  compat="$package/compat"
  [ -f "$compat/ace-core-runtime.patch" ] || compat="$script_dir/../Recovery/source/compat"
  compat_patch="$compat/ace-core-runtime.patch"
  compat_manifest="$compat/ace-core-runtime-SHA256.txt"
  [ "$(shasum -a 256 "$compat_patch" | awk '{print $1}')" = 19ca95a6e767cc0b9920433f632da5895baab012b018039c6c5f5a1a0436edad ] || {
    echo 'ACE runtime compatibility patch hash mismatch' >&2
    exit 1
  }
  [ "$(shasum -a 256 "$compat_manifest" | awk '{print $1}')" = 59f41ace0c11e93283eb7259f8a30a4c77028bb67d825a015739a61048f913f4 ] || {
    echo 'ACE runtime source manifest hash mismatch' >&2
    exit 1
  }
  patch --batch -E -p1 -d "$source" -i "$compat_patch" > "$output/ace-runtime-patch.log"
  (cd "$source" && shasum -a 256 --check "$compat_manifest" > "$output/ace-runtime-check.log")
fi
if [ "$module" = ace-runtime-v2 ] || [ "$module" = ace-runtime-v3 ]; then
  compat="$package/compat"
  [ -f "$compat/ace-ipi-contract.patch" ] || compat="$script_dir/../Recovery/source/compat"
  compat_patch="$compat/ace-ipi-contract.patch"
  compat_manifest="$compat/ace-ipi-contract-SHA256.txt"
  [ "$(shasum -a 256 "$compat_patch" | awk '{print $1}')" = 2c980623d8b18d4dac4ca6c38fe5db6f6e6987f1b9108de8c096c84f1fbda87e ] || {
    echo 'ACE IPI compatibility patch hash mismatch' >&2
    exit 1
  }
  [ "$(shasum -a 256 "$compat_manifest" | awk '{print $1}')" = 08762d7277e6ae5395ac180e3b70257f152d8e40d51b0e69d68bd1eef81d25dd ] || {
    echo 'ACE IPI compatibility source manifest hash mismatch' >&2
    exit 1
  }
  patch --batch -E -p1 -d "$source" -i "$compat_patch" > "$output/ace-ipi-patch.log"
  (cd "$source" && shasum -a 256 --check "$compat_manifest" > "$output/ace-ipi-check.log")
fi
if [ "$module" = ace-runtime-v3 ]; then
  compat="$package/compat"
  [ -f "$compat/ace-tace-service-host.patch" ] || compat="$script_dir/../Recovery/source/compat"
  compat_patch="$compat/ace-tace-service-host.patch"
  compat_manifest="$compat/ace-tace-service-host-SHA256.txt"
  [ "$(shasum -a 256 "$compat_patch" | awk '{print $1}')" = 4c0ba86568ba2bfeb3ae39accbfcf165979c35b74a9a7841dfb1a12e98f2919d ] || {
    echo 'ACE Tace service-host patch hash mismatch' >&2
    exit 1
  }
  [ "$(shasum -a 256 "$compat_manifest" | awk '{print $1}')" = 41d15d258aa8d74cb820d1fc42329f098c73ccab3eaf8a975928190c6af728c5 ] || {
    echo 'ACE Tace service-host source manifest hash mismatch' >&2
    exit 1
  }
  patch --batch -E -p1 -d "$source" -i "$compat_patch" > "$output/ace-tace-service-host-patch.log"
  (cd "$source" && shasum -a 256 --check "$compat_manifest" > "$output/ace-tace-service-host-check.log")
fi
if [ "${4:-}" = --check ]; then
  echo "Source and variant verified: $source"
  exit 0
fi
command -v x86_64-w64-mingw32-clang >/dev/null
command -v x86_64-w64-mingw32-strip >/dev/null
command -v bison >/dev/null
export CC='/usr/bin/clang -arch x86_64' CXX='/usr/bin/clang++ -arch x86_64'
export MACOSX_DEPLOYMENT_TARGET=26.0
# Do not embed the archive extraction directory or the builder's account name
# in DWARF/STABS records, __FILE__ strings, or critical-section diagnostics.
# Keep the mapped prefix byte length unchanged so diagnostic string replacement
# cannot move PE read-only data and its code references.
source_bytes="$(LC_ALL=C printf '%s' "$source" | wc -c | tr -d ' ')"
neutral_base='/usr/src/wine/'
neutral_bytes="$(LC_ALL=C printf '%s' "$neutral_base" | wc -c | tr -d ' ')"
[ "$source_bytes" -ge "$neutral_bytes" ] || { echo 'Source path is too short for path mapping' >&2; exit 1; }
neutral_padding="$(printf '%*s' "$((source_bytes - neutral_bytes))" '' | tr ' ' _)"
neutral_source="$neutral_base$neutral_padding"
path_map="-ffile-prefix-map=$source=$neutral_source -fdebug-prefix-map=$source=$neutral_source -fmacro-prefix-map=$source=$neutral_source"
export CFLAGS="${CFLAGS:--O2} $path_map"
export CXXFLAGS="${CXXFLAGS:--O2} $path_map"
# SDK 27 advertises pipe2; retain the host-26 fallback used by the binaries.
export ac_cv_func_pipe2=no
flags=(--build=x86_64-apple-darwin25.6.0 --host=x86_64-apple-darwin25.6.0 --enable-win64 --disable-tests --without-x --without-gstreamer --without-gnutls --without-freetype --without-sdl --without-vulkan)
case "$module" in
  ntdll) flags+=(--enable-archs=x86_64 --enable-werror); targets=(dlls/ntdll/ntdll.so) ;;
  ntoskrnl|ntoskrnl-ace) flags+=(--enable-archs=x86_64 --enable-werror); targets=(dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe) ;;
  ace-runtime|ace-runtime-v2|ace-runtime-v3)
    flags+=(--enable-archs=x86_64 --enable-werror)
    targets=(dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe programs/wineboot/x86_64-windows/wineboot.exe loader/wine.inf)
    ;;
  wineserver) flags+=(--enable-archs=none); targets=(server/wineserver) ;;
  winemac) flags+=(--enable-archs=none); targets=(dlls/winemac.drv/winemac.so) ;;
  kernel32) flags+=(--enable-archs=x86_64); targets=(dlls/kernel32/x86_64-windows/kernel32.dll) ;;
  auth)
    : "${GNUTLS_CFLAGS:?Set GNUTLS_CFLAGS for the GnuTLS headers}"
    : "${GNUTLS_LIBS:?Set GNUTLS_LIBS for the matching x86_64 GnuTLS library}"
    : "${FREETYPE_CFLAGS:?Set FREETYPE_CFLAGS for FreeType headers}"
    : "${FREETYPE_LIBS:?Set FREETYPE_LIBS for the matching x86_64 FreeType library}"
    : "${CPPFLAGS:?Set CPPFLAGS to the Vulkan-Headers include path}"
    : "${LDFLAGS:?Set LDFLAGS to the matching runtime library directory}"
    export ac_cv_lib_soname_gnutls='@loader_path/../../libgnutls.30.dylib'
    export ac_cv_lib_soname_freetype='@loader_path/../../libfreetype.6.dylib'
    export ac_cv_lib_soname_vulkan='@loader_path/../../libvulkan.1.4.350.dylib'
    flags=(--build=x86_64-apple-darwin25.6.0 --host=x86_64-apple-darwin25.6.0 --enable-win64 --enable-archs=x86_64 --disable-tests --with-vulkan --with-coreaudio --with-freetype --with-gnutls --without-x --without-wayland --without-gstreamer --without-sdl --prefix="$output/install")
    targets=(programs/lsass/x86_64-windows/lsass.exe dlls/secur32/x86_64-windows/secur32.dll dlls/msv1_0/x86_64-windows/msv1_0.dll dlls/sechost/x86_64-windows/sechost.dll dlls/secur32/secur32.so dlls/msv1_0/msv1_0.so)
    ;;
esac
mkdir "$output/build"
(cd "$output/build" && "$source/configure" "${flags[@]}") > "$output/configure.log" 2>&1
if [ "$module" = ntdll ]; then
  printf '%s\n' 'dlls/ntdll/unix/msync.o: CFLAGS += -Wno-error=unused-function' > "$output/build-overrides.mk"
  make -C "$output/build" -f Makefile -f "$output/build-overrides.mk" -j4 "${targets[@]}" > "$output/build.log" 2>&1
else
  make -C "$output/build" -j4 "${targets[@]}" > "$output/build.log" 2>&1
fi
mkdir -p "$output/overlay/bin" "$output/overlay/lib/wine/x86_64-unix" "$output/overlay/lib/wine/x86_64-windows" "$output/overlay/share/wine"
for target in "${targets[@]}"; do
  case "$target" in
    server/wineserver) destination="$output/overlay/bin/wineserver" ;;
    loader/wine.inf) destination="$output/overlay/share/wine/wine.inf" ;;
    *.so) destination="$output/overlay/lib/wine/x86_64-unix/$(basename "$target")" ;;
    *) destination="$output/overlay/lib/wine/x86_64-windows/$(basename "$target")" ;;
  esac
  cp "$output/build/$target" "$destination"
  case "$target" in
    server/wineserver|*.so)
      /usr/bin/strip -S "$destination"
      codesign --force --sign - "$destination"
      ;;
    loader/wine.inf) ;;
    *) x86_64-w64-mingw32-strip --strip-debug "$destination" ;;
  esac
done
printf 'Built %s: %s\n' "$module" "$output/overlay"
printf '%s\n' 'Rebuilding changes signatures/hashes. Validate independently and update runtime manifests before distribution.'
