# WNF · 窝囊费

## 1. 身份卡

上班时薪实时滚动的原生 SwiftUI iOS App。已上架 App Store（ASC App ID `6780135826`）。

| 项 | 值 |
|---|---|
| 二进制版本 | 以 `WNF.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 为准（当前 1.1 / 2） |
| 可编辑 ASC 版本 | 1.2（`metadata/version/1.2`） |
| 工程 | `WNF.xcodeproj` |
| 已跟踪 scheme | 只有 `WNF`（`WNF.xcodeproj/xcshareddata/xcschemes/WNF.xcscheme`）。`xcodebuild -list` 里可能出现本地自动生成的 `WNFWidget`，不要 check-in |
| Targets | `WNF` / `WNFWidget` / `WNFTests` / `WNFUITests` |
| Bundle IDs | `com.wonangfei.app` · `.widget` · `.tests` · `.uitests` |
| App Group | `group.com.wonangfei.app`（`WNFShared.appGroupID`） |
| 最低系统 | iOS 17.0；仅 iPhone、仅竖屏（`TARGETED_DEVICE_FAMILY = 1`，`Info.plist` `UISupportedInterfaceOrientations`） |
| 依赖 | 零第三方代码/包依赖；包含 3 个 OFL 字体二进制。Apple 框架 + 系统 SQLite（`OTHER_LDFLAGS = -lsqlite3`）+ `WNF/Fonts/` 下三份 TTF |

文案：短、自嘲、具体（如「再忍忍，钱在涨。」）。禁用「提升效率」「智能洞察」「数据驱动」。分支前缀只有 `feat/`（行为）· `fix/`（缺陷）· `tweak/`（视觉/文案/手感/素材）。色板只活在 `WNFTheme`，不是 CSS。

## 2. 五分钟启动

唯一命令：

```sh
./scripts/wnf verify
```

需要 macOS、Xcode、iOS 26.5 runtime。默认 destination 是 `platform=iOS Simulator,name=iPhone 17,OS=26.5`。失败时先跑 `./scripts/wnf doctor` 看环境含义，不要另写 xcodebuild 菜谱。

UI 测试经 `UITestSupport.launchMainShell()` 传入启动参数 `-wnf.onboarding.completed` 跳过引导，**不必**先在模拟器里点完 Onboarding。

## 3. 权威来源矩阵

| 事实 | 唯一所有者 |
|---|---|
| 构建/测试命令 | `scripts/wnf` |
| targets、版本、bundle ID | `project.pbxproj` |
| UserDefaults keys | `StorageKey` |
| 生产默认值 | `Default` in `WageState.swift` |
| App/Widget schema 与状态 label | `WidgetShared.swift`（`WorkStatus.label`） |
| 活跃持久化 | `DailyRecordSQLiteStore` |
| 公共法务内容 | `docs/privacy.html` / `docs/terms.html` / `docs/acknowledgements.html` |
| 当前 ASC 编辑内容 | `metadata/version/1.2` |
| 历史 ASC 快照 | `metadata/version/1.0` / `1.1`（远端不可变快照） |
| 许可 | `docs/acknowledgements.html` |

不要把 key 表、月薪默认值或 xcodebuild 菜谱再抄一份到别处。

## 4. 运行架构

`WNFApp` → `WageState` → `RootView`。

- App 把当日快照写入 App Group 键 `wnf.widget.wage.snapshot.v1`（`WNFWidgetSnapshotWriter` / `WNFShared.widgetSnapshotKey`）；`WNFWidget` 只读，永不回写。Widget 预览用 `WNFWidgetSnapshot.sample`，视图保留 `containerBackground(for: .widget)`。
- 同一汇流点调用 `WNFLiveActivityController.reconcile` 更新灵动岛。
- 活跃存储是 App Group SQLite `DailyRecords.sqlite`（`DailyRecordSQLiteStore`）：近 `retainedDailyRecordCount`（400）天每日明细，更早收成月汇总。旧 UserDefaults JSON 只是迁移路径。
- 跨日：离开 `.active` 时 `WageState.persistCurrentDaySnapshot()`；`currentDate` 前进时 `advanceCalendarDay` 关闭旧日，并按 last-observed 设置补记中间日。
- `RecordsView` 周/月/年图必须从 `RecordAggregationInput` 聚合，不要写死倍率。
- `FoundationModels` 只在具备能力的 iOS 26+ 设备上给气泡文案（`BubbleQuoteEngine`）；否则用静态 quotes。不是网络依赖。

跨 target 唯一共享源：`WNF/WidgetShared.swift`（schema + `WorkStatus` + Live Activity attributes）。

| 层 | 文件 | 职责 |
|---|---|---|
| 入口 | `WNFApp.swift` → `RootView.swift` | scene / 快照汇流；三页果冻 pager |
| 状态 | `WageState.swift` | 共享 `ObservableObject`：设置、当日计算、记录、结算旗 |
| 领域 | `WageCalculator.swift` · `DailyRecordStorage.swift` · `DailySettlement.swift` | 纯工资数学；SQLite + 旧 JSON 迁移；结算派生 |
| 页面 | `HomeView.swift` · `RecordsView.swift` · `SettingsView.swift` · `OnboardingView.swift` | 首页 / 记录 / 我的 / 首启引导 |
| 共享 | `Theme.swift` · `SharedViews.swift` · `WageFormatting.swift` · `WorkStatusPresentation.swift` | token、控件、格式化、quotes / 吉祥物（label 来自 `WorkStatus.label`） |
| 特效 | `ShaderFX.swift` + `WNFShaders.metal` + `GenieEffect.metal` · `OdometerText.swift` · `PagerShell.swift` | 着色器包装、滑轮数字、pager / 手势仲裁 |
| 凭证 | `Voucher.swift` · `ShareCard.swift` | 公文票据族、战报卡 genie |
| 外延 | `WidgetSnapshotWriter.swift` · `LiveActivityController.swift` · `ClockOutReminder.swift` · `Legal.swift` | 快照写入、灵动岛、下班提醒、法务 WebView |
| 其它 | `HomeMascotVideoSessionCoordinator.swift` · `BubbleQuoteEngine.swift` | 吉祥物视频会话、气泡文案 |
| Widget | `WNFWidget/WNFWidget.swift` | 只读镜像；gallery 用 sample |
| 测试 | `WNFTests/` · `WNFUITests/` | 工资/存储/结算/Widget/法务；`JellyTourUITests.testGrandTour` 巡演 |

## 5. 不可破坏契约

结算语义：**数据自动保存，仪式手动触发**。不自动弹窗、不红点追赶、不连续催。只有「存入资产」把当天写成已结算；X / 点屏外 / 跳过都不算完成。个人时间态看 `WageState.isTodaySettled`。

| 约束 | 原因 | 所有者 |
|---|---|---|
| `JellyStretch` 是普通 transform，**不是** `distortionEffect` | shader layer effect 无法栅格化首页吉祥物的 `AVPlayerLayer` | `ShaderFX.JellyStretch` |
| Odometer 必须传 `maxWidth` | `scaleEffect` 只缩小视觉，view 仍声明自然宽度；大数字会撑开 `VStack` 把 TopBar 尾钮挤出屏 | `OdometerText` / `OdometerMoneyText` |
| `TopBar` 必须在页面 `ScrollView` **之外** | scroll 的 delayed-touch + pager `simultaneousGesture` 会吞掉点击 | `TopBar`（`HomeView` / `RecordsView` / `SettingsView`） |
| 首页背景/同层装饰的固有尺寸不得超过页面 | 过大的 sibling 会撑大布局、居中内容、挤走 TopBar；装饰放进 `.background` 并 page-sized + clip | `HomeView` · pager `.clipped()`（`RootView`） |
| 任何 `RecordsView` / `BarChart` 预览必须注入 `HorizontalGestureArbiter()` | 缺了会崩；生产由 `RootView` 注入 | `HorizontalGestureArbiter`（`PagerShell`） |
| `WNFNumberPadSheet.initialText` 在 `.sheet` 内容里调 provider | 捕获的 `@State` 会 stale | `WNFNumberPadSheet` |
| 常量黄面上的字用 `inkFixed`，不用 `ink` | `ink` 深色模式翻成奶油，黄底上被冲淡 | `WNFTheme.inkFixed` |
| 金币层挂 `backgroundPreferenceValue`，不要改回 overlay | 掉落金币不得盖住进度标签和气泡 | `HomeView` |
| `WNFConversion` 按日历日确定，渲染时不得随机 | 同一天重渲必须同一张凭证 | `WNFConversion` |
| 公章骑年压月：盖日期/流水号，**永不**盖金额 | 发放凭证的视觉契约 | `DailySettlement` |
| 分享 spinner 预热是感知反馈，不是渲染并发修复 | `ImageRenderer` 仍在 MainActor 同步栅格化；先让一帧刷新 loading | `RootView.presentSystemShare` |
| 着色器时钟必须 `isActive` + Reduce Motion 门控 | 离屏 pager 页与 Reduce Motion 用户零帧 | `ShaderFX.GoldShimmer` 等 |
| 结算只从首页 Clock-Out CTA 触发 | `RootView` 独占 overlay；「存入资产」= `persistCurrentDaySnapshot()` + `markTodaySettled()` | `RootView` · `WageState` |
| 提醒 / Live Activity 的 reconcile 不进 View | 分别走 `WageState.reconcileClockOutReminder()` 与 `WNFLiveActivityController.reconcile` | `ClockOutReminderService` · `WNFLiveActivityController` |
| 六个工作状态文案只有一张表 | 改文案只改这一处 | `WorkStatus.label`（`WidgetShared.swift`） |
| 法务页只加载 bundle 内 HTML，无网络回退 | 设置里打开就是本地那份 | `Legal.swift` / `LegalWebNavigationPolicy` |
| Widget 永不写入 App Group | 单向数据流 | `WNFWidget` |
| 不自动弹出结算 | 仪式手动；没有红点追赶 | `RootView` |

圆角：10–12 控件 / 18 缩略图 / 22 卡片 / 28 hero / 999 胶囊。发丝描边 `WNFTheme.hairline`。不用 emoji 当功能图标。纸 overlay（战报 genie、结算层）强制浅色。首页滑轮保持系统圆体；`WNFTheme.display` 只标题/字标，`WNFTheme.mono` 走工资条数字。

## 6. 验证与变更矩阵

构建与测试命令的唯一入口是 `scripts/wnf`。不要把「N passed」写进文档或脚本。

| 改动 | 要跑 |
|---|---|
| 任何改动 | `./scripts/wnf build`（Debug） |
| 状态 / 存储 / 工资数学 / Widget | `./scripts/wnf test-unit`（L2） |
| 布局 / 手势 / 分享 / tab | `./scripts/wnf test-ui`（L3） |
| 发布相关、bundle 内容、签名无关的 Release 警告 | `./scripts/wnf release-check` |
| 交 PR / 交接 | `./scripts/wnf verify`（doctor → bootstrap → 静态门禁 → build → L2 → L3 → analyze → release-check） |

L3 依赖这些 a11y identifier，重构必须保留：`home.money` · `home.share` · `home.privacy` · `tab.home` / `tab.records` / `tab.settings` · `records.period.week|month|year` · `records.chart` · `share.cancel` · `settings.legal.privacy` / `settings.legal.terms`。`JellyTourUITests.testGrandTour` 兼布局护栏（TopBar 被挤出屏会 off-screen 失败）。`VoucherSnapshotTests` 是 render-smoke，不是参考图回归。

`./scripts/wnf store-check` 是可选的只读 ASC 核对，**不**计入 `verify`。

## 7. 发布边界

- ASC App ID `6780135826`；可编辑版本 1.2。不要把 `appInfoId` 写死进仓库（现场有两个 live ID，用时动态解析）。
- 公共 URL（ASC 已提交，**不可随意改**）：<https://rottesya.github.io/wonangfei/> · `/privacy.html` · `/support.html`
- 截图：`store/screenshots/`（规范 6.9" 竖屏 1320×2868 成套；不要把 `framed/` 当规范源）
- 元数据 diff 用 `asc metadata pull` / `plan`；cleanup / handover **禁止** `apply`、submit、远端删除
- 支持邮箱 `raysyadesu@gmail.com`；版权 © 2026 SHE LINGZHAO
- App 名「窝囊费」（不要加长成「窝囊费 - 上班实时数钱」）；副标题 `上班实时数钱，摸鱼也在回血`
- 关键词不要重复 App 名或副标题里已有的词
- 分级 4+ · 财务（`LSApplicationCategoryType` = `public.app-category.finance`）
- `metadata/version/1.0` 与 `1.1` 是已 `READY_FOR_DISTRIBUTION` 的快照，留下；商店文案只能改 1.2

## 8. 资产与许可

Asset Catalog 用 **imageset 名** 引用，不是 PNG 文件名。引导五张必须 1536×1024 + alpha：`OnboardingP1` · `OnboardingP2` · `OnboardingP4` · `OnboardingLunchSleep` · `OnboardingLunchWake`。白矩形 = alpha 丢了；软光晕是预期。

吉祥物视频 `home-typing.mov` / `home-bored.mov`：已经是 HEVC Main、1080×1080、30fps、约 15s、约 16 Mbps。剩下的是码率优化 + 视觉门禁，**不是**「转成 HEVC」。

字体：`WNFTheme.display` = 站酷庆科黄油体（标题）；`WNFTheme.mono` = JetBrains Mono（工资条数字）。SHA-256 与 OFL 全文在 `docs/acknowledgements.html`。

四个 stitchable shader 全活：`wnfGoldShimmer` / `wnfPaperGrain` / `wnfMoltenGold`（`WNFShaders.metal`）+ `genie`（`GenieEffect.metal`）。Swift 侧 `ShaderLibrary.<name>(…)`。不要把每个调用点再列一遍。

## 9. 已接受技术债

只留未完成项，且带退出标准。

- **ZCOOL subsetting**：全字形 TTF ~8.3MB，撑大 IPA。退出：可重复的 glyph corpus、动态白名单、许可文本保留、有视觉回归。
- **视频码率**：两份 HEVC 合计约 59MB（约 16 Mbps），IPA 约 88MB。退出：6 或 8 Mbps 的 `hvc1` 无音轨，时长/帧率/尺寸不变，loop/seek 正常，SSIM≥0.98，单文件≤15MB，Release 模拟器 bundle ≤62MB；达不到就留原片。
- **Git 历史包**约 188MB（已删的 `assets/`、`HomeSprite.mov`、旧 mp4）。未经所有者批准不要改写历史，不是一句 `git filter-repo` 的事。
- **无 CI**：验证就是 `./scripts/wnf verify`。
- Live Activity UI 是方案无关的黑金工牌（`WNFLiveActivity` / `LiveActivityPalette`），不要让它跟 light/dark。
- 引导 `TabView(.page)` 与法务 `NavigationStack` sheet：已接受的 stock。
