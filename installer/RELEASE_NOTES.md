# v0.4.2-preview：ACE 服务宿主与 Vulkan 稳定性修复

本版用于修复部分设备上的 ACE `1-1720-1000015145`，并改善 Vulkan 花屏和画面冻结。持续日常使用验证通过。

- 补齐 `KeIpiGenericCall`、`KeSetSystemGroupAffinityThread`、`KeRevertToUserGroupAffinityThread`、`MmCopyMemory`，保留此前已采用的 DriverInit、MDL、线程上下文与真实 LSA 修复。
- `KeIpiGenericCall` 和通用 DPC 按活动处理器执行，保持处理器身份与 IRQL/CR8 一致；补齐 DPC 异常、TLS、自旋锁和卸载收尾。
- 在 Wine 初始化后通过服务管理器注册并启动 `SamSs`，由 `lsass.exe` 以服务方式运行。
- 对 ACE-CORE 后台线程触发的无参数 `Tace` 保留 Wine 驱动服务宿主，只结束触发 watchdog 的系统线程；带参数的 `Tace` 和其他 bugcheck 保持原处理。
- MoltenVK 采用 FineWine 的终末地补丁，并合入管线缓存配置匹配、部分描述符写入、3D 纹理视图生命周期、参数缓冲重绑和 Metal 命令缓冲资源保留修复。
- 正常游戏配置关闭资源快照、GPU 错误详情、故障面包屑与编码器标签等长时诊断，减少额外命令缓冲开销；同步、资源生命周期和管线修复保留。
- 默认运行日志记录 `ntoskrnl` 警告，便于在受影响的 Mac 上确认隐藏 `Tace` 是否已被收敛。
- 运行库升级时只清除 Hypergryph/Gryphline 终末地目录中的 `vulkan_pso_cache.bin`；同版本重装保留缓存，其他用户设置和缓存不动。
- 官方“DirectX 11 启动”未勾选仍为 Vulkan/MoltenVK，勾选仍为 DX11/DXMT。

新增“终末地兼容诊断”入口，可生成脱敏支持包，用于比较 ACE 文件、服务配置和最近会话中的相关日志。

推荐分发 `Wine_Endfield-Installer-0.4.2-preview.zip`。解压后打开“终末地 Mac 安装器.app”，选择原安装目录即可升级。安装器为 ad-hoc 签名，未经过 Apple 公证。

验证通过。
