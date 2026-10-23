# Wine_Endfield
arm mac的《明日方舟：终末地》兼容层

### 图形实现
- DirectX 11
- Vulkan
两种渲染方式都做了实现，在作者电脑测试游玩基本无问题。

### 注意事项
1.作者只在M1Max的Mac中进行了测试，系统为macOS26.6.1，不保证其他主机可用。   
2.因为反作弊的原因，又因为本项目使用wine模拟作为实现方式，所以不保证账号安全，可能有封号风险（虽然作者一直拿这个玩）。   
3.理论讲Vulkan版本会更流畅，但需要有缓存后才会流畅，初次游玩时应该会很卡，但需要适应一段时间后才会流畅；DirectX 11版本一直相对流畅，但性能上限不及Vulkan版本。   
4.输入映射的是windows的输入方式，需要自行适应，由于作者使用的就是windows版键盘所以无障碍。   

爱来自GPT-6 Astra。

## v0.4.0-recovery：修复版安装器（预发布）

从 [v0.4.0-recovery 发布页](https://github.com/xichangyue/Wine_Endfield/releases/tag/v0.4.0-recovery) 下载 **Wine_Endfield-Installer-0.4.0-recovery.zip**，解压后打开“终末地 Mac 安装器.app”。需要 **Apple Silicon、macOS 26 或更新版本及 Rosetta 2**；使用者无需编译器或 Python。请勿下载 GitHub 自动生成的 Source code ZIP 作为安装器。

本版统一已验证的 Wine 修复运行库，修正官方启动器白屏相关图形路径和认证组件的依赖加载位置，并补充安装失败的阶段、退出码和具体错误。仅在 M1 Max / macOS 26.6.1 验证，不把此前收到的“mac 27.2 安装未完成”反馈视为已定位或已修复；若新版仍失败，请保留日志。

### 从 v0.2 / v0.3 升级

1. 正常退出游戏、官方启动器和其他 Wine 程序，外置磁盘保持连接。
2. 打开新版安装器，选择**原安装文件夹**，即包含 `Game`、`Launcher`、`Apps` 等目录的位置，通常为 `~/Games/Wine Endfield`。不要选择其中的 `Game`、某个模式子目录或旧安装器 App。
3. 已有官方启动器时，“官方安装包”可留空；旧安装未完成、目录中尚无 `Launcher/Launcher.exe` 时，重新选择自己从官网下载的 Windows 官方启动器 EXE。
4. 点击更新环境。新环境准备完成后才切换；游戏文件和已有官方启动器保留。成功后只保留新版采用的用户环境，自动清除旧版本设置与缓存，不必重新下载整份游戏。旧版遗留的 `.setup-lock` 不需要手工删除。
5. 完成后打开“终末地”入口，**在官方启动器里点击“开始游戏”**。旧版三个模式入口也会打开官方启动器；原来的直接启动游戏流程不再适用于本版。

官方未勾选“DirectX 11 启动”时使用 **Vulkan / MoltenVK**；勾选时使用 **DirectX 11 / DXMT / Metal**。启动器自身使用 DXMT，不代表游戏一定在用 DX11。

支持带 `.endfield-installer-v1` 标记的旧安装目录；旧版失败后保留的受管理目录也可以重试。不要手工创建标记来接管其他目录。本版不自动迁移 v0.1 手工分包。失败时旧环境用于恢复；成功后自动清理已识别的旧运行库、旧环境和历次运行库备份，不保留完整旧版供回退。发现实体游戏时保留对应部分并提示；未采用的旧 Wine 环境会整体清理，已识别清理目录之外的自有文件保留。

### 新安装、移动硬盘与日志

- 新用户选择空文件夹，并提供从官网下载的 Windows 官方启动器 EXE。完成后在官方启动器自行确认协议、下载和校验游戏，保留默认目录或 `C:\Endfield`。
- 可选择内置磁盘或 **APFS / Mac OS 扩展（HFS+）** 外置盘；不支持直接安装到 exFAT、FAT、NTFS 或网络卷。安装器不会格式化磁盘。
- 搬动时先退出所有 Wine 程序，再移动**整个安装文件夹**，从新位置 `Apps/终末地.app` 打开。选择另一空目录属于新安装，不会自动搬走旧游戏。
- 失败弹窗会显示具体阶段及错误；点击“查看日志”，提供末尾约30行、芯片型号、完整系统版本和安装磁盘格式。分享前移除账号等个人信息，不要上传整个 prefix。

完整步骤见 [安装器说明](installer/README.zh-CN.md)，改动见 [更新说明](installer/RELEASE_NOTES.md)，验证范围见 [VALIDATION.md](VALIDATION.md)。本版未经过 Apple 公证，请核对 Release 的 SHA256SUMS.txt 并按系统提示处理；不要关闭全局安全保护。

### 源码和历史版本

运行包不含游戏、官方安装器、账号、个人 prefix 或预热缓存。Release 同时提供修改后的 Wine、MoltenVK 完整源码和相关上游源码；来源与许可证见 [THIRD_PARTY.md](THIRD_PARTY.md)，构建方式见 [BUILD.zh-CN.md](BUILD.zh-CN.md)。独立安装器使用 MIT，Wine 派生代码保留 LGPL，各第三方组件保留原许可。

旧版分包仅保留作历史参考：[v0.3 文档](https://github.com/xichangyue/Wine_Endfield/blob/v0.3.0-preview/README.md)。其中“退出官方启动器后直接启动游戏”的步骤不适用于本版。
