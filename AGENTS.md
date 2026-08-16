# WNF · 窝囊费

## 1. 这是什么

上班时薪实时滚动的原生 SwiftUI iOS App。已上架 App Store（ASC App ID `6780135826`），仓库当前 `MARKETING_VERSION = 1.1` / `CURRENT_PROJECT_VERSION = 2`（`WNF.xcodeproj/project.pbxproj`）。单一 Xcode 工程，零第三方依赖（无 `Package.swift` / CocoaPods / npm）。

## 2. 30 秒跑起来

前置：Xcode + iOS 26.5 runtime + `iPhone 17` 模拟器。打开 `WNF.xcodeproj`，**只用 scheme `WNF`**（widget 经隐式依赖一并构建；`xcodebuild -list` 里第二个 `WNFWidget` 是 Xcode 本地自动生成的，仓库只 check-in 了 `WNF.xcscheme`）。

环境自检（预期：Xcode 版本 / iOS 26.5 / `iPhone 17` UDID / 4 个 target）：

```sh
xcodebuild -version && xcrun simctl list runtimes | grep "iOS 26.5" \
  && xcrun simctl list devices available | grep "iPhone 17 (" \
  && xcodebuild -list -project WNF.xcodeproj
```

构建与测试命令只在 §10 出现一次。XcodeBuildMCP 默认值在 `.xcodebuildmcp/config.yaml`（`scheme: WNF` / `simulatorName: iPhone 17` / `bundleId: com.wonangfei.app`）；路径与 UDID 已于 2026-08-16 按本机 checkout 修正。

## 3. 依赖拓扑

跨 target 唯一共享源：`WNF/WidgetShared.swift`（schema + Live Activity attributes）。Widget 只读 App Group，永不回写。

| 层 | 文件 | 职责 |
|---|---|---|
| 入口 | `WNFApp.swift` → `RootView.swift` | scene / 快照汇流；三页果冻 pager |
| 状态 | `WageState.swift` | 共享 `ObservableObject`：设置、当日计算、记录、结算旗 |
| 领域 | `WageCalculator.swift` · `DailyRecordStorage.swift` · `DailySettlement.swift` | 纯工资数学；SQLite + 旧 JSON 迁移；结算派生 |
| 页面 | `HomeView.swift` · `RecordsView.swift` · `SettingsView.swift` · `OnboardingView.swift` | 首页 / 记录 / 我的 / 首启引导 |
| 共享 | `Theme.swift` · `SharedViews.swift` · `WageFormatting.swift` · `WorkStatusPresentation.swift` | token、控件、格式化、状态文案 |
| 特效 | `ShaderFX.swift` + `WNFShaders.metal` + `GenieEffect.metal` · `OdometerText.swift` · `PagerShell.swift` | 着色器包装、滑轮数字、pager / 手势仲裁 |
| 凭证 | `Voucher.swift` · `ShareCard.swift` | 公文票据族、战报卡 genie |
| 外延 | `WidgetSnapshotWriter.swift` · `LiveActivityController.swift` · `ClockOutReminder.swift` · `Legal.swift` | 快照写入、灵动岛、下班提醒、法务 WebView |
| 其它 | `HomeMascotVideoSessionCoordinator.swift` · `BubbleQuoteEngine.swift` | 吉祥物视频会话、气泡文案 |
| Widget | `WNFWidget/WNFWidget.swift` | 只读镜像；gallery 用 `WNFWidgetSnapshot.sample` |
| 测试 | `WNFTests/WageEngineTests.swift` · `VoucherSnapshotTests.swift` · `WNFUITests/JellyTourUITests.swift` | 工资/存储/结算/Widget；凭证 render-smoke；UI 巡演 |

`RecordsView` 周/月/年图必须从 `RecordAggregationInput`（`recordsRevision` + `dailyRecords` + 当日记算，`RecordsView.swift:44-117`）聚合，不要写死倍率。

## 4. 构建与身份事实

| 项 | 值 |
|---|---|
| Targets | `WNF` / `WNFWidget` / `WNFTests` / `WNFUITests` |
| Bundle IDs | `com.wonangfei.app` · `.widget` · `.tests` · `.uitests` |
| App Group | `group.com.wonangfei.app`（`WidgetShared.swift:4`） |
| Team | `TZ2T95MG29` |
| 最低系统 | iOS 17.0；`TARGETED_DEVICE_FAMILY = 1`（仅 iPhone、仅竖屏，`Info.plist` `UISupportedInterfaceOrientations`） |
| 语言 | Swift 5.0 |
| SQLite | app target `OTHER_LDFLAGS = -lsqlite3`（`project.pbxproj`） |

## 5. 数据与持久化

活跃存储是 App Group SQLite `DailyRecords.sqlite`（`DailyRecordSQLiteStore`，`DailyRecordStorage.swift:156`）：近 400 天每日明细（`:157`）+ 更早月汇总。`wnf.records.daily*` 与 recovery / rawBackup 键（`:22-30`）只是旧 UserDefaults JSON 的迁移路径，不是活跃存储。

生产默认值与已归档网页原型 `TWEAK_DEFAULTS` 对齐（`WageState.swift` `Default`，`:668-680`）：月薪 `18000`、每月工作日 `26`、09:30–18:30、午休 12:00–13:00、周一到周五、计加班、提醒关、Live Activity 开。

UserDefaults 键（定义在 `DailyRecordStorage.swift:8-32`，引导完成在 `RootView.swift:93`）：

| 键 | 默认 |
|---|---|
| `wnf.settings.monthlySalary` | 18000 |
| `wnf.settings.workdaysPerMonth` | 26 |
| `wnf.settings.workStartMinute` / `workEndMinute` | 570 / 1110 |
| `wnf.settings.lunchStartMinute` / `lunchEndMinute` | 720 / 780 |
| `wnf.settings.hasLunchBreak` | true |
| `wnf.settings.includeOvertime` | true |
| `wnf.settings.privacyMode` | false |
| `wnf.settings.selectedWeekdays` | `[0,1,2,3,4]`（周一=0） |
| `wnf.settings.clockOutReminderEnabled` | **false** |
| `wnf.settings.liveActivityEnabled` | **true** |
| `wnf.settlement.lastCompletedDateKey` | 无 |
| `wnf.onboarding.completed` | false |
| `wnf.records.lastObservedDateKey` / `lastObservedSnapshot` | 跨日回填用上次观察设置，避免今天的薪资改写历史（`WageState.swift:327-363`） |

跨日：`WNFApp` 离开 `.active` 时 `persistCurrentDaySnapshot()`（`WNFApp.swift:19`，`WageState.swift:227`）；`currentDate` 前进时 `advanceCalendarDay` 关闭旧日并按 last-observed 设置补记中间日。

下班提醒只经 `WageState.reconcileClockOutReminder()`（`:526`）调度——设置变更（`clockOutReminderEnabled` / `workEnd` / `selectedWeekdays`）和 `scenePhase == .active`（`WNFApp.swift:16`）必须走这里，不要在 View 里直接排程。

⚠️ 跨 target 文案同源：六个工作状态文案的所有者是 `WorkStatusPresentation.swift:9-63`（`今天不用窝囊` / `尚未开工` / `上午搬砖中` / `午休回血` / `下午挺挺` / `今日通关`）。`WidgetShared.swift:255-269` 的 `projectedStatusLabel` 硬编码了一份拷贝；改文案必须同时改两处。

## 5b. 单向数据流

`WageState` → `WNFApp.writeWidgetSnapshot()`（`WNFApp.swift:61-79`）→ App Group 键 `wnf.widget.wage.snapshot.v1`（`WidgetShared.swift:5`）→ `WNFWidget` 只读。Live Activity 走同一汇流点（`:79` + `LiveActivityController.swift:15`）。Widget 预览必须用固定 sample，所有 widget 视图保留 `containerBackground(for: .widget)`。

## 6. 不变量与陷阱

| 约束 | 为什么 | 锚点 |
|---|---|---|
| `JellyStretch` 是普通 transform，**不是** `distortionEffect` | shader layer effect 无法栅格化首页吉祥物的 `AVPlayerLayer` | `ShaderFX.swift:58-61` |
| Odometer 必须传 `maxWidth` | `scaleEffect` 只缩小视觉，view 仍声明自然宽度；大数字会撑开 `VStack` 把 TopBar 尾钮挤出屏 | `OdometerText.swift:16-19,124-128` |
| `TopBar` 必须在页面 `ScrollView` **之外** | scroll 的 delayed-touch + pager `simultaneousGesture` 会吞掉点击（隐私眼曾在记录/我的页静默失效） | `HomeView.swift:92-98` · `RecordsView.swift:420-427` · `SettingsView.swift:31-36` |
| 首页背景/同层装饰的固有尺寸不得超过页面 | 过大的 sibling 会撑大布局、居中内容、挤走 TopBar；装饰放进 `.background` 并 page-sized + clip | `HomeView.swift:26` · pager `.clipped()` `RootView.swift:345` |
| 任何 `RecordsView` / `BarChart` 预览必须注入 `HorizontalGestureArbiter()` | 缺了会崩；生产由 `RootView` 注入 | `RootView.swift:69,346` · `RecordsView.swift:974` · `PagerShell.swift:10` |
| `WNFNumberPadSheet.initialText` 在 `.sheet` 内容里调 provider | 捕获的 `@State` 会 stale | `SettingsView.swift:403-408` |
| 常量黄面上的字用 `inkFixed`，不用 `ink` | `ink` 深色模式翻成奶油，黄底上被冲淡 | `Theme.swift:19,43` |
| 金币层挂 `backgroundPreferenceValue`，不要改回 overlay | 掉落金币不得盖住进度标签和气泡 | `HomeView.swift:139-142` |
| `WNFConversion` 按日历日确定，渲染时不得随机 | 同一天重渲必须同一张凭证 | `Voucher.swift:7-8,107-112` |
| 公章骑年压月：盖日期/流水号，**永不**盖金额 | 发放凭证的视觉契约 | `DailySettlement.swift:859` |
| 分享 spinner 预热是感知反馈，不是渲染并发修复 | `ImageRenderer` 仍在 MainActor 同步栅格化；先让一帧刷新 loading | `RootView.swift:549-558` |
| 着色器时钟必须 `isActive` + Reduce Motion 门控 | 离屏 pager 页与 Reduce Motion 用户零帧 | `ShaderFX.swift:6-16` · `RootView.swift:317` |
| 结算只从首页 Clock-Out CTA 触发 | `RootView` 独占 overlay；「存入资产」= `persistCurrentDaySnapshot()` + `markTodaySettled()` | `RootView.swift:319,535` · `WageState.swift:113` |
| 提醒 / Live Activity 的 reconcile 不进 View | 分别走 `WageState.reconcileClockOutReminder()` 与 `WNFLiveActivityController.reconcile` | `ClockOutReminder.swift:6` · `LiveActivityController.swift:15` |

## 7. 产品与品牌契约

结算语义：**数据自动保存，仪式手动触发**。不自动弹窗、不红点追赶、不连续催。只有「存入资产」把 `lastSettlementDateKey` 写成当天（`WageState.swift:109-114`）；X / 点屏外 / 跳过都不算完成。个人时间态看 `isTodaySettled`。

色板（理由：丧萌、自嘲、金币感、工位回血、黑黄强对比；避免高级灰和企业感）：窝囊黄 `#FFC83D` · 反思黑 `#0D0D0D` · 奶油白 `#FFF6E5` · 电光青 `#00E5FF` · 热辣珊瑚 `#FF5C57`。实现是 `WNFTheme`（`Theme.swift:10-36`），不是 CSS。

文案：短、自嘲、具体（如「再忍忍，钱在涨。」）。禁用「提升效率」「智能洞察」「数据驱动」。

圆角：10–12 控件 / 18 缩略图 / 22 卡片 / 28 hero / 999 胶囊。发丝描边 `0.5px`（`Theme.swift:28` `hairline`）。不用 emoji 当功能图标。

分支前缀只有 `feat/`（行为）· `fix/`（缺陷）· `tweak/`（视觉/文案/手感/素材）。

## 8. 设计系统

`WNFTheme` 全是动态色（浅 = 原品牌，深 = 暖棕黑「熄灯的工位」，从不用中性灰）：

- `ink` 文字（深色翻奶油）
- `inkSurface` 黑卡**面**（深色仍暗：成就卡、tab 胶囊、`+¥1`）
- `inkFixed` 常量反思黑 — 黄面与凭证墨
- `surface` 白卡；`track` 进度槽；`paper` 凭证白，永不跟主题（`Theme.swift:40`）

纸 overlay（战报 genie、结算层）强制 `.environment(\.colorScheme, .light)`（`ShareCard.swift:270` · `DailySettlement.swift:378`）。

字体经 `Info.plist` `UIAppFonts`：`WNFTheme.display` = 站酷庆科黄油体（只标题/字标，`Theme.swift:48`）；`WNFTheme.mono` = JetBrains Mono（工资条数字，`:53`）。首页滑轮刻意保持系统圆体。

自绘控件：`WNFNumberPadSheet`、`WNFTimePickerSheet` + `WNFSnapColumn`、`WNFToggle`（关轨走 `track`）。已接受的 stock：引导 `TabView(.page)`、法务 `NavigationStack` sheet。

## 9. 资产规则

Asset Catalog 用 **imageset 名** 引用，不是 PNG 文件名。在用：

| imageset | 使用点 |
|---|---|
| `CowFrontSad` / `CowThreeQ` | `WorkStatusPresentation.swift:17-72`；`CowThreeQ` 另见 `Voucher.swift:134` · `SharedViews.swift:10` |
| `HeroMascot` | `RecordsView.swift:710` · `SettingsView.swift:262` |
| `OnboardingP1` `P2` `P4` `LunchSleep` `LunchWake` | `OnboardingView.swift` |
| `AppIcon` / `AccentColor` | pbxproj `ASSETCATALOG_COMPILER_*` |

引导图五张必须 `1536 x 1024` + alpha。原外部素材目录已不在本机；只替换 catalog 内 PNG，再用：

```sh
sips -g pixelWidth -g pixelHeight -g hasAlpha WNF/Assets.xcassets/OnboardingP1.imageset/onboarding-p1.png
```

白矩形 = alpha 丢了；`OnboardingImagePanel` / `LunchImagePanel` 的软光晕是预期。

字体：`WNF/Fonts/{ZCOOLQingKeHuangYou-Regular,JetBrainsMono-Regular,JetBrainsMono-Bold}.ttf`。吉祥物视频：`home-typing` / `home-bored`（`HomeView.swift:524-527`），约 59M 未压缩 `.mov`，经 pbxproj Resources 进 bundle。

4 个 stitchable shader 全活：`wnfGoldShimmer` / `wnfPaperGrain` / `wnfMoltenGold`（`WNFShaders.metal`）+ `genie`（`GenieEffect.metal`）。Swift 侧 `ShaderLibrary.<name>(…)`。

## 10. 验证手册

```sh
# L1 · 编译（~60s）— 任何改动后必跑
xcodebuild -project WNF.xcodeproj -scheme WNF \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build

# L2 · 单元测试（~90s）— 触及状态/存储/工资数学/Widget 时必跑
xcodebuild test -project WNF.xcodeproj -scheme WNF \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WNFTests

# L3 · UI 巡演（~3min）— 触及布局/手势/分享/tab 时必跑
xcodebuild test -project WNF.xcodeproj -scheme WNF \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WNFUITests
```

基线：L2 = 29 passed（27 个 Swift Testing `@Test` 在 `WageEngineTests.swift` + 2 个 XCTest 在 `VoucherSnapshotTests.swift`）。

前置，否则会把环境问题误判成回归：

- **L3** 不重置引导。`JellyTourUITests.testGrandTour`（`:15`）直接 `app.launch()`，全新模拟器会停在 `OnboardingView`，在找 `home.money`（`:26`）失败。跑 L3 前目标模拟器必须已完成引导（`wnf.onboarding.completed = 1`）。
- **L2** 的 `dateToday(hour:minute:)`（`WageEngineTests.swift:602-608`）用真实 `Date()`。`WageStateSettlementTests` / `RecordsAggregationTests` 对当前星期几和挂钟时间敏感。

`VoucherSnapshotTests` 是 render-smoke，无参考图比对，不能当快照回归。设环境变量 `TEST_RUNNER_WNF_SNAPSHOT_DIR=<dir>`（`xcodebuild test` 会剥 `TEST_RUNNER_` 前缀，代码读 `WNF_SNAPSHOT_DIR`，`VoucherSnapshotTests.swift:13`）可把两张卡写成 PNG。

`testGrandTour` 兼布局护栏（TopBar 被挤出屏会 "off-screen" 失败）。可配 `xcrun simctl io 'iPhone 17' recordVideo --codec h264 --force tour.mov`。七个 a11y identifier 重构必须保留：`home.money` · `home.share` · `home.privacy` · `tab.<home\|records\|settings>` · `records.period.<week\|month\|year>` · `records.chart` · `share.cancel`。法务入口：`settings.legal.privacy` / `settings.legal.terms`。

## 11. 发布与 App Store

| 项 | 值 |
|---|---|
| ASC App ID | `6780135826` |
| `appInfoId` | `294998ba-df08-4211-854c-4219d0bde32a` |
| Team / AASA | `TZ2T95MG29` · `TZ2T95MG29.com.wonangfei.app`（`store/site/.well-known/apple-app-site-association`） |
| 营销 / 隐私 / 支持 | `https://rottesya.github.io/wonangfei/` · `/privacy.html` · `/support.html`（`docs/` = live GitHub Pages，ASC 已提交，**不可随意改 URL**） |
| 支持邮箱 | `raysyadesu@gmail.com` |
| 版权 | `© 2026 SHE LINGZHAO` |
| 名称 | 纯品牌「窝囊费」（不用「窝囊费 - 上班实时数钱」——Apple 偏好干净 App 名，搜索词放副标题和关键词） |
| 副标题 | `上班实时数钱，摸鱼也在回血` |
| 关键词 | 不要重复 App 名或副标题里已有的词（二者单独索引，重复浪费 100 字符配额） |
| 分级 / 分类 | 4+ · 财务（`LSApplicationCategoryType` = `public.app-category.finance`） |
| 截图 | 已提交在 `store/screenshots/`；6.9" 竖屏 `1320×2868` |

`metadata/` 是 asc CLI 的按版本分目录（`version/1.0/` 与 `1.1/` 都要留，差在 `whatsNew`）。**已知失败**（`.asc/reports/metadata-apply/failures-*.json`）：版本非可编辑态无法改 `privacyPolicyUrl` 与 `description`——`metadata apply` 必须跑在可编辑版本上。

法务两处必须同时改、保持字节一致：`WNF/Legal/{privacy,terms}.html`（App 内唯一来源，`Legal.swift:52-62`）与 `docs/{privacy,terms}.html`（GitHub Pages / ASC 隐私 URL）。App 内不再请求 `wonangfei.app`。

## 12. 已知技术债与已接受的妥协

- ZCOOL 全字形 TTF ~8.3MB，subsetting **待做**。
- 引导 `TabView(.page)` 与法务 `NavigationStack` sheet：已接受的 stock。
- `home-typing.mov` + `home-bored.mov` 合计 ~59M 未做 HEVC 压缩：**待做**（需实测画质）。
- 无 CI、无脚本：验证就是 §10 三层命令。
- Live Activity UI 是方案无关的「黑金工牌」，不要让它跟 light/dark（`WNFWidget.swift`）。
