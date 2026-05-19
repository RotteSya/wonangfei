# 窝囊费 Handoff Package

交付时间：2026-05-15  
交付范围：品牌色彩、字体、间距规范、组件库定义、互动原型源码、吉祥物与视觉参考资产。

## Package Map

- `WNF.xcodeproj`：原生 SwiftUI iOS 工程，可直接用 Xcode 打开、构建和运行。
- `WNF/`：SwiftUI App 源码、工资计算状态、Premium 买断、页面组件和 Asset Catalog。
- `WNFWidget/`：Widget extension，读取 App Group entitlement snapshot 和工资快照。
- `WNFTests/`：Premium 核心状态与导出相关单元测试。
- `WNFPremium.storekit`：本地 StoreKit 配置，商品 ID 为 `com.wonangfei.app.premium.lifetime`。
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
- 记录页：周 / 月 / 年分段控件、按本机每日记录聚合的可点柱状图、成就卡、徽章区；记录聚合读取本机每日记录 payload，但缓存 key 使用日期键、`recordsRevision` 和 live-day 设置，避免每次 body 重算都比较整份记录字典，也不订阅首页的秒级刷新。
- 我的页：月薪编辑、每月工作日编辑、周工作日选择、上下班时间、午休开关、加班开关和常驻 Premium 区；设置、主题预览、分享模板和锁屏 Widget 隐私选项保存在本机。
- Premium：一次性买断，解锁桌面/锁屏小组件、主题皮肤、截图分享模板和历史记录导出。

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
- Premium 分享模板：免费用户可预览模板入口但不能保存应用；购买后可持久化模板，分享卡导出使用已选模板。
- 底部 tab 切换：页面内容按 tab 顺序横向滑入/滑出，并与胶囊选中态同步过渡。
- 首次启动引导：4 屏 SwiftUI onboarding、第一页参考大图优先的 intro 布局、跳过/返回/分页控制、月薪/作息/午休设置和最终确认。
- 记录页周 / 月 / 年切换、柱状图选中态、成就和徽章模块；金额来自 `WageState` 暴露的 `wnf.records.daily` 每日快照，今日金额按记录页聚合快照计入，跨日或 App 离开活跃前台时写回本机，并暂停跨日计时器；回到活跃前台会刷新日期并重建计时器，多天未打开时会补齐中间日期。
- 我的页月薪和每月工作日支持 `- / +` 微调，也支持点中间数字弹出快速输入框；时间、午休和加班状态可编辑。
- Premium 买断：`PremiumEntitlementStore` 在 `WNFApp.init` 创建，启动 long-running `Transaction.updates` listener，依次处理 unfinished、current entitlements 和 product load；Paywall 使用全局 `PremiumPaywallController`，Restore 调用 `AppStore.sync()` 后刷新权益，退款入口只在 `beginRefundRequest` 返回 success 后记录审核中状态。
- Widget：`WNFWidget` 支持 `.systemSmall`、`.systemMedium`、`.accessoryRectangular`、`.accessoryInline`，使用空 stub `AppIntentConfiguration` 预留后续 per-widget 配置；gallery/placeholder 使用固定示例值，不读取真实工资；真实 timeline 只读 App Group snapshot，主 App 解锁不信任 snapshot。
- 历史导出：Premium 用户导出前会确认文件包含完整金额和工时数据；CSV 写入 UTF-8 BOM，JSON 使用 daily record schema 并包含 live today。
- `WNF/WageState.swift` 保留共享 `ObservableObject`、设置读写、跨日快照、记录变更 `recordsRevision` 和补记生命周期；`WNF/DailyRecordStorage.swift` 承载 `StorageKey`、`DailyWageRecord`、schema envelope、旧格式迁移、recovery-key 写入保护和加锁复用的 JSON coder；`WNF/WageCalculator.swift` 承载 `WageDay` / `WorkStatus` / 纯工资计算和时间组件工具；`WNF/WorkStatusPresentation.swift` 承载状态展示文案和吉祥物资源名；`WNF/WageFormatting.swift` 承载金额与时长格式化。每日记录以带 `schemaVersion` 的 JSON envelope 存入 `wnf.records.daily`，内部仍按日期键保存 `DailyWageRecord`，并用 `source` 区分 observed / backfilled；旧版裸字典会在读取时迁移并保留 raw backup，解码/编码失败会写系统日志，且失败后的写入会转到持久化的 recovery key，后续启动会优先读回该 recovery key，避免覆盖主 raw payload 或丢失恢复期新增记录；秒级金额刷新限制在首页本地 `TimelineView`，共享状态只在日期键跨日、记录或设置变化时发布；首次引导完成状态继续使用 `wnf.onboarding.completed`。
- `assets/mascot` 中的主吉祥物和 Cow pose 已接入 `WNF/Assets.xcassets`。
- 首页视频源来自 `/Users/shelingzhao/Documents/窝囊费素材/精灵图/打电脑透明.mov` 和 `/Users/shelingzhao/Documents/窝囊费素材/精灵图/无聊透明.mov`，当前以 `WNF/home-typing.mov`、`WNF/home-bored.mov` 打包进 app resources。

引导页 hero 图位于 `WNF/Assets.xcassets`，源文件来自 `/Users/shelingzhao/Documents/窝囊费素材/引导/`：

- `p1.png` -> `OnboardingP1.imageset/onboarding-p1.png`
- `p2.png` -> `OnboardingP2.imageset/onboarding-p2.png`
- `p3午休.png` -> `OnboardingLunchSleep.imageset/onboarding-lunch-sleep.png`
- `p3睡醒.png` -> `OnboardingLunchWake.imageset/onboarding-lunch-wake.png`
- `p4.png` -> `OnboardingP4.imageset/onboarding-p4.png`

这些 PNG 必须保持 `1536 x 1024` 和 alpha 通道。替换后先用 `sips -g pixelWidth -g pixelHeight -g hasAlpha <file>` 检查目标 asset，再构建。

## Premium Release Notes

- ASC 商品类型为 Non-Consumable，product ID 固定为 `com.wonangfei.app.premium.lifetime`。价格以 CNY 为基准自动换算大陆、港澳台和美国；大陆优先选 ¥18 price point，无则回退 ¥19，若 ¥17-¥20 均不可用则暂停提交并申请 custom price。
- Family Sharing v1 关闭；代码只把 `.purchased` 视为可解锁，`.familyShared` 仅记录诊断。开启 Family Sharing 后通常不可逆，后续必须经产品/发布负责人确认。
- 法务链接远程优先：`https://wonangfei.app/terms`、`https://wonangfei.app/privacy`；App bundle 内同时包含 `WNF/Legal/terms.html` 和 `WNF/Legal/privacy.html` 作为离线 fallback。Universal Link 使用 `https://wonangfei.app/premium`，`wonangfei://premium` 只做 fallback。
- 发布前仍需在外部完成：AASA 部署并在线验证、Associated Domains/App Group provisioning、Paid Apps Agreement、税务/银行、工信部 App 备案号、ICP/主体信息、软著、隐私政策 URL、客服联系方式、ASC App Privacy 和 IAP 元数据。

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

覆盖率目标为 `>= 80%`。2026-05-19 当前 focused 单测和 SwiftUI render coverage tests 为 51 个，通过率 51/51；`xccov` whole app target 覆盖率为 `85.12% (7723/9073)`。已覆盖 Premium core、mock StoreKit、verifier、unfinished、purchase pending/cancel/success、revoked、refund status、snapshot、preferences、Settings Premium presentation、export、deep link、工资公式、设置持久化、daily record envelope/legacy/corrupt/recovery storage、格式化、展示文案，以及 Settings/Records/Onboarding/Paywall/ShareCard/Root 的 SwiftUI 渲染路径。

## Source of Truth

当前实现中的主令牌来自 `assets/source/shared.jsx`，根页面的运行时样式来自 `brand-tokens.css`。如果视觉规范和源码出现差异，以 `brand-tokens.css` 和 `design-tokens.json` 作为交付后的实现基准。
