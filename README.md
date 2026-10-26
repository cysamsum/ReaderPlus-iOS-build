# 拾页 Reader+ — iOS 9 兼容版

UIKit 阅读器，支持 TXT、Markdown、EPUB 与 PDF 原页，提供微软在线语音、预下载音频离线播放、iOS 系统语音。1.2.0（build 5）已由 cysamsum 账号构建。

## 连续朗读预缓冲

在线朗读同时准备当前段与后续段落；队列保留当前段和后两段，最多两个合成请求并行。播放当前段时，提前生成后续音频并预备下一段播放器，减少每段播完才联网的停顿。第一段仍需首次合成；网络持续慢于播放速度时仍可能等待。

音频按书中顺序播放，即使网络先返回后面的段落也不会乱序。暂停时不会因预取完成而自动播放；停止、换章、换书或改音色/语速会取消旧会话。缓存按文本、音色、语速区分，已有音频直接复用，离线模式不会发起预取合成请求。

## GitHub Actions

在 **Actions → Build iOS 9 universal IPA → Run workflow** 运行。成功后下载 `ReaderPlus-iOS9-universal-IPA`，内含未签名 IPA、对应提交的精确源码、Mach-O 验证及 SHA256。IPA 需要根据设备支持的方式签名安装。

```sh
bash scripts/prepare_compat_sdk.sh
python3 scripts/build_compat.py
python3 scripts/build_compat.py --simulator
bash scripts/compat_tests.sh
bash scripts/compat_simulator.sh
python3 scripts/verify_compat_ipa.py dist/ReaderPlus-1.2.0-iOS9-26.1-unsigned.ipa
```

设备包为 armv7 + arm64，按 iOS 9.0 最低系统编译；使用固定 Theos SDK 提交 `0222fd5413cf4b9af096f37b4621afa2688572f7` 的 iOS 9.3 头文件、12.4 设备链接桩及 Xcode 16.4 classic linker。当前模拟器回归目标为 iOS 26.1，不能将最低系统声明视作所有旧版本真机已通过。

回归包括乱序返回、预取数量上限、跨章、取消后迟到响应、延后报告预取错误、缓存与离线隔离；还实际运行系统朗读、缓存 MP3 播放，以及三段在线预取的暂停/恢复和衔接统计。诊断报告在 `ReaderPlus-iOS9-diagnostics`。

## 离线使用与限制

联网选好晓晓/云希及语速，点击“下载全书离线音频”，保持阅读页开启并等待完成；断网后改为“仅播放离线音频”，保持相同音色和语速。iOS 系统语音也可断网朗读新文字，先在系统设置下载需要的音色。

微软离线能力是播放提前下载的音频。Windows 晓晓、云希模型缺少可用 iOS 合成运行库，未包含在 IPA 中，不能在断网时使用这些 Windows 模型合成新文字。

PDF 在 iOS 9/10 支持原页阅读，文字提取需要系统提供 PDFKit（iOS 11+）；扫描件没有 OCR。不支持 DRM、MOBI/AZW。EPUB 提取文字而不还原复杂排版。微软在线接口的协议和可用性可能变化。

## 来源与许可

原创 UIKit 代码为 MIT，阅读功能参考 SumatraPDF Plus，未复制其 Win32/C++/MuPDF。在线协议参考 Brewus Edge-TTS（MIT）。SocketRocket 0.6.1 固定提交 `6fdc5fd0db5c49b1ed050d4033ee6a6ee2ec4d39`，保留 BSD 与 PATENTS；仅移除旧 SDK 没有的网络服务枚举分支。

`CompatApp/RPGEC.c` 从 rany2/edge-tts 提交 `bd44c1d1aaebdc1db7f47456ee12431b42ec7cac` 移植，保留 LGPLv3；完整许可位于 `ThirdParty/`。修改后可以按上述脚本重建应用并自行签名安装，精确源码随成功构建的 IPA 提供。

这里只发布用户授权的最小构建源码、示例和许可，不包含账号凭据、用户书籍或 Windows 语音包。

## 已验证构建

[构建 40281145519](https://github.com/cysamsum/ReaderPlus-iOS-build/actions/runs/40281145519) 全部通过，精确源码提交 `6909831cacf6bf8c5a3a494f670e8b47b98eee80`。iOS 26.1 模拟器三段在线播放的两次换段均已有缓冲，未缓冲换段为 0；跨章、暂停恢复、系统语音与缓存 MP3 播放通过。缓存播放新增合成请求为 0（测试并未物理断开主机网络）。旧系统真机及持续弱网仍需复测。

IPA SHA256：`a0dc5d124ab8f76d9b1a0b530235ef2f79cbef82e940a7c560626957c9d4cfdd`。Actions 主产物同时提供精确源码 ZIP 与校验记录。
