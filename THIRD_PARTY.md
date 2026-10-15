# 第三方组件与许可

本项目不是游戏官方产品，不分发游戏、官方启动器、Windows 商业字体或用户数据。独立安装脚本与说明使用仓库 MIT 许可；Wine 派生模块仍按其 LGPL 许可，MoltenVK 与其他上游代码仍按各自许可。

- **Wine 11.16**：LGPL-2.1-or-later；各模式保留 `licenses/Wine-*`。Release 的完整原始源码 `wine-11.16-source.tar.gz` 加该模式 `source/wine-11.16.patch` 即为修改源码。Vulkan 和 DirectX11 的补丁独立，后者保持原版；构建脚本为 `tools/build-overlay.sh`。
- **Gcenx macOS Wine builds 11.16**：二进制基础包来自 [固定发布页](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.16)。其未修改依赖不属于本项目 MIT；来源和构建方法见 [macports-wine](https://github.com/Gcenx/macports-wine)。完整包保留上游附带的许可证。
- **MoltenVK 1.4.2（Vulkan 修改版）**：Apache-2.0；基线 [db66022459ffb663aa2b50f6b018bc2e124f5edf](https://github.com/KhronosGroup/MoltenVK/tree/db66022459ffb663aa2b50f6b018bc2e124f5edf)。本版不再使用未修改的官方 dylib。Release 提供完整 `MoltenVK-1.4.2-Endfield-v0.3.0-source.tar.xz`；仓库保留 `Vulkan/source/moltenvk-1.4.2-endfield.patch`、源码清单和 `tools/build-moltenvk.sh`。许可证为 `Vulkan/licenses/MoltenVK-Apache-2.0.txt`。
- **SPIRV-Cross（修改版）**：Apache-2.0；基线 [6c09849fe88c48eaed08413aa022aaa136a3a057](https://github.com/KhronosGroup/SPIRV-Cross/tree/6c09849fe88c48eaed08413aa022aaa136a3a057)，修改为 Device-scope barrier 转换，patch 为 `Vulkan/source/spirv-cross-device-barrier.patch`。完整修改源码包含在上述 MoltenVK 源码附件中。
- **MoltenVK 依赖**：源码附件固定包含 SPIRV-Tools、SPIRV-Headers、Vulkan-Headers、Vulkan-Tools、volk 和 cereal 的精确提交，完整表见 `Vulkan/source/SOURCE-PROVENANCE.json`。各自许可证 / notices 保留在源码原位，并复制至 `Vulkan/licenses/MoltenVK-dependencies/`；包括 Apache-2.0、MIT、BSD 及文件内单独许可。这些许可证不因本项目 MIT 而改变。Vulkan-Tools 和 volk 是上游示例依赖，不用于游戏主绘制。
- **DXMT 0.80**：MIT；[上游源码](https://github.com/3Shain/dxmt/tree/v0.80) 和 [固定发布页](https://github.com/3Shain/dxmt/releases/tag/v0.80)。本项目不修改 DXMT 二进制；上游内含 LLVM 等第三方代码，按其各自许可。DirectX11 仅使用 d3d11 / dxgi / winemetal，不安装 NVAPI / NGX。其上游基础包原带的 MoltenVK 不用于游戏 Vulkan 路径。
- **MSync**：Wine LGPL 范围的移植代码；参考 [wine-msync](https://github.com/marzent/wine-msync) 与 [wiage 同步变更](https://github.com/dttdrv/wiage/commit/3f52c197d9fc9569a09d224b861e3010b397cb03)，本项目适配至 Wine 11.16。
- **Endfield_FineWine**：兼容性研究参考 [上游仓库](https://github.com/stoicswe/Endfield_FineWine)，Wine 修改保留源码版权。
- **7-Zip 26.03 for macOS**：未修改的官方通用二进制，用于读取用户自己的 NSIS 安装器；来源为 [官方下载页](https://www.7-zip.org/download.html)。各模式保留 `licenses/7zip-License.txt`（LGPL、unRAR 限制及 BSD 部分），Release 同时提供 `7z2603-src.tar.xz` 完整源码。本项目不分发鹰角安装器或代用户接受其协议。

重新分发时，请一并保留许可证和可取得的对应源码；具体构建与源码校验见 `BUILD.zh-CN.md`。
