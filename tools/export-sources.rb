#!/usr/bin/env ruby
# Generate variant patches against a pristine wine-wine-11.16 source tree.
require 'open3'
require 'fileutils'
abort 'usage: ruby export-sources.rb PRISTINE MODIFIED OUTPUT' unless ARGV.length == 3
original, modified, output = ARGV.map { |p| File.expand_path(p) }
files = %w[
 dlls/ntdll/Makefile.in dlls/ntdll/unix/loader.c dlls/ntdll/unix/msync.c
 dlls/ntdll/unix/msync.h dlls/ntdll/unix/sync.c dlls/ntdll/unix/signal_x86_64.c
 dlls/ntdll/unix/server.c dlls/ntoskrnl.exe/ntoskrnl.c
 dlls/ntoskrnl.exe/ntoskrnl_private.h dlls/ntoskrnl.exe/ntoskrnl.exe.spec
 dlls/kernel32/module.c server/token.c server/Makefile.in server/inproc_sync.c
 server/main.c server/msync.c server/msync.h server/protocol.def server/thread.c
 include/wine/server_protocol.h server/request_handlers.h server/request_trace.h
 dlls/winemac.drv/macdrv_main.c dlls/winemac.drv/macdrv_cocoa.h
 dlls/winemac.drv/cocoa_window.m dlls/winemac.drv/macdrv.h dlls/winemac.drv/window.c
]
%w[Vulkan DirectX11].each do |mode|
  patch = files.map do |file|
    next '' if mode == 'Vulkan' && file.start_with?('dlls/winemac.drv/')
    next '' if mode == 'DirectX11' && file == 'dlls/ntdll/unix/server.c'
    a = File.join(original, file)
    b = File.join(modified, file)
    a = '/dev/null' unless File.exist?(a)
    text, status = Open3.capture2('diff', '-u', '--label', "a/#{file}", '--label', "b/#{file}", a, b)
    abort "diff failed: #{file}" unless [0, 1].include?(status.exitstatus)
    text
  end.join
  FileUtils.mkdir_p(File.join(output, mode, 'source'))
  File.write(File.join(output, mode, 'source/wine-11.16.patch'), patch)
end
