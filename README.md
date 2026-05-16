# 窝囊费 Handoff Package

交付时间：2026-05-15  
交付范围：品牌色彩、字体、间距规范、组件库定义、互动原型源码、吉祥物与视觉参考资产。

## Package Map

- `WNF.xcodeproj`：原生 SwiftUI iOS 工程，可直接用 Xcode 打开、构建和运行。
- `WNF/`：SwiftUI App 源码、工资计算状态、页面组件和 Asset Catalog。
- `index.html`：已实现的可运行 App 原型入口，包含首页、记录页、我的页、参数控制和交接文件链接。
- `brand-tokens.css`：可直接复制到实现项目的 CSS 变量。
- `design-tokens.json`：给工程、设计工具或 CJX 导入用的结构化 token。
- `component-library.md`：当前原型抽象出的组件定义、状态和使用规则。
- `implementation-handoff.md`：工程落地说明，包含当前互动、数据公式和文件关系。
- `asset-manifest.md`：所有已打包图片资产的用途和路径。
- `assets/source/`：当前活跃原型源码快照，根页面直接复用其中的产品屏组件。
- `assets/source/wonangfei.html`：`窝囊费.html` 的 ASCII 文件名副本，便于跨平台交接。
- `assets/mascot/`：主吉祥物图和 8 个原始 Cow pose。
- `assets/reference-screens/`：用户提供的整套视觉物料和参考图。

## Brand Summary

窝囊费的视觉关键词是：丧萌、自嘲、金币感、工位回血、黑黄强对比。整体避免高级灰和企业感，用奶油白承托内容，用窝囊黄负责第一视觉锚点，用反思黑承担标题、核心按钮和高权重信息。

核心视觉系统：

- 主色：窝囊黄 `#FFC83D`
- 强对比：反思黑 `#0D0D0D`
- 背景：奶油白 `#FFF6E5`
- 辅助：电光青 `#00E5FF`、热辣珊瑚 `#FF5C57`
- 展示字体：ZCOOL QingKe HuangYou
- 正文字体：Nunito + PingFang SC
- 数字字体：JetBrains Mono

## Current Product Surfaces

- 首页：一个核心数字，不再提供上下分页或明细下页；右上角为分享入口，弹出今日窝囊战报卡片。
- 记录页：周 / 月 / 年分段控件、可点柱状图、成就卡、徽章区。
- 我的页：月薪编辑、每月工作日编辑、周工作日选择、上下班时间、午休开关和加班开关。

## iOS App

当前已落成一个原生 SwiftUI 版本，bundle id 为 `com.wonangfei.app`，最低系统版本为 iOS 17。

构建命令：

```sh
xcodebuild -project WNF.xcodeproj -scheme WNF -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

XcodeBuildMCP 已在 `.xcodebuildmcp/config.yaml` 持久化默认值：project `WNF.xcodeproj`、scheme `WNF`、configuration `Debug`、simulator `iPhone 17`、bundle id `com.wonangfei.app`。配置有效时可以直接使用 `build_sim`、`build_run_sim`、`screenshot` 和 `tap`。

已实现：

- 首页工资实时计算、隐私打码、进度条。
- 首页分享卡片：背景虚化、今日窝囊费/上班时长、卡片内隐藏敏感信息、系统分享和退出。
- 首次启动引导：4 屏 SwiftUI onboarding、第一页参考大图优先的 intro 布局、跳过/返回/分页控制、月薪/作息/午休设置和最终确认。
- 记录页周 / 月 / 年切换、柱状图选中态、成就和徽章模块。
- 我的页月薪和每月工作日支持 `- / +` 微调，也支持点中间数字弹出快速输入框；时间、午休和加班状态可编辑。
- `assets/mascot` 中的主吉祥物和 Cow pose 已接入 `WNF/Assets.xcassets`。

引导页 hero 图位于 `WNF/Assets.xcassets`，源文件来自 `/Users/shelingzhao/Documents/窝囊费素材/引导/`：

- `p1.png` -> `OnboardingP1.imageset/onboarding-p1.png`
- `p2.png` -> `OnboardingP2.imageset/onboarding-p2.png`
- `p3午休.png` -> `OnboardingLunchSleep.imageset/onboarding-lunch-sleep.png`
- `p3睡醒.png` -> `OnboardingLunchWake.imageset/onboarding-lunch-wake.png`
- `p4.png` -> `OnboardingP4.imageset/onboarding-p4.png`

这些 PNG 必须保持 `1536 x 1024` 和 alpha 通道。替换后先用 `sips -g pixelWidth -g pixelHeight -g hasAlpha <file>` 检查目标 asset，再构建。

## Source of Truth

当前实现中的主令牌来自 `assets/source/shared.jsx`，根页面的运行时样式来自 `brand-tokens.css`。如果视觉规范和源码出现差异，以 `brand-tokens.css` 和 `design-tokens.json` 作为交付后的实现基准。
