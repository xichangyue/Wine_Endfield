# 自行编译（Apple Silicon / 简体中文）

Release 的一键安装器和完整运行时包可直接使用，无需本教程。当前发布保留已验证的二进制，Vulkan 与 DirectX11 的 Wine 模块都要求 **macOS 26.0 或更新版本**，并需要 Rosetta 2。不能通过修改版本号或 Mach-O load command 获得旧系统兼容性。

本教程重建项目修改的 Wine 模块和 Vulkan 的 MoltenVK；其余 Gcenx / DXMT 二进制保持上游版本。构建输出不会自动覆盖稳定包。不同 Xcode、SDK、链接器和签名会改变二进制哈希，本项目不承诺逐字节重现。

## Wine 模块

需要 Xcode Command Line Tools、GNU Bison 3.8.2+、[llvm-mingw 20260826 UCRT macOS universal](https://github.com/mstorsjo/llvm-mingw/releases/tag/20260826)、clang、make、patch、tar、shasum、codesign。将 bison 和 llvm-mingw 的 bin 目录加入 PATH。目标是 x86_64 Windows / x86_64 macOS，不要混用 ARM64 Windows 目标。

从同一 Release 下载 `wine-11.16-source.tar.gz`：

```text
SHA-256 2b6d5cff784cb774f7f17b9a640b123ca8361d89c4280c0021b70bb6f3cd1b1c
```

```bash
git clone https://github.com/xichangyue/Wine_Endfield.git
cd Wine_Endfield
git pull --ff-only
bash tools/build-overlay.sh Vulkan /源码路径/wine-11.16-source.tar.gz
# 或保留的 DirectX11 版本：
bash tools/build-overlay.sh DirectX11 /源码路径/wine-11.16-source.tar.gz
```

脚本在该模式的 `local/` 新建目录，解压固定基线并应用完整补丁，分别构建 ntdll、wineserver、kernel32 和 ntoskrnl。DirectX11 另建 winemac 双缓冲 / DXMT 窗口桥接；它保留原来的独立源码补丁，未包含本次 Vulkan 优化。

Vulkan 完整补丁包含 MSync、server reply 完整性检查、Darwin delay 分支及 MSync alert-slot 清理。`Vulkan/source/SOURCE-PROVENANCE.json` 记录对应源文件 SHA。无需再叠加旧版零散补丁，两模式补丁也不能互相叠加。

## Vulkan 的 MoltenVK 与 SPIRV-Cross

本版 Vulkan 使用项目修改的 **MoltenVK 1.4.2**，不再是官方未修改的 dylib。Release 同时提供：

```text
MoltenVK-1.4.2-Endfield-v0.3.0-source.tar.xz
SHA-256 b24254c87e0219cf32ce1282a3190aadce2f923c555ed49517e69df235a4aa84
```

该附件已经包含修改后的 MoltenVK、SPIRV-Cross，以及所有固定的上游依赖源码和许可证，不包含 Git 目录或编译产物。`SOURCE-MANIFEST.json` 列明各组件提交；`SOURCE-SHA256.txt` 可逐文件校验。主仓库中的两个 patch 用于审阅变更：

- `Vulkan/source/moltenvk-1.4.2-endfield.patch`：相对 MoltenVK 提交 `db66022459ffb663aa2b50f6b018bc2e124f5edf`。
- `Vulkan/source/spirv-cross-device-barrier.patch`：相对 SPIRV-Cross 提交 `6c09849fe88c48eaed08413aa022aaa136a3a057`。

附件已应用上述补丁，**不要再应用一次**。需要已完成首次设置的完整 Xcode。先校验，再选择编译：

```bash
bash tools/build-moltenvk.sh /源码路径/MoltenVK-1.4.2-Endfield-v0.3.0-source.tar.xz --check
bash tools/build-moltenvk.sh /源码路径/MoltenVK-1.4.2-Endfield-v0.3.0-source.tar.xz
```

脚本在新目录校验源码，使用上游模板的预生成 SPIRV-Tools 头文件，先编译并打包依赖，再以 Release / macOS scheme 构建 MoltenVK。全程不联网，也不运行 `fetchDependencies`，避免其 checkout 覆盖 SPIRV-Cross 的修改。

本轮核对了全部 28 个 MoltenVK 修改文件与 9 月 18–19 日的构建冻结记录；它们对应已验证 dylib SHA `1cf987832fc970cd1ed842fadc3a68796c39d4c173209e6a1eee9b04ca8e554d` 的源码链。本次发布没有重新编译该已验证二进制。软件绘制网页的 `WINEQT_QUICK_BACKEND=software` 属于启动配置，不是游戏着色器补丁。

## 使用自己的构建

1. 退出整个游戏和官方启动器，确认该运行时的 Wine 进程结束。保留整份发行包与原有 `local/` 数据作为备份。
2. 将 Wine 构建输出的 `overlay/` 合并到预编译包的 `runtime/Wine Devel.app/Contents/Resources/wine/`。ntdll 与 wineserver 必须作为同一套模块替换。MoltenVK 的新 dylib 单独放到该目录的 `lib/libMoltenVK.dylib`。
3. 按需要对修改模块及 Wine App 重新签名，重新生成该模式的 `RUNTIME-SHA256.txt`。自己的签名会改变模块哈希，也需要同步启动脚本的固定校验值；不要跳过校验后直接分发。
4. 使用独立的新安装目录验证初始化、登录、大世界、转视角、传送、网页和返回登录页；不要覆盖保留的稳定目录或删除用户缓存来掩盖故障。

第三方依赖来源和许可见 `THIRD_PARTY.md`。反馈时提供系统版本、硬件、渲染模式和脱敏日志，勿上传整个 Wine prefix。
