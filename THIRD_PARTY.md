# 第三方组件与许可

本项目不是游戏官方产品，不分发游戏、官方启动器、Windows 商业字体或用户数据。独立安装脚本与说明使用仓库 MIT 许可；Wine 派生模块仍按其 LGPL 许可，MoltenVK 与其他上游代码仍按各自许可。安装包的 `Recovery/licenses/` 保留组件许可证和 notices。

v0.4.0 使用统一 Recovery 运行库。Wine 模块来自分别验证的历史源码变体；完整对应源码和模块映射见 [Recovery/source/README.zh-CN.md](Recovery/source/README.zh-CN.md)。旧 v0.3 的两个模式补丁不能重建本版全部 Wine 模块。

- **Wine 11.16 及本项目修改**：LGPL-2.1-or-later，另有 Wine 源码中的逐文件许可与 notices。同一 Release 提供 `Wine-11.16-Endfield-v0.4.0-recovery-source.tar.xz`，包含 12,461 个文件的完整源码集合、五套可恢复实际构建源树的变体、逐文件校验和构建脚本。覆盖 ntdll、ntoskrnl、wineserver、winemac、kernel32 和 LSA/RPC 认证模块。其聚合补丁相对固定的 [Wine 11.16](https://github.com/wine-mirror/wine/tree/wine-11.16)；模块到源码及二进制哈希映射见 `Recovery/source/SOURCE-PROVENANCE.json`。
- **Gcenx macOS Wine builds 11.16**：未改模块和配套依赖来自 [固定发布页](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.16)，构建方法与依赖来源见 [macports-wine](https://github.com/Gcenx/macports-wine)。依赖不属于本项目 MIT；上游包内许可证保留在运行库中。GnuTLS、FreeType 等依赖保持上游二进制；本版重建 `secur32.so`，使其通过相对路径加载包内 GnuTLS。
- **MoltenVK 1.4.2（项目修改版）**：Apache-2.0；基线 [db66022459ffb663aa2b50f6b018bc2e124f5edf](https://github.com/KhronosGroup/MoltenVK/tree/db66022459ffb663aa2b50f6b018bc2e124f5edf)。二进制与 v0.3 已发布版本一致。同一 Release 提供完整 `MoltenVK-1.4.2-Endfield-v0.3.0-source.tar.xz`，仓库保留 `Vulkan/source/moltenvk-1.4.2-endfield.patch` 和 `tools/build-moltenvk.sh`。附件沿用 v0.3 名称是因为源码和二进制均未再次修改。
- **SPIRV-Cross（修改版）**：Apache-2.0；基线 [6c09849fe88c48eaed08413aa022aaa136a3a057](https://github.com/KhronosGroup/SPIRV-Cross/tree/6c09849fe88c48eaed08413aa022aaa136a3a057)，修改为 Device-scope barrier 转换，patch 为 `Vulkan/source/spirv-cross-device-barrier.patch`。完整修改源码包含在上述 MoltenVK 附件中。
- **MoltenVK 依赖**：上述附件包含 SPIRV-Tools、SPIRV-Headers、Vulkan-Headers、Vulkan-Tools、volk 和 cereal 的固定源码与原位许可证；提交表见 `Vulkan/source/SOURCE-PROVENANCE.json`。主要许可证为 Apache-2.0、MIT、BSD 及逐文件许可，notices 另复制至包内 `licenses/MoltenVK-dependencies/`。Vulkan-Tools 和 volk 是上游示例依赖，不用于游戏主绘制。
- **DXMT v0.80**：MIT；四个 d3d11/dxgi/winemetal 模块与 [官方 v0.80 二进制](https://github.com/3Shain/dxmt/releases/tag/v0.80) 逐字节一致，未在本项目重编译。源码固定提交为 [589adb780354b461645b29999cefaf533594ee99](https://github.com/3Shain/dxmt/tree/589adb780354b461645b29999cefaf533594ee99)，Release 提供 `dxmt-v0.80-source.tar.gz`。这个上游源码归档不包含 Git 子模块或 LLVM 源码；固定依赖来源见 `Recovery/source/GRAPHICS-PROVENANCE.json`，上游构建方法见该提交的 `.github/workflows/ci.yml`。本项目不安装 NVAPI/NGX；DXMT 上游包附带的其他 MoltenVK 不用于本版游戏 Vulkan 路径。
- **DXMT 依赖与移植代码**：LLVM 15.0.7 使用 Apache-2.0 WITH LLVM-exception；DXVK、MinGW 头文件、DXBCParser 及其他文件保留各自许可。许可证和 notices 位于 `Recovery/licenses/DXMT-dependencies/`，来源及 SHA-256 见 `Recovery/source/GRAPHICS-LICENSES.json`。本项目修改的 `winemac.so` 属于 Wine，由 Wine 源码附件覆盖。
- **MSync**：Wine LGPL 范围的移植代码，参考 [wine-msync](https://github.com/marzent/wine-msync) 与 [wiage 同步变更](https://github.com/dttdrv/wiage/commit/3f52c197d9fc9569a09d224b861e3010b397cb03)，本项目适配至 Wine 11.16。
- **Endfield_FineWine / DW-Proton**：兼容性研究及 Wine 补丁参考 [Endfield_FineWine](https://github.com/stoicswe/Endfield_FineWine)。所采用 Wine 修改的版权和许可证保留在完整源码与补丁中。
- **7-Zip 26.03 for macOS**：未修改的官方通用二进制，用于读取用户自己的 NSIS 安装器，来源为 [官方下载页](https://www.7-zip.org/download.html)。包内保留 `licenses/7zip-License.txt`（LGPL、unRAR 限制及 BSD 部分）；Release 同时提供完整 `7z2603-src.tar.xz`。本项目不分发鹰角安装器或代用户接受其协议。

附件 SHA-256 见同一 Release 的 `SHA256SUMS.txt`。重新分发时，请保留许可证及对应源码的获取方式；构建说明见 [BUILD.zh-CN.md](BUILD.zh-CN.md)。

本包继承的可选 `winegstreamer.so` / `winedmo.so` 仍有未随包提供的 GStreamer / FFmpeg 依赖；本机已有游戏验证不等同于全部 Wine 媒体解码功能验证。本版没有把这些模块改为完整自包含的媒体运行库。
