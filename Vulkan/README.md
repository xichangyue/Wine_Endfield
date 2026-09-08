# Vulkan

独立管理的 Wine Vulkan → MoltenVK 1.4.2 实验版本。

下载 Release 完整预编译包后解压，双击“启动游戏.command”。包内包含运行时，首次仅校验并创建干净 prefix，再输入你自己的游戏目录，无需编译或下载 Wine。无游戏本体、账号、微软字体或预热缓存。Git 源码目录不含 runtime 编译产物。

“更新游戏.command”用于打开自己的官方 Launcher.exe。优先使用 DirectX11 包的更新入口；Vulkan 包的启动器使用软件渲染，尚未验证同等流畅性。更新完成后退出启动器，再用本包启动游戏。详细限制及启动步骤见仓库根 README。
