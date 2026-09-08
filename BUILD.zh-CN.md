# 自行编译教程（Apple Silicon / 简体中文）

优先使用 Release 的预编译包。以下是重新编译本项目修改过的 Wine 模块的备用流程，不是从零重建 Gcenx 所有第三方依赖的教程；Wine 构建系统会检查工具版本。构建脚本不自动覆盖稳定包。

## 1. 准备工具

- 安装 Apple Xcode Command Line Tools：在终端运行 `xcode-select --install` 并按系统提示完成。
- 准备 GNU Bison 3.8.2 或更新版本（macOS 自带的旧 Bison 不够），将其 bin 目录加入 PATH。本机编译使用 Bison 3.8.2。
- 下载 [llvm-mingw 20260826](https://github.com/mstorsjo/llvm-mingw/releases/tag/20260826) 的 `llvm-mingw-20260826-ucrt-macos-universal.tar.xz`，解压后将其 bin 目录加入 PATH。
- 安装 Rosetta 2。需可用的 clang、make、patch、tar、shasum、codesign。不要混用 ARM64 Windows 编译目标，目标为 x86_64 Windows。

例如（把占位路径换成真实路径）：

```bash
export PATH="/你的路径/bison/bin:/你的路径/llvm-mingw/bin:$PATH"
bison --version
x86_64-w64-mingw32-clang --version
```

若自编译 Bison 提示找不到 skeleton/m4 资源，设置 `BISON_PKGDATADIR` 为该 Bison 安装目录中的 `share/bison`。

## 2. 获取仓库与对应源码

```bash
git clone https://github.com/xichangyue/Wine_Endfield.git
cd Wine_Endfield
git pull --ff-only
```

从同一 Release 下载 `wine-11.16-source.tar.gz`，其 SHA-256 必须是：

```text
2b6d5cff784cb774f7f17b9a640b123ca8361d89c4280c0021b70bb6f3cd1b1c
```

这份源码基线为 Wine 11.16。不要对其他版本硬套补丁，也不要同时叠加两个目录的补丁。

## 3. 编译对应版本

```bash
bash tools/build-overlay.sh Vulkan /源码下载路径/wine-11.16-source.tar.gz
# 或：
bash tools/build-overlay.sh DirectX11 /源码下载路径/wine-11.16-source.tar.gz
```

脚本新建带时间戳的工作目录，解压源码、应用该版本完整补丁，然后构建 ntdll、wineserver、kernel32 和 ntoskrnl。DirectX11 额外构建 winemac 双缓冲及 DXMT 窗口桥接。输出目录会在完成时显示。

Vulkan 保留上游 winemac，包含故障时的 server reply 诊断；DirectX11 使用独立 winemac 修改，不包含该诊断。两版均保留适配 Wine 11.16 的 MSync。源文件补丁已通过 pristine source dry-run；本脚本是从原构建命令整理的可重建流程，不承诺跨 Xcode 版本字节一致。

## 4. 安装自己编译的模块

1. 先解压对应预编译 Release 包作为完整基础运行时，确保从未混用其他版本的 Wine。
2. 正常退出游戏和官方启动器；对该包的 prefix 使用其自己的 wineserver 停止残留服务，不要使用全局 killall。
3. 复制整个发行包作为备份。把构建输出的 `overlay/` 内容合并到该包 `runtime/Wine Devel.app/Contents/Resources/wine/`。其中 ntdll 与 wineserver 必须配套替换。
4. 对修改后的运行时重新生成校验文件（在该版本文件夹中执行）：

```bash
(cd runtime && find . -type f -exec shasum -a 256 '{}' \;) > RUNTIME-SHA256.txt
```

5. 先把旧的 `local/` 移到自己的备份位置，让“启动游戏”创建新 prefix 验证，不要删除账号/缓存。正常运行后再自行评估迁移设置。
6. 如果回退，退出进程后恢复整份备份，不要只替换 ntdll 而保留不同版本的 wineserver。

编译只重建本项目修改模块，其他依赖仍来自所下载的固定版本运行时。若需要重建 DXMT、MoltenVK 或整个 Gcenx 包，请使用 THIRD_PARTY.md 中的上游构建教程，勿把本脚本当作全依赖构建脚本。

## 5. 验证与反馈

先验证能初始化 Wine、正常绘制，再测试登录、大世界、快速转视角与多技能战斗。不要把“编译成功”当作可玩或无封号风险的保证。报错时提供硬件/系统版本、所用渲染方式和脱敏日志，不要上传整个 local 目录。
