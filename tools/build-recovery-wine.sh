#!/bin/bash
# Rebuild one module family from its retained historical source variant.
# Does not install files, run Wine, or overwrite a playable environment.
set -euo pipefail
archive="${1:?Usage: build-recovery-wine.sh SOURCE.tar.xz MODULE NEW_OUTPUT_DIRECTORY [--check]}"
module="${2:?Module: ntdll, ntoskrnl, wineserver, winemac, kernel32, auth}"
output="${3:?Specify a new output directory}"
case "$module" in
  ntdll|ntoskrnl|wineserver|auth) variant="$module" ;;
  winemac|kernel32) variant=desktop ;;
  *) echo 'Unknown module' >&2; exit 2 ;;
esac
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
[ ! -e "$output" ] || { echo 'Output directory already exists' >&2; exit 1; }
mkdir -p "$output"
output="$(cd "$output" && pwd)"
tar -xf "$archive" -C "$output"
package="$output/Wine-11.16-Endfield-v0.4.0-recovery-source"
(cd "$package" && shasum -a 256 --check SOURCE-SHA256.txt > "$output/source-check.log")
source="$package/wine"
patch --batch -E -p1 -d "$source" -i "$package/variants/$variant.patch" > "$output/variant-patch.log"
(cd "$source" && shasum -a 256 --check "$package/variants/$variant-SHA256.txt" > "$output/variant-check.log")
if [ "${4:-}" = --check ]; then
  echo "Source and variant verified: $source"
  exit 0
fi
command -v x86_64-w64-mingw32-clang >/dev/null
command -v bison >/dev/null
export CC='/usr/bin/clang -arch x86_64' CXX='/usr/bin/clang++ -arch x86_64'
export MACOSX_DEPLOYMENT_TARGET=26.0
# SDK 27 advertises pipe2; retain the host-26 fallback used by the binaries.
export ac_cv_func_pipe2=no
flags=(--build=x86_64-apple-darwin25.6.0 --host=x86_64-apple-darwin25.6.0 --enable-win64 --disable-tests --without-x --without-gstreamer --without-gnutls --without-freetype --without-sdl --without-vulkan)
case "$module" in
  ntdll) flags+=(--enable-archs=x86_64 --enable-werror); targets=(dlls/ntdll/ntdll.so) ;;
  ntoskrnl) flags+=(--enable-archs=x86_64 --enable-werror); targets=(dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe) ;;
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
    targets=(programs/lsass/x86_64-windows/lsass.exe dlls/secur32/x86_64-windows/secur32.dll dlls/msv1_0/x86_64-windows/msv1_0.dll dlls/secur32/secur32.so dlls/msv1_0/msv1_0.so)
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
mkdir -p "$output/overlay/bin" "$output/overlay/lib/wine/x86_64-unix" "$output/overlay/lib/wine/x86_64-windows"
for target in "${targets[@]}"; do
  case "$target" in
    server/wineserver) destination="$output/overlay/bin/wineserver" ;;
    *.so) destination="$output/overlay/lib/wine/x86_64-unix/$(basename "$target")" ;;
    *) destination="$output/overlay/lib/wine/x86_64-windows/$(basename "$target")" ;;
  esac
  cp "$output/build/$target" "$destination"
  case "$target" in server/wineserver|*.so) codesign --force --sign - "$destination" ;; esac
done
printf 'Built %s: %s\n' "$module" "$output/overlay"
printf '%s\n' 'Rebuilding changes signatures/hashes. Validate independently and update runtime manifests before distribution.'
