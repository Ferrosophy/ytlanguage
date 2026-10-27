# YTLanguage

在 YouTube iOS 客户端里学英语的注入插件（`YTLanguage.dylib`）：双语字幕、长按查词、字幕列表、单词/句子收藏与导出。

本仓库只包含 YTLanguage 自己的源码。不包含、也不分发 YouTube 应用或任何第三方二进制。你需要自备合法获得的 YouTube IPA，自行注入、签名和安装。

## 功能

- **双语字幕**：原文 + 简体中文译文，可切换 双语 / 原文 / 译文 / 关闭。
  - 原文来自 YouTube 当前加载的 CC 字幕，按句合并并限制每句长度。
  - YouTube 关闭 CC 时，双语字幕也会一起隐藏。
  - 竖屏和画中画时不显示任何字幕。
- **翻译来源**：
  1. 视频自带的人工简体中文字幕。自动生成和自动翻译的字幕轨不算在内。
  2. Google 翻译（免 Key）。
  3. DeepSeek（可选，需要自己的 API Key，存在钥匙串里）。
- **字幕样式**：字号、粗细、颜色、阴影/描边、背景（颜色、模糊、内边距、宽度、圆角），以及 X/Y 位置。
  - 控制栏出现时，字幕自动上移让开进度条。
  - 字幕位于 YouTube 控制按钮和侧边栏下层，不会挡住它们。
- **长按查词**：长按原文中的单词，查看释义和原句，可以收藏单词或打开系统词典。查词时可以选择暂停视频。
- **字幕列表**：显示整部视频的句子和译文，当前句高亮并自动跟随，点击句子跳转到对应位置，长按收藏句子。可将全片原文导出为 Markdown。
- **双语学习**：入口在「设定 › Tweaks」分组下。页面分 单词 / 句子 两个标签，可只显示原文、只显示译文，或两者都显示；左滑删除。可导出为 TXT / CSV / JSON。

## 兼容性

已测试的环境：

| 项目 | 版本 |
|---|---|
| YouTube | 21.37.5 |
| iOS | 27.0.1 |
| 注入方式 | 轻松签（ESign） |

插件依赖的是 YouTube 的私有界面和类，YouTube 更新后可能失效，不保证兼容未来版本。逐项的设备验证记录见 [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)。

**需要同时注入：**
- [YTVideoOverlay](https://github.com/PoomSmart/YTVideoOverlay)：提供播放器按钮。缺少时，只会显示一个提示用的悬浮角标。

**可选：**
- YouGroupSettings：提供设置中的 Tweaks 分组。缺少时，「双语学习」会出现在设置第一组。

## 构建

在 Windows 上使用 WSL2 Ubuntu + [Theos](https://theos.dev)，SDK 为 iPhoneOS 16.5，目标为 arm64 / iOS 14.0+。

```bash
bash build.sh               # 产出 dist/YTLanguage-v<VERSION>.dylib，附构建日志和 sha256
CHECK_ONLY=1 bash build.sh  # 只编译检查，不写 dist/
```

版本号来自 `VERSION` 文件。`build.sh` 不会覆盖已存在的同版本产物。

`Sources/Core` 是不依赖 UIKit 的纯逻辑部分，测试在 `Tests/CoreTests.m`。macOS 上可以直接运行：

```bash
clang -fobjc-arc -framework Foundation Tests/CoreTests.m Sources/Core/*.m -o coretests && ./coretests
```

GitHub Actions 会在 macOS 上自动跑这组测试。

## 代码结构

| 目录 | 内容 |
|---|---|
| `Tweak.x` | 全部 hook：播放器按钮、字幕文档捕获、播放器、画中画、原生字幕、设置分组 |
| `Sources/Core` | 字幕解析、分句、文本工具（可离线测试） |
| `Sources/HostAdapter` | 访问 YouTube 内部对象。每个用到的接口都注明了来源，并在调用前检查是否存在 |
| `Sources/Services` | 设置、字幕样式、翻译、SQLite 存储 |
| `Sources/UI` | 字幕层、字幕列表、查词卡片、面板、样式页、双语学习页 |

## 隐私

- **数据保存在本机**：收藏的单词和句子存放在 `Application Support/YTLanguage/ytlanguage.sqlite`，不上传。没有任何统计或遥测。
- **网络请求**：只有以下三类。
  - YouTube 自己的字幕地址（下载人工中文字幕时）；
  - `translate.googleapis.com`（Google 翻译）；
  - `api.deepseek.com`（仅在填写了 Key 时）。
- **DeepSeek Key**：保存在 iOS 钥匙串，不写入日志。

## 致谢与许可

- 接口声明参考了 [YouTubeHeader](https://github.com/PoomSmart/YouTubeHeader)（MIT）。
- 设置分组和播放器按钮的接入方式参考了 [YTVideoOverlay](https://github.com/PoomSmart/YTVideoOverlay)、[YouPiP](https://github.com/PoomSmart/YouPiP)（MIT）。
- 本仓库没有复制它们的源码，只声明了用到的最小接口。

更新记录见 [CHANGELOG.md](CHANGELOG.md)。
