# 第三方组件与许可

本项目不是游戏官方产品，不分发游戏、官方启动器、Windows 商业字体或用户数据。

- **Wine 11.16**：LGPL-2.1-or-later；版权及许可证见各模式 licenses/Wine-*。Release 提供完整原始源码 archive，加各模式 source/wine-11.16.patch 即为修改源码；构建脚本见 tools/build-overlay.sh。
- **Gcenx macOS Wine builds 11.16**：上游二进制基础包来自 https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.16 。包含的未修改依赖保留各自许可证，不属于本项目 MIT。上游构建和依赖来源见其 README 与 https://github.com/Gcenx/macports-wine 。
- **DXMT 0.80**：https://github.com/3Shain/dxmt/tree/v0.80 ，MIT；上游内含 LLVM 等第三方代码，按其各自许可；本项目不修改 DXMT 二进制。只使用 d3d11/dxgi/winemetal，不安装 NVAPI/NGX。源码发布页 https://github.com/3Shain/dxmt/releases/tag/v0.80 。
- **MoltenVK 1.4.2**：Apache-2.0；https://github.com/KhronosGroup/MoltenVK/tree/v1.4.2 。Vulkan 包使用官方非 private-api 构建；DX11 上游基础包原带的 MoltenVK 保留不用于游戏 Vulkan 路径。
- **MSync**：Wine LGPL 范围内的移植代码；参考 https://github.com/marzent/wine-msync 及 https://github.com/dttdrv/wiage/commit/3f52c197d9fc9569a09d224b861e3010b397cb03 ，本项目仅选取同步相关变更适配 Wine 11.16。
- **Endfield_FineWine**：兼容性研究参考 https://github.com/stoicswe/Endfield_FineWine ，具体 Wine 修改保留源码版权；不是游戏官方支持或账号安全承诺。

- **7-Zip 26.03 for macOS**：未修改的官方通用二进制，用于读取用户自己的 NSIS 安装器。来源 https://www.7-zip.org/download.html ，许可见各模式 licenses/7zip-License.txt（LGPL、unRAR 限制及 BSD 部分）。Release 附 7z2603-src.tar.xz 对应官方完整源码。本项目没有分发鹰角安装器或替用户接受协议。

独立脚本及说明使用仓库 MIT 许可。Wine 派生补丁及所构建模块不因此转为 MIT。自行再分发时同样须保留相应许可证和可取得的对应源码。
