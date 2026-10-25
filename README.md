# 拾页 Reader+ — iOS 9 兼容版

UIKit 文本阅读器，支持 TXT、Markdown、EPUB 和 PDF 原页。集成微软在线自然语音、已下载音频的离线播放、iOS 系统语音。应用版本 1.1.0（build 4）。

## 构建与下载

在 **Actions → Build iOS 9 universal IPA → Run workflow** 运行。成功后下载 `ReaderPlus-iOS9-universal-IPA`，包含未签名 IPA、该次提交的精确源码、校验记录和 SHA256。IPA 需要按设备支持的方式签名安装。

设备包同时包含 armv7 和 arm64，二进制最低系统为 iOS 9.0。当前实际运行验证使用 iOS 26.1 模拟器；iOS 9 等旧系统尚待真机测试，不能将最低系统字段视为所有版本均已验证。

```sh
bash scripts/prepare_compat_sdk.sh
python3 scripts/build_compat.py
python3 scripts/build_compat.py --simulator
bash scripts/compat_tests.sh
bash scripts/compat_simulator.sh
python3 scripts/verify_compat_ipa.py dist/ReaderPlus-1.1.0-iOS9-26.1-unsigned.ipa
```

设备使用固定提交 Theos SDK 库 `0222fd5413cf4b9af096f37b4621afa2688572f7` 的 iOS 9.3 头文件、12.4 设备链接桩以及 Xcode 16.4 classic linker；源码不依赖 SwiftUI 或 Swift 运行库。模拟器使用当前 SDK 编译同一份 UIKit 源码。

回归包括文本/EPUB/GEC 测试、真实在线合成、系统语音实际完成播放，以及缓存 MP3 实际完成播放且不发起新的合成请求。诊断报告在 `ReaderPlus-iOS9-diagnostics`。

## 使用

点击书架加号选择文件，也可从“文件”共享导入。设置中选择微软音色、语速，允许在线合成后即可播放。出门前点击“下载全书离线音频”，等待下载完成，再将朗读方式切为“仅播放离线音频”。缓存按文本、音色、语速保存，改变设置后需重新下载。

“系统语音（离线）”使用设备实际安装的音色，可以朗读未预下载的新文字。中文音色可先在系统语音设置中下载。

**微软完全离线使用来自提前下载的音频。Windows 晓晓、云希模型没有可用的 iOS 合成运行库，未被包含在 IPA 中；不能在断网时使用这些 Windows 模型合成新内容。**

PDF 在 iOS 9/10 支持原页查看，文字提取需要系统提供 PDFKit（iOS 11+）；扫描 PDF 无 OCR。EPUB 提取文字而不还原复杂排版。不支持 DRM、MOBI/AZW。

## 来源与许可

原创 UIKit 代码为 MIT。阅读功能参考 SumatraPDF Plus，未复制其 Win32/C++/MuPDF 源码。在线协议参考 Brewus Edge-TTS（MIT）。SocketRocket 0.6.1 固定提交 `6fdc5fd0db5c49b1ed050d4033ee6a6ee2ec4d39`，保留 BSD 与 PATENTS；移除了旧 SDK 没有的网络服务枚举分支，使用默认网络服务类型。

`CompatApp/RPGEC.c` 从 rany2/edge-tts（固定提交 `bd44c1d1aaebdc1db7f47456ee12431b42ec7cac`）移植，保留 LGPLv3。完整许可在 `ThirdParty/`。修改此模块后可按上述脚本重新构建完整应用，并自行签名安装；对应源码随每份成功构建的 IPA 一起提供。

仓库仅发布用户明确授权的最小构建源码、示例和许可，不包含账号凭据、用户书籍或 Windows 语音包。微软在线接口的协议和可用性可能变化。

## 当前构建结果

[1.1.0 build 4 完整成功构建](https://github.com/gdsamsum/ReaderPlus-iOS-build/actions/runs/40212914396)，精确源码提交 `a5afb14fecd6ac3f24ce0cb2b182e04247dd4537`。iOS 26.1 模拟器的系统朗读和缓存 MP3 播放完成，缓存播放期间新增合成请求为 0。此断言针对应用合成请求计数；没有物理关闭主机网络。旧系统和真机仍需验证。

IPA SHA256：`0cbcb81bacf90344764eb5c4b14331449ea2c87273fb61628c391b94980b8834`。对应精确源码快照随 Actions 主产物提供。
