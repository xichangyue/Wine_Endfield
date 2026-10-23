# 自行编译（Apple Silicon / 简体中文）

Release 的安装器已包含运行库，普通用户无需编译。v0.4.0 使用统一 Recovery 环境，要求 **macOS 26.0 或更新版本**及 Rosetta 2；不能通过修改版本号或 Mach-O load command 获得旧系统兼容性。

本教程重建项目修改的 Wine 模块和 MoltenVK。其余 Gcenx / DXMT 二进制沿用上游版本。构建输出不会自动覆盖现有安装。工具链、SDK、构建路径和签名会改变二进制哈希，本项目不承诺逐字节重现。

包内可选 Wine 媒体模块的部分 GStreamer / FFmpeg 依赖未随包提供；这些模块不在本教程的重建范围内，不能据游戏启动成功推断全部媒体解码功能可用。

## Wine 模块

从同一 Release 下载 `Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz`，并按 Release 的 `SHA256SUMS.txt` 校验。该附件包含完整 Wine 源码、五套历史变体、许可证、逐文件清单和构建脚本。不要使用旧版 `build-overlay.sh` 或 Vulkan/DirectX11 两套补丁重建本版。

运行库按模块组合：`ntdll`、`ntoskrnl`、`wineserver`、桌面桥接和认证模块各自采用不同的已验证源码树；脚本会恢复相应变体。具体映射见 [Recovery/source/README.zh-CN.md](Recovery/source/README.zh-CN.md) 和 `SOURCE-PROVENANCE.json`。

需要 Xcode Command Line Tools、GNU Bison 3.8.2+、[llvm-mingw 20260826 UCRT macOS universal](https://github.com/mstorsjo/llvm-mingw/releases/tag/20260826)、make、patch、tar、shasum、codesign。将 bison 和 llvm-mingw 的 `bin` 加入 `PATH`。Bison 若不在默认位置，还需设置 `BISON_PKGDATADIR`。目标为 x86_64 Windows / x86_64 macOS。

```bash
git clone https://github.com/xichangyue/Wine_Endfield.git
cd Wine_Endfield
git pull --ff-only
# 只解压、校验并恢复源码，不编译、不运行 Wine：
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz ntdll /新的输出路径/ntdll-check --check
# 实际编译，使用另一个新的输出目录：
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz ntdll /新的输出路径/ntdll
```

第二个参数可为 `ntdll`、`ntoskrnl`、`wineserver`、`winemac`、`kernel32`、`auth`。输出为该目录下的 `overlay/`，脚本不安装、不运行 Wine。源码包内已有聚合修改；不要重复应用 `wine-11.16-recovery.patch`。该补丁仅供审阅或对固定原始 Wine 11.16 基线应用，基线 SHA-256 记录在来源清单中。

`auth` 还需匹配运行库的 GnuTLS / FreeType 头文件、x86_64 库与 Vulkan-Headers。按本机依赖位置设置 `GNUTLS_CFLAGS`、`GNUTLS_LIBS`、`FREETYPE_CFLAGS`、`FREETYPE_LIBS`、`CPPFLAGS`、`LDFLAGS`，详见源码包 README。脚本将 GnuTLS 加载名固定为 `@loader_path/../../libgnutls.30.dylib`，不可写入个人电脑的绝对库路径。无需重编译未被替换的其他 Wine 模块。

脚本保留 macOS 26 部署目标和 `ac_cv_func_pipe2=no`，避免新 SDK 自动选用较高系统才提供的函数。已有 `msync.o` unused-function 警告仅在 ntdll 的该对象上放宽 Werror。历史实际构建参数、模块输出和本次便携加载配置见源码包 `MODULE-BUILD-RECORDS.json`；公开脚本是重建入口，不表示全部冻结二进制在本轮重新编译过。

## MoltenVK 与 SPIRV-Cross

游戏 Vulkan 路径使用项目修改的 **MoltenVK 1.4.2**。二进制和源码沿用 v0.3，因此附件名称保持不变：

```text
MoltenVK-1.4.2-Endfield-v0.3.0-source.tar.xz
SHA-256 b24254c87e0219cf32ce1282a3190aadce2f923c555ed49517e69df235a4aa84
```

附件包含修改后的 MoltenVK、SPIRV-Cross 和所有固定依赖源码及许可证，不含 Git 目录或编译产物。`SOURCE-MANIFEST.json` 列明提交，`SOURCE-SHA256.txt` 可逐文件校验。仓库中的 `Vulkan/source/moltenvk-1.4.2-endfield.patch` 与 `spirv-cross-device-barrier.patch` 供审阅，不能对附件再次应用。

需要已完成首次设置的完整 Xcode。先校验，再选择构建：

```bash
bash tools/build-moltenvk.sh /源码路径/MoltenVK-1.4.2-Endfield-v0.3.0-source.tar.xz --check
bash tools/build-moltenvk.sh /源码路径/MoltenVK-1.4.2-Endfield-v0.3.0-source.tar.xz
```

脚本使用上游模板的预生成 SPIRV-Tools 头文件，先编译依赖，再以 Release / macOS scheme 构建 MoltenVK。全程不联网，不运行 `fetchDependencies`，避免覆盖 SPIRV-Cross 修改。已发布 dylib SHA-256 为 `1cf987832fc970cd1ed842fadc3a68796c39d4c173209e6a1eee9b04ca8e554d`。

## DXMT

DXMT 的四个模块与官方 v0.80 二进制一致。附带 `dxmt-v0.80-source.tar.gz` 对应固定提交，但不含 Git 子模块及 LLVM 源码；这些依赖的固定版本、来源和上游构建流程见 `Recovery/source/GRAPHICS-PROVENANCE.json`。Wine 的 `winemac.so` 桥接由上面的 `winemac` 模块构建，不由 DXMT 源码包生成。

## 使用自己的构建

1. 正常退出游戏与官方启动器，确认 Wine 已结束。备份完整安装目录，尤其是 `State/`；安装器成功升级时会自动清理旧环境，不应将它当作长期回退备份。
2. 在独立安装副本中，将 Wine 构建输出的 `overlay/` 合并到 `Recovery/runtime/Wine Devel.app/Contents/Resources/wine/`。保持 ntdll 与 wineserver 的源码/ABI 配套。新 MoltenVK 单独放入 `lib/libMoltenVK.dylib`。
3. 对修改的 Mach-O 模块及 Wine App 重新签名，更新 `Recovery/version.json` 的相关 pins、`CORE-SHA256.txt`、`RUNTIME-SHA256.txt` 和 `PROFILE-SHA256.txt`；复制到 `State/prefix/drive_c/windows/system32/` 的配对 PE 也须一致。不要关闭校验后直接分发。
4. 在独立安装中验证初始化、官方启动器和游戏，再验证两个渲染模式。不要覆盖保留的可用目录或删除用户缓存来掩盖故障。

第三方来源和许可见 [THIRD_PARTY.md](THIRD_PARTY.md)。反馈请提供系统版本、硬件、渲染模式和脱敏日志，勿上传整个 Wine prefix。
