# 自行编译（Apple Silicon / 简体中文）

安装器已包含运行库，普通用户无需编译。v0.4 系列使用统一 Recovery 环境，要求 **macOS 26.0 或更新版本**及 Rosetta 2；不能通过修改版本号或 Mach-O load command 获得旧系统兼容性。v0.4.2-preview 更新了 ACE 运行模块，并沿用 private.1 已冻结的 MoltenVK 字节；对应源码附件与安装器一并发布。

本教程重建项目修改的 Wine 模块和 MoltenVK。其余 Gcenx / DXMT 二进制沿用上游版本。构建输出不会自动覆盖现有安装。工具链、SDK、构建路径和签名会改变二进制哈希，本项目不承诺逐字节重现。

包内可选 Wine 媒体模块的部分 GStreamer / FFmpeg 依赖未随包提供；这些模块不在本教程的重建范围内，不能据游戏启动成功推断全部媒体解码功能可用。

## Wine 模块

从 Release 下载 `Wine-11.16-Endfield-v0.4.2-private.3-source.tar.xz`，并使用 `SHA256SUMS.txt` 校验。附件保留最终候选名称，内容与公开运行库对应；其中包含完整 Wine 源码、五套历史变体、ACE 运行补丁、IPI/IRQL 契约补丁、Tace 服务宿主收敛补丁、许可证、逐文件清单和构建脚本。不要使用旧版 `build-overlay.sh` 或 Vulkan/DirectX11 两套补丁重建本版。

运行库按模块组合：`ntdll`、`ntoskrnl`、`wineserver`、桌面桥接和认证模块各自采用不同的已验证源码树；脚本会恢复相应变体。具体映射见 [Recovery/source/README.zh-CN.md](Recovery/source/README.zh-CN.md) 和 `SOURCE-PROVENANCE.json`。

需要 Xcode Command Line Tools、GNU Bison 3.8.2+、[llvm-mingw 20260826 UCRT macOS universal](https://github.com/mstorsjo/llvm-mingw/releases/tag/20260826)、make、patch、tar、shasum、codesign。将 bison 和 llvm-mingw 的 `bin` 加入 `PATH`。Bison 若不在默认位置，还需设置 `BISON_PKGDATADIR`。目标为 x86_64 Windows / x86_64 macOS。

```bash
git clone https://github.com/xichangyue/Wine_Endfield.git
cd Wine_Endfield
git pull --ff-only
# 只解压、校验并恢复源码，不编译、不运行 Wine：
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.2-private.3-source.tar.xz ntdll /新的输出路径/ntdll-check --check
# 实际编译，使用另一个新的输出目录：
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.2-private.3-source.tar.xz ntdll /新的输出路径/ntdll
```

第二个参数可为 `ntdll`、`ntoskrnl`、`ntoskrnl-ace`、`ace-runtime`、`ace-runtime-v2`、`ace-runtime-v3`、`wineserver`、`winemac`、`kernel32`、`auth`。输出为该目录下的 `overlay/`，脚本不安装、不运行 Wine。`ntoskrnl-ace` 保留早期三接口候选；`ace-runtime` 加入完整 ACE 运行补丁；`ace-runtime-v2` 再加入 IPI/IRQL 契约；private.3 使用 `ace-runtime-v3`，最后加入 Tace 服务宿主收敛补丁。三个 ACE 运行模块均输出 `ntoskrnl.exe`、`wineboot.exe` 和 `wine.inf`。源码包内已有聚合修改；不要重复应用 `wine-11.16-recovery.patch`。

三接口候选可先只校验源码：

```bash
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.2-private.3-source.tar.xz ntoskrnl-ace /新的输出路径/ntoskrnl-ace-check --check
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.2-private.3-source.tar.xz ace-runtime /新的输出路径/ace-runtime-check --check
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.2-private.3-source.tar.xz ace-runtime-v2 /新的输出路径/ace-runtime-v2-check --check
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.2-private.3-source.tar.xz ace-runtime-v3 /新的输出路径/ace-runtime-v3-check --check
```

完整候选增加 `KeIpiGenericCall`、`KeSetSystemGroupAffinityThread`、`KeRevertToUserGroupAffinityThread` 和 `MmCopyMemory`，并通过 `wine.inf`/`wineboot.exe` 注册和启动 `SamSs`。private.3 剥离前参考 SHA-256 为 `ntoskrnl.exe` `c31782815f1d5ab37c7da936ec2295af9cd3c3b38d9cd9e09d0da6cd42580726`、`wineboot.exe` `652087ba497444d0c028975fb837ac665f8c293cc6928adb5294c24b91cca5ae`、`wine.inf` `d1248be104eeb27fed9c1ed3849f46e28768fed24da6e9d7c72fce450a9cd409`。发行脚本会使用等字节长的中性源码路径，并在输出时删除 PE DWARF 与 Mach-O STABS。候选验证状态：通过。

`auth` 还需匹配运行库的 GnuTLS / FreeType 头文件、x86_64 库与 Vulkan-Headers。按本机依赖位置设置 `GNUTLS_CFLAGS`、`GNUTLS_LIBS`、`FREETYPE_CFLAGS`、`FREETYPE_LIBS`、`CPPFLAGS`、`LDFLAGS`，详见源码包 README。脚本将 GnuTLS 加载名固定为 `@loader_path/../../libgnutls.30.dylib`，并同时生成 LSA/RPC 模块和纯净 `sechost.dll`；不可写入个人电脑的绝对路径。

脚本保留 macOS 26 部署目标和 `ac_cv_func_pipe2=no`，避免新 SDK 自动选用较高系统才提供的函数。已有 `msync.o` unused-function 警告仅在 ntdll 的该对象上放宽 Werror。历史实际构建参数、模块输出和本次便携加载配置见源码包 `MODULE-BUILD-RECORDS.json`；公开脚本是重建入口，不表示全部冻结二进制在本轮重新编译过。

## MoltenVK 与 SPIRV-Cross

游戏 Vulkan 路径使用项目修改的 **MoltenVK 1.4.2**。本版沿用最终私测候选采用的 FineWine 终末地补丁，并加入近期上游描述符、纹理生命周期、参数缓冲重绑、命令缓冲资源保留和管线缓存匹配修复：

```text
MoltenVK-1.4.2-Endfield-v0.4.2-private.1-source.tar.xz
SHA-256 cfe6d1b10edb62f683a2729c5079ceaf97d99249803b115965924c1f264ad386
```

附件包含修改后的 MoltenVK、SPIRV-Cross 和所有固定依赖源码及许可证，不含 Git 目录或编译产物。`SOURCE-PROVENANCE.json` 列明提交与改动文件，`SOURCE-SHA256.txt` 可逐文件校验，`patches/` 保留相对固定上游提交的完整差异；不要对附件再次应用这些补丁。

需要已完成首次设置的完整 Xcode。先校验，再选择构建：

```bash
bash tools/build-moltenvk.sh /源码路径/MoltenVK-1.4.2-Endfield-v0.4.2-private.1-source.tar.xz --check
bash tools/build-moltenvk.sh /源码路径/MoltenVK-1.4.2-Endfield-v0.4.2-private.1-source.tar.xz
```

脚本使用上游模板的预生成 SPIRV-Tools 头文件，先编译 x86_64 依赖，再以 Release / macOS scheme 构建 MoltenVK。全程不联网，不运行 `fetchDependencies`，避免覆盖 SPIRV-Cross 修改。私测 dylib SHA-256 为 `b8a7cdde32010a3cfb93f4e20db8a020d0ef706e2a21241760b2bc98d4ef7561`。

## DXMT

DXMT 的四个模块与官方 v0.80 二进制一致。附带 `dxmt-v0.80-source.tar.gz` 对应固定提交，但不含 Git 子模块及 LLVM 源码；这些依赖的固定版本、来源和上游构建流程见 `Recovery/source/GRAPHICS-PROVENANCE.json`。Wine 的 `winemac.so` 桥接由上面的 `winemac` 模块构建，不由 DXMT 源码包生成。

## 使用自己的构建

1. 正常退出游戏与官方启动器，确认 Wine 已结束。备份完整安装目录，尤其是 `State/`；安装器成功升级时会自动清理旧环境，不应将它当作长期回退备份。
2. 在独立安装副本中，将 Wine 构建输出的 `overlay/` 合并到 `Recovery/runtime/Wine Devel.app/Contents/Resources/wine/`。保持 ntdll 与 wineserver 的源码/ABI 配套。新 MoltenVK 单独放入 `lib/libMoltenVK.dylib`。
3. 对修改的 Mach-O 模块及 Wine App 重新签名，更新 `Recovery/version.json` 的相关 pins、`CORE-SHA256.txt`、`RUNTIME-SHA256.txt` 和 `PROFILE-SHA256.txt`；复制到 `State/prefix/drive_c/windows/system32/` 的配对 PE 也须一致。不要关闭校验后直接分发。
4. 在独立安装中验证初始化、官方启动器和游戏，再验证两个渲染模式。不要覆盖保留的可用目录或删除用户缓存来掩盖故障。

第三方来源和许可见 [THIRD_PARTY.md](THIRD_PARTY.md)。反馈请提供系统版本、硬件、渲染模式和脱敏日志，勿上传整个 Wine prefix。
