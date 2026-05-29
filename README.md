# 窝囊费 Handoff Package

交付时间：2026-05-15  
交付范围：品牌色彩、字体、间距规范、组件库定义、互动原型源码、吉祥物与视觉参考资产。

## Package Map

- `WNF.xcodeproj`：原生 SwiftUI iOS 工程，可直接用 Xcode 打开、构建和运行。
- `WNF/`：SwiftUI App 源码、工资计算状态、页面组件和 Asset Catalog。
- `WNFWidget/`：Widget extension，读取 App Group 工资快照。
- `WNFTests/`：单元测试。
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

## Branches

本项目只使用三个分支前缀：

- `feat/`：新功能或行为变化，例如 `feat/payslip-export`。
- `fix/`：bug 修复，例如 `fix/coin-animation-stutter`。
- `tweak/`：视觉微调、文案、间距、动效手感或素材替换，例如 `tweak/yellow-pill-radius`。

除非项目负责人明确改约定，否则不要使用 `codex/`、`chore/`、`design/`、`release/` 等额外前缀。

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
- 记录页：周 / 月 / 年分段控件、按本机每日记录聚合的可点柱状图、成就卡、徽章区；记录聚合读取 SQLite 中近 400 天每日明细和更早的月汇总，但缓存 key 使用日期键、`recordsRevision` 和 live-day 设置，避免每次 body 重算都比较整份记录字典，也不订阅首页的秒级刷新；非选中工作日的今日 live record 记为 0。
- 我的页：月薪编辑、每月工作日编辑、周工作日选择、上下班时间、午休开关、加班开关。

## iOS App

当前已落成一个原生 SwiftUI 版本，bundle id 为 `com.wonangfei.app`，最低系统版本为 iOS 17。v1 面向 iPhone；Xcode target 使用 `TARGETED_DEVICE_FAMILY = 1`，ASC 不上传 iPad 截图。

构建命令：

```sh
xcodebuild -project WNF.xcodeproj -scheme WNF -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

XcodeBuildMCP 已在 `.xcodebuildmcp/config.yaml` 持久化默认值：project `WNF.xcodeproj`、scheme `WNF`、configuration `Debug`、simulator `iPhone 17`、bundle id `com.wonangfei.app`。配置有效时可以直接使用 `build_sim`、`build_run_sim`、`screenshot` 和 `tap`。

已实现：

- 首页工资实时计算、隐私打码、进度条。
- 首页吉祥物位使用透明循环视频序列：`home-typing.mov` 和 `home-bored.mov` 每轮随机排序后连续播放；视频控制器由 `HomeMascotVideoSessionCoordinator` 稳定持有，`RootView` 只转发 scene phase 和 tab 切换事件；切换 tab 或进入短暂 inactive 时只暂停/恢复，不重建 AVQueuePlayer 队列；进入后台或收到内存警告时才会清空队列，回到首页活跃态再重新装载。
- 首页分享卡片：背景虚化、今日窝囊费/上班时长、卡片内隐藏敏感信息、系统分享和退出；系统分享渲图期间分享按钮会显示 loading 并防重复点击。该处理是 UX/感知反馈修复，不减少主线程栅格化开销：渲图前会先让出一帧刷新 UI，再用当前 `UIWindowScene.screen.scale` 驱动 SwiftUI `ImageRenderer.render(rasterizationScale:)` 输出系统分享图；`UIActivityViewController` 由根视图背景中的 presenter 呈现，并配置 popover source view，避免 iPad / Mac Catalyst 分享弹窗崩溃；分享卡组件集中在 `WNF/ShareCard.swift`。
- 下班结算：产品语义是“数据自动保存，仪式手动触发”。下班前首页不显示结算 CTA；下班后未结算时，progress track 下方显示「下班！领今天的窝囊费」，但不自动弹窗、不红点追赶、不连续催。点击进入全屏 settlement overlay，三阶段动画 — 中心金币雨爆开（heavy 触感）→ 结算卡 spring-in、金额从 0 滚到今日金额 → 「存入资产 / 分享卡片」action 行 ease-in；可随时跳过。卡片含金额、忍耐指数（1-4 星）、已忍时长、连续打工天数（封顶 60）、动态文案、今日最佳忍耐时刻、累积窝囊费总额。「今日最佳忍耐时刻」quote 卡支持长按 0.4s 撕碎换文案（rigid 触感 + id-driven transition）。每日记录会照常自动持久化；只有「存入资产」会额外执行 `markTodaySettled()` 并触发个人时间状态。App 启动或回到前台不会自动结算；用户不点也不会丢当天数据。「分享卡片」复用已有 `ImageRenderer` 管线，输出 `DailySettlementShareCard` 系统分享图。结算文件集中在 `WNF/DailySettlement.swift`。
- 个人时间模式：用户完成「存入资产」后当天首页切换为个人时间态 — StatusChip 文案改为「今日已下班 · 个人时间」，CTA 改为「今日已下班 · 再看一眼 / 今日窝囊费已入账，剩下都是你的时间」（带 ✓ 图标）；其它数字（金额 / 进度 / 时长）保持实时同步。状态来自 `WageState.isTodaySettled`，跨日自动重置。持久化键 `wnf.settlement.lastCompletedDateKey`。
- 下班结算提醒（可选 / 默认关闭）：「我的」页 `提醒` section 提供开关；开启后 `ClockOutReminderService` 会按选中工作日 + 下班时间调度 `UNCalendarNotificationTrigger` 本地通知；权限被系统拒绝时 Settings 内会展示打开系统通知设置的引导。提醒文件集中在 `WNF/ClockOutReminder.swift`。
- 底部 tab 切换：页面内容按 tab 顺序横向滑入/滑出，并与胶囊选中态同步过渡。
- 首次启动引导：4 屏 SwiftUI onboarding、第一页参考大图优先的 intro 布局、跳过/返回/分页控制、月薪/作息/午休设置和最终确认。
- 记录页周 / 月 / 年切换、柱状图选中态、成就和徽章模块；金额来自 `WageState` 暴露的 SQLite 每日明细 + 月汇总，今日金额按记录页聚合快照计入，跨日或 App 离开活跃前台时按日期 upsert 本机 SQLite，并暂停跨日计时器；回到活跃前台会刷新日期并重建计时器，多天未打开时会补齐中间日期。
- 我的页月薪和每月工作日支持 `- / +` 微调，也支持点中间数字弹出快速输入框；时间、午休和加班状态可编辑，上下班时间会保持“下班晚于上班”的有效组合。
- Widget：`WNFWidget` 支持 `.systemSmall`、`.systemMedium`、`.accessoryRectangular`、`.accessoryInline`，使用空 stub `AppIntentConfiguration` 预留后续 per-widget 配置；gallery/placeholder 使用固定示例值，不读取真实工资；真实 timeline 只读 App Group snapshot，按快照里的作息/费率/工作日集合生成分钟级 future entries，下一次 reload 放到下个选中工作日起点，并尊重 App 隐私模式把金额显示为 `¥•••.••`。
- `WNF/WageState.swift` 保留共享 `ObservableObject`、设置读写、`liveDay(at:)` 工作日门控、跨日快照、记录变更 `recordsRevision` 和补记生命周期；`WNF/DailyRecordStorage.swift` 承载 `StorageKey`、`DailyWageRecord`、`MonthlyRecordSummary`、SQLite store、旧 UserDefaults JSON/envelope 迁移、迁移备份和加锁复用的 JSON coder；`WNF/WageCalculator.swift` 承载 `WageDay` / `WorkStatus` / 纯工资计算和时间组件工具，`includeOvertime` 只影响下班后的实时金额是否继续增长，午休只扣与工作时段重叠的部分，无效上下班区间返回零值结果；`WNF/WorkStatusPresentation.swift` 承载状态展示文案和吉祥物资源名；`WNF/WageFormatting.swift` 承载金额与时长格式化。每日记录迁移到 App Group SQLite，近 400 天保留每日明细，更早记录折叠成月汇总；旧版 `wnf.records.daily` / recovery payload 在首次可读迁移时写入 App Group 备份 JSON 并清理大块 `UserDefaults` payload；跨日关闭和补记会读取 `wnf.records.lastObservedSnapshot` 中的上次观察设置，避免今天的薪资/作息设置追溯改写历史估算；秒级金额刷新限制在首页本地 `TimelineView`，共享状态只在日期键跨日、记录或设置变化时发布；首次引导完成状态继续使用 `wnf.onboarding.completed`。
- `assets/mascot` 中的主吉祥物和 Cow pose 已接入 `WNF/Assets.xcassets`。
- 首页视频源来自 `/Users/shelingzhao/Documents/窝囊费素材/精灵图/打电脑透明.mov` 和 `/Users/shelingzhao/Documents/窝囊费素材/精灵图/无聊透明.mov`，当前以 `WNF/home-typing.mov`、`WNF/home-bored.mov` 打包进 app resources。

引导页 hero 图位于 `WNF/Assets.xcassets`，源文件来自 `/Users/shelingzhao/Documents/窝囊费素材/引导/`：

- `p1.png` -> `OnboardingP1.imageset/onboarding-p1.png`
- `p2.png` -> `OnboardingP2.imageset/onboarding-p2.png`
- `p3午休.png` -> `OnboardingLunchSleep.imageset/onboarding-lunch-sleep.png`
- `p3睡醒.png` -> `OnboardingLunchWake.imageset/onboarding-lunch-wake.png`
- `p4.png` -> `OnboardingP4.imageset/onboarding-p4.png`

这些 PNG 必须保持 `1536 x 1024` 和 alpha 通道。替换后先用 `sips -g pixelWidth -g pixelHeight -g hasAlpha <file>` 检查目标 asset，再构建。

## Validation

构建：

```sh
xcodebuild -project WNF.xcodeproj -scheme WNF -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

单测与覆盖率：

```sh
xcodebuild test -project WNF.xcodeproj -scheme WNF -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -enableCodeCoverage YES
xcrun xccov view --report <latest WNF xcresult>
```

## Source of Truth

当前实现中的主令牌来自 `assets/source/shared.jsx`，根页面的运行时样式来自 `brand-tokens.css`。如果视觉规范和源码出现差异，以 `brand-tokens.css` 和 `design-tokens.json` 作为交付后的实现基准。
