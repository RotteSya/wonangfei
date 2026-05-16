# 窝囊费 Handoff Package

交付时间：2026-05-15  
交付范围：品牌色彩、字体、间距规范、组件库定义、互动原型源码、吉祥物与视觉参考资产。

## Package Map

- `WNF.xcodeproj`：原生 SwiftUI iOS 工程，可直接用 Xcode 打开、构建和运行。
- `WNF/`：SwiftUI App 源码、工资计算状态、页面组件和 Asset Catalog。
- `WNFWidget/`：WidgetKit 小组件源码，复用原生工资计算和展示派生模型。
- `WNFTests/`：轻量命令行检查，覆盖工资计算核心边界。
- `index.html`：已实现的可运行 App 原型入口，包含首页、记录页、我的页、参数控制和交接文件链接。
- `brand-tokens.css`：可直接复制到实现项目的 CSS 变量。
- `design-tokens.json`：给工程、设计工具或 CJX 导入用的结构化 token。
- `component-library.md`：2026-05-16 原型抽象出的组件定义、状态和使用规则。
- `implementation-handoff.md`：工程落地说明，包含已实现互动、数据公式和文件关系。
- `asset-manifest.md`：所有已打包图片资产的用途和路径。
- `assets/source/`：2026-05-16 活跃原型源码快照，根页面直接复用其中的产品屏组件。
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

## Product Surfaces

- 首页：一个核心数字，不再提供上下分页或明细下页。
- 记录页：周 / 月 / 年分段控件、可点柱状图、成就卡、徽章区。
- 我的页：月薪编辑、工作日选择、上下班时间、午休开关、加班与隐私开关。

## iOS App

截至 2026-05-16，仓库已落成一个原生 SwiftUI 版本，bundle id 为 `com.wonangfei.app`，最低系统版本为 iOS 17。Widget extension 的 bundle id 为 `com.wonangfei.app.WNFWidget`，App Group 为 `group.com.wonangfei.app`。

构建命令：

```sh
xcodebuild -project WNF.xcodeproj -scheme WNF -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

工资计算检查：

```sh
swiftc WNF/WageCore.swift WNF/WageDisplayModel.swift WNFTests/WageCalculatorChecks.swift -o /tmp/wnf-wage-checks && /tmp/wnf-wage-checks
```

已实现：

- 首页工资实时计算、隐私打码、进度条和 `HomeSprite.mov` 首页吉祥物动画；缺少 MOV 资源时才回落到状态静态图。
- 首页下班后会切换为今日结算；开启计入加班时显示“加班多挣”和今日总计，并支持“结束今日”。
- 记录页周 / 月 / 年切换、柱状图选中态、成就和徽章模块。
- 我的页月薪、工作日、时间、午休、加班、隐私状态编辑，并持久化到本机设置。
- WidgetKit 小组件 target：小 / 中 / 大尺寸读取 App Group 配置快照，按同一套工资计算展示收工、加班、休息状态。
- `assets/mascot` 中的主吉祥物和 Cow pose 已接入 `WNF/Assets.xcassets`。

## Source of Truth

原型令牌来自 `assets/source/shared.jsx`，根页面的运行时样式来自 `brand-tokens.css`。原生实现以 `WNF/Theme.swift`、`WNF/WageCore.swift` 和 `WNF/WageDisplayModel.swift` 为准；如果视觉规范和源码出现差异，以 `brand-tokens.css`、`design-tokens.json` 和原生 SwiftUI 实现共同校准。
