# 拾页 Reader+ — iOS 9 兼容版

**1.2.1（build 7）已通过 [云端构建与回归 40324991581](https://github.com/cysamsum/ReaderPlus-iOS-build/actions/runs/40324991581)。** 精确应用源码提交为 `56358f684a9781fbb28afa1fa159caecff490b59`。iOS 26.1 原生及本机导入界面、系统朗读、离线播放和在线预缓冲回归全部通过。

在 iPad mini 第一代 / iOS 9.3.5 上实际捕获旧版点击“＋”时的 iCloud entitlement 断言；现已使用本机导入列表修复。TXT/EPUB 均已实际入库，最终 build 7 覆盖安装后原书库文件哈希保持一致，用户再次确认 TXT 进入阅读页。此证据不代表全部系统或文件提供方均已验证。

未签名 IPA SHA256：`8cbc51984428d1417d553a351f0f9c5106cdc22dfb6c4b26796cdb203397cb3e`；精确云端源码包 SHA256：`67c5905b35fac09e2f881529dc104730d66ae3006914553fd8995bbc53466df9`。二者可从上述构建的 `ReaderPlus-iOS9-universal-IPA` 下载。

UIKit 阅读器，支持 TXT、Markdown、EPUB 与 PDF 原页，提供微软在线语音、预下载音频离线播放、iOS 系统语音。本次修订为 1.2.1（build 7），由 cysamsum 账号构建，结果见 Actions。

## iOS 9/10 本机导入

旧系统的系统文档选择器要求签名具备 iCloud 容器 entitlement。未配置该能力时会在初始化阶段触发系统断言。1.2.1 在 iOS 9/10 直接使用 App 内的文档浏览器：通过电脑文件共享把 TXT、EPUB、PDF 或 MD 传入“拾页 Reader+”，点击加号后即可选取；子文件夹可进入，右上角可刷新。也可以从其他 App 选择“拷贝到拾页”。

iOS 11+ 使用系统选择器，接收 `public.data` / `public.content` 文档类型；若系统初始化失败则回退到本机浏览器。本机浏览器不会读取其他 App 的私有目录，也不需要伪造 iCloud entitlement。

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
python3 scripts/verify_compat_ipa.py dist/ReaderPlus-1.2.1-iOS9-26.1-unsigned.ipa
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

