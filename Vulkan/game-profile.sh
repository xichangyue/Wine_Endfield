#!/bin/bash
# Current user-tested Vulkan profile. Shared by the .command and installer apps.
# Independent script code: MIT. Runtime components keep their original licenses.
profile_require() {
  local file="$1" expected="$2" actual
  [ -f "$file" ] || { echo "运行时文件缺失：$file" >&2; return 1; }
  actual="$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')"
  [ "$actual" = "$expected" ] || { echo "运行时版本不匹配，请重新解压同版本完整包：$file" >&2; return 1; }
}
game_environment() {
  local PREFIX="$STATE/prefix" CAPTURE_PARENT CAPTURE_RUN validation_option
  profile_require "$WINE_ROOT/bin/wine" 14b1fe57c9aabf12419948a1f8670b1ad0eae1b8346ff4388a9bdc8313d08463 || return
  profile_require "$WINE_ROOT/lib/wine/x86_64-unix/ntdll.so" 329bd2cdb98b0e40546a3373a7c6372df90aea3dd3ffef5b85aa2d1e71439e12 || return
  profile_require "$WINE_ROOT/lib/libMoltenVK.dylib" 1cf987832fc970cd1ed842fadc3a68796c39d4c173209e6a1eee9b04ca8e554d || return
  # Wine synchronization and renderer correctness fixes retained from the accepted run.
  export ENDFIELD_REPLY_INTEGRITY=1
  export ENDFIELD_RESOURCE_COMPAT_TEST=0
  export ENDFIELD_COPY_RESOURCE_USAGE=1
  export ENDFIELD_FULLSCREEN_COPY_RESOURCE_USAGE=1
  export ENDFIELD_DEVICE_BARRIER_TEST=1
  export ENDFIELD_DARWIN_LONG_DELAY_ONLY=1
  export ENDFIELD_DARWIN_DELAY_CHUNKS=0
  export ENDFIELD_DEFER_COLD_MTL_LIBRARY=1
  export ENDFIELD_ENCODER_ANNOTATIONS=0
  export ENDFIELD_FRAME_TIMING=0
  export ENDFIELD_TARGET_UBO_DIAGNOSTICS=0
  export ENDFIELD_TARGET_RESOURCE_DIAGNOSTICS=1

  # Preserve the five diagnostics enabled in the accepted run; other collectors stay off.
  export ENDFIELD_GPU_FAULT_BREADCRUMBS=1
  export ENDFIELD_GPU_ERROR_DETAILS=1
  export ENDFIELD_RENDER_LABELS=1
  export ENDFIELD_COMPUTE_LABELS=1
  export ENDFIELD_BATCH_ENCODER_LABELS=0
  export ENDFIELD_COMPILE_TIMING=0
  export ENDFIELD_SERVER_FD_DIAGNOSTICS=0
  export ENDFIELD_DELAY_DIAGNOSTICS=0
  unset ENDFIELD_GPU_FAULT_BREADCRUMBS_PATH ENDFIELD_RENDER_DUMP_DIR ENDFIELD_COMPUTE_DUMP_DIR
  unset ENDFIELD_COMPILE_TIMING_PATH ENDFIELD_FRAME_TIMING_PATH
  unset ENDFIELD_TARGET_UBO_DIAGNOSTICS_PATH ENDFIELD_TARGET_RESOURCE_DIAGNOSTICS_PATH
  unset ENDFIELD_UBO_RUN_DIR ENDFIELD_PREWARM_WRAPPER_PID ENDFIELD_PREWARM_SHADER_HASHES

  export WINEPREFIX="$PREFIX" WINEMSYNC=1
  export WINEDEBUG=-all,err+all WINEDLLOVERRIDES='vulkan-1,winevulkan=b'
  export MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION=0
  export MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1
  export MVK_CONFIG_PERFORMANCE_TRACKING=0
  export MVK_CONFIG_USE_MTLHEAP=0
  export MTL_DEBUG_LAYER=0
  for validation_option in ${!MTL_SHADER_VALIDATION_@}; do
    unset "$validation_option"
  done
  unset validation_option
  export MTL_SHADER_VALIDATION=0

  # Keep the dormant on-demand capture configuration used by the accepted run.
  # A prior capture-disabled control froze at login, so that change is not promoted.
  export MTL_CAPTURE_ENABLED=1
  export MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE=3
  export MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_FAMILY_INDEX=0
  export MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_INDEX=0
  CAPTURE_PARENT="$STATE/logs/vulkan-runs"
  mkdir -p "$CAPTURE_PARENT"
  CAPTURE_RUN="$(/usr/bin/mktemp -d "$CAPTURE_PARENT/run-XXXXXX")"
  export MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE="$CAPTURE_RUN/frame.gputrace"
  export ENDFIELD_GPU_FAULT_BREADCRUMBS_PATH="$CAPTURE_RUN/gpu-fault-breadcrumbs.jsonl"
  export ENDFIELD_TARGET_RESOURCE_DIAGNOSTICS_PATH="$CAPTURE_RUN/target-resource.jsonl"

  unset MVK_CONFIG_SHADER_DUMP_DIR MVK_CONFIG_LIVE_CHECK_ALL_RESOURCES
  unset MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS
  unset MVK_CONFIG_FAST_MATH_ENABLED
  unset DXMT_CONFIG DXMT_CONFIG_FILE DXMT_METALFX_SPATIAL_SWAPCHAIN
  unset MTL_HUD_ENABLED MTL_HUD_LOG_ENABLED MTL_HUD_LOG_SHADER_ENABLED
  unset QT_QUICK_BACKEND QT_OPENGL QTWEBENGINE_CHROMIUM_FLAGS
  unset DYLD_PRINT_LIBRARIES DYLD_PRINT_LIBRARIES_POST_LAUNCH

  # Import into the Windows Qt environment; Unix QT_* is ignored by Wine.
  # Retain the software scenegraph after the confirmed webpage rendering test.
  export WINEQT_QUICK_BACKEND=software
}
