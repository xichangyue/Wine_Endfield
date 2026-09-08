# v0.1.0-experimental

两个独立管理的 macOS Apple Silicon 实验性预编译包：

- `Wine_Endfield-Vulkan-v0.1.0-experimental.tar.xz`：完整运行时，MoltenVK 1.4.2、同步提交、禁用 Metal heap，保留本机已确认流畅的配置。
- `Wine_Endfield-DirectX11-v0.1.0-experimental.tar.xz`：完整运行时，DXMT 0.80、双缓冲、MSync；本机反馈视角响应改善，大量技能叠加仍可能卡顿。
- `wine-11.16-source.tar.gz`：对应 Wine 原始源码；结合仓库各模式 source/wine-11.16.patch 和 BUILD.zh-CN.md 可重建修改模块。
- `SHA256SUMS.txt`：附件 SHA-256。
- `7z2603-src.tar.xz`：包内未修改的 7-Zip 解包组件对应源码。

首次只需从游戏官网获取官方启动器安装器 EXE，解压本包后双击“安装官方启动器.command”选择安装器。脚本从官方1.5.0安装包提取原始文件（规避已复现崩溃的32位安装界面），打开官方启动器，由用户确认协议并下载游戏；之后使用“启动游戏.command”。不要求用户提前准备完整Windows游戏。需要 Rosetta 2，不需要编译器或再次下载 Wine。具体启动、更新、字体和安全提示见 README.md；无法使用预编译包时见 BUILD.zh-CN.md。

不含游戏、官方启动器、账号配置、微软字体或缓存。两版可共用同一游戏目录，但不要同时运行。更新后请退出官方启动器，使用本包入口启动，不依赖官方 DX11 勾选项切换。

验证范围：原本机环境已实际游玩；发行运行时已通过干净 prefix 初始化、DX11 三角形/像素回读/180 帧呈现、Vulkan 环境 Windows 命令测试，两种模式的源码构建脚本实际通过。用户确认从官方安装包提取的启动器能显示下载/安装入口。中文可正常显示，但部分字体仍会回退，外观未完全匹配 Windows；用户确认接受这一限制。发行包的全新账号登录、完整游戏下载与战斗流程和其他 Mac 型号尚未复测。不得将其理解为官方支持、稳定帧率或账号安全保证。

许可证：独立脚本/文档 MIT，Wine 派生模块 LGPL-2.1-or-later；其他组件保持各自许可，见 THIRD_PARTY.md。
