# v0.4.0 修复运行库的 Wine 源码

本目录记录新版统一运行库的 Wine 变更。**不要使用 v0.3 的 `Vulkan/source/wine-11.16.patch` 或旧 DirectX11 补丁重建新版。** 从同一 Release 下载 `Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz`；其中包含完整 Wine 源码、许可证、逐文件校验、聚合补丁、各模块对应的历史源码变体以及构建脚本。

运行库是逐模块验证后冻结的组合，并非在最后一棵源码上一次构建的结果。源码包的 `wine/` 是所有已采用修改的完整源码集合；`variants/` 将它恢复到各模块实际使用的完整源码树。每个变体均与保留的历史源码逐文件核对，避免共享头文件和未采用的实验修改混入构建。

| 模块 | 构建时使用的源码变体 | 主要内容 |
| --- | --- | --- |
| `ntoskrnl.exe` | `ntoskrnl` | 内核兼容修复、MDL 映射、线程上下文 thunk |
| Unix `ntdll.so` | `ntdll` | MSync、映射语义、单 REX NOP 与上下文处理 |
| `wineserver` | `wineserver` | MSync 及 `SEC_IMAGE_NO_EXECUTE` 服务端映射 |
| `winemac.so` / `kernel32.dll` | `desktop` | DXMT 窗口桥接及已采用的基础模块修改 |
| `lsass.exe`、`secur32.dll/.so`、`msv1_0.dll/.so` | `auth` | 真正的 LSA/RPC 认证实现回移及生命周期修复 |

源码包包含新增认证服务的 IDL、构建定义和安装配置；它们不能仅靠最后的 `ntoskrnl` 源码目录获得。DXMT、MoltenVK 与其他第三方组件的源码、许可证和来源见仓库 `THIRD_PARTY.md`，不应误称为本 Wine 源码包的一部分。

## 构建

普通用户无需构建；发布的安装器已包含二进制。源码构建需要 Apple Silicon Mac、Rosetta 2、Xcode Command Line Tools、GNU Bison 3.8.2+、llvm-mingw 20260826 UCRT macOS universal、make、patch、tar、shasum、codesign。将 bison 和 llvm-mingw 的 `bin` 加入 `PATH`。Bison 若不在默认安装位置，还需设置 `BISON_PKGDATADIR`。

先校验下载的附件 SHA-256。以下脚本会在**新的输出目录**解压并校验完整源码，为所选模块应用对应变体，再构建到 `overlay/`。不会替换现有运行库或运行 Wine。

```bash
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz ntdll /输出路径/ntdll
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz ntoskrnl /输出路径/ntoskrnl
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz wineserver /输出路径/wineserver
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz winemac /输出路径/winemac
bash tools/build-recovery-wine.sh /源码路径/Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz kernel32 /输出路径/kernel32
```

附加 `--check` 只做解压、完整源码校验及变体恢复，不要求编译器，也不会运行 Wine。归档已经包含聚合修改，**不要对 `wine/` 再次应用 `wine-11.16-recovery.patch`**；该补丁仅用于审阅或对固定的原始 Wine 11.16 压缩包应用。原始压缩包 SHA-256 为 `2b6d5cff784cb774f7f17b9a640b123ca8361d89c4280c0021b70bb6f3cd1b1c`。

`auth` 构建还需要匹配 x86_64 运行库的 GnuTLS / FreeType 开发头文件、Vulkan-Headers 和库目录。按现有依赖位置设置 `GNUTLS_CFLAGS`、`GNUTLS_LIBS`、`FREETYPE_CFLAGS`、`FREETYPE_LIBS`、`CPPFLAGS`、`LDFLAGS` 后再传入 `auth`。这些是依赖路径，不是游戏或账号信息。构建输出保留当前二进制使用的模块布局。

本版 `secur32.so` 的 GnuTLS 动态加载位置使用 `@loader_path/../../libgnutls.30.dylib`，加载安装包内的配套库。该改动属于构建配置，认证 C 源码不变；公开构建脚本采用相同的相对路径。历史调试构建的个人目录不应被照搬进发行包。`SOURCE-PROVENANCE.json` 记录模块 SHA-256、所用变体和构建记录；`MODULE-BUILD-RECORDS.json` 区分历史实际构建与本次相对路径重建。

脚本保留 macOS 26 部署目标与 `ac_cv_func_pipe2=no`，防止新 SDK 自动选用只在更高系统可用的 `pipe2`；`ntdll` 仅对已有的 `msync.o` unused-function 警告放宽 Werror。完整工具版本、路径和签名会改变输出哈希，本项目不承诺逐字节重现。重新分发自行构建的运行库前，应重新签名、生成完整校验清单，并在独立安装目录验证初始化、官方启动器及游戏。
