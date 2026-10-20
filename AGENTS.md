# WNF · 窝囊费

上班时薪实时滚动的原生 SwiftUI iOS App。已上架 App Store（ASC App ID `6780135826`）。只做 iPhone、竖屏，最低 iOS 17.0。零第三方代码依赖：Apple 框架、系统 SQLite、`WNF/Fonts/` 里三份 OFL 字体。

交接只看这一份。工程、代码和资源各自拥有事实；`scripts/wnf` 检查它们是否还对得上。某次验证的结果写在那次运行的 `manifest.json`，不写进本文。

## 开始工作

具备所需 Xcode 组件的机器，用下面这一条启动正确流程，并在失败时直接看到是哪一段：

```sh
./scripts/wnf verify
```

失败先看 `./scripts/wnf doctor`。doctor 会执行 Metal 编译器；缺组件时它停在构建之前，并打印安装命令。脚本不下载 Xcode、runtime 或 Metal toolchain。

默认模拟器由脚本里的设备名和 runtime 版本派生。`WNF_DESTINATION` 只接受 `./scripts/wnf help` 里的两种形式。`.xcodebuildmcp/config.yaml` 是可选工具配置，不是第二套验证配置。分支前缀：`feat/` 行为，`fix/` 缺陷，`tweak/` 视觉、文案、手感、素材。

UI 测试经 `UITestSupport.launchMainShell()` 传入 `-wnf.onboarding.completed` 跳过引导。每次启动另带一个新的 `-wnf.test.stateID`。

## 事实归谁

| 事实 | 所有者 |
|---|---|
| 构建、测试、bootstrap、环境判断 | `scripts/wnf` |
| target、版本、bundle ID、链接设置 | `WNF.xcodeproj/project.pbxproj` |
| App 私有持久化键 | `StorageKey` |
| App Group、Widget 快照键、共享模型 | `WNFShared` / `WidgetShared.swift` |
| 生产默认值 | `WageState.swift` 的 `Default` |
| 六个工作状态文案 | `WorkStatus.label` |
| 迁移与保留策略 | `DailyRecordSQLiteStore` |
| 首页正在播放的视频 | `HomeMascotVideoClip.all` |
| 气泡固定文案 | `WorkStatusPresentation.quotes` |
| 公共法务与字体许可 | `docs/` 里对应 HTML |
| 当前可编辑商店文案 | `metadata/version/1.2` |

已跟踪 scheme 只有 `WNF`。`xcodebuild -list` 可能多一个本地生成的 `WNFWidget`，不要 check-in。历史商店快照留在 `metadata/version/1.0` 和 `1.1`。

## 运行架构

```text
WNFApp
  ├─ 持有 WageState，处理 scene 生命周期
  ├─ RootView → 引导 / 首页 / 记录 / 设置 / 独占结算 overlay
  └─ 当日快照汇流 → WidgetSnapshotWriter + LiveActivityController

WageState
  ├─ WageCalculator：工资计算
  ├─ ClockOutRuntimeEngine：截止、加班、关闭与结算状态
  ├─ DailyRecordSQLiteStore：明细、月汇总、旧数据迁移
  └─ ClockOutReminderService：提醒协调

WNFWidget
  └─ 只读共享快照，通过 WidgetShared 的规则投影
```

`DailySettlement.swift` 同时有结算模型和 SwiftUI 展示。`RecordsView.swift` 同时有 `RecordAggregationInput` 和记录页；周/月/年图从这里聚合。跨 target 共享源是 `WNF/WidgetShared.swift`。Widget 只读 App Group，投影截止用 `overtimeEnd`；没有明确加班截止时仍封顶于正常下班时间。

气泡文案按 `WorkStatus` 在 `WorkStatusPresentation.quotes` 里本地轮换。下午那组的首句是「我先眯会儿，钱还在涨。」

## 改哪里

| 改动 | 入口 | 接着看 | 验证 |
|---|---|---|---|
| 工资、午休、工作日 | `WageCalculator` | `WageState` | `test-unit` |
| 到点、加班、跨日、结算 | `ClockOutRuntime` / `ClockOutFlow` | `RootView`、`WageState` | `test-unit`，再 `test-ui` |
| 记录图 | `RecordsView` 里的 `RecordAggregationInput` | 存储层 | `test-unit` |
| 首页视频 | `HomeMascotVideoClip.all` | `HomeMascotVideoController` | `release-check`，并看循环播放 |
| Widget / 灵动岛数据 | `WidgetShared.swift` | `WidgetSnapshotWriter`、`WNFLiveActivityController` | `test-unit` |
| 状态文案或气泡 | `WorkStatus.label` 或 `quotes` | 展示层只读这些表 | `test-unit` |
| 颜色、圆角、字 | `WNFTheme` | 见下面的色板边界 | `test-ui` |
| 商店文案 | `metadata/version/1.2` | 不要改 1.0 / 1.1 | `static-gate` |

## 不可破坏的契约

结算：到达当日 `ClockOutRuntimeState.baseWorkEndMinute` 后工资封顶。金额语义不依赖 App 一直活着；记录在 App 再次可执行时，经恢复、`reconcileClockOut()` 和跨日关闭补齐，不承诺进程已经终止时立刻写盘。同一天第一次进入到点状态，首页弹出下班决策（「下班！」「加班…」）。「下班！」立即 `confirmClockOut()`：保存快照并 `markTodaySettled()`，然后播放仪式。撕纸只是视觉收尾。关闭结算卡不撤销结算。「加班…」必须选明确时长，到期再停表并再弹一轮。关掉决策层则保持停表，这一轮不再自动强弹，首页留入口。次日不补弹旧日决策。当天的下班边界以运行快照为准；设置里改默认下班时间，从下一个工作日生效。个人时间态看 `WageState.isTodaySettled`。加班叠在同一基础时薪上，不改 `workdayMinutes` / `targetToday`。

| 规则 | 原因 | 所有者 |
|---|---|---|
| `JellyStretch` 用普通 transform | shader layer effect 栅格化不了首页 `AVPlayerLayer` | `ShaderFX.JellyStretch` |
| Odometer 传 `maxWidth` | `scaleEffect` 不减少布局宽度，大数字会把 TopBar 尾钮挤出屏 | `OdometerText` |
| `TopBar` 在页面 `ScrollView` 之外 | scroll 的 delayed-touch 和 pager 手势会吞掉点击 | `HomeView` / `RecordsView` / `SettingsView` |
| 首页装饰放进 page-sized `.background` 并裁剪 | 过大的同级视图会撑开布局、挤走 TopBar | `HomeView`、`RootView` |
| `RecordsView` / `BarChart` 预览注入 `HorizontalGestureArbiter()` | 缺了会崩；生产由 `RootView` 注入 | `PagerShell` |
| `WNFNumberPadSheet.initialText` 在 `.sheet` 内容里取 | 外面捕获的 `@State` 会过期 | `WNFNumberPadSheet` |
| 常量黄面上的字用 `inkFixed` | `ink` 在深色模式变成奶油，黄底上看不清 | `WNFTheme.inkFixed` |
| 金币层用 `backgroundPreferenceValue` | 掉落金币要留在进度标签和气泡下面 | `HomeView` |
| `WNFConversion` 按日历日确定 | 同一天重复渲染必须是同一张凭证 | `WNFConversion` |
| 公章盖日期和流水号 | 发放凭证不把章盖在金额上 | `DailySettlement` |
| 分享 spinner 先让一帧刷新 | `ImageRenderer` 仍在主线程同步栅格化 | `RootView.presentSystemShare` |
| 着色器时钟看 `isActive` 和 Reduce Motion | 离屏页和减少动态效果的用户不空转 | `ShaderFX` |
| 结算 overlay 只由 RootView 管 | 「下班！」就是 `confirmClockOut()` | `RootView`、`WageState` |
| 提醒、灵动岛、下班运行态不在 View 里 reconcile | 各自走自己的控制器 | `WageState`、`WNFLiveActivityController` |
| 六个状态文案只有 `WorkStatus.label` | Widget 样例也用这张表 | `WidgetShared.swift` |
| 法务页只加载 bundle 内 HTML | 设置里打开的就是本地那份 | `Legal.swift` |
| Widget 不写 App Group | 快照单向流出 | `WNFWidget` |
| 到点决策同一 revision 只自动弹一次 | 关掉后首页留入口，不追赶 | `RootView`、`ClockOutPhase` |

色板：App 用 `WNFTheme`。Widget 用自己的 `WidgetPalette`。灵动岛用固定的黑金 `LiveActivityPalette`，不跟浅色/深色走。圆角：10–12 控件 / 18 缩略图 / 22 卡片 / 28 hero / 999 胶囊。发丝描边 `WNFTheme.hairline`。功能图标不用 emoji。战报和结算这些纸 overlay 用浅色。首页滑轮用系统圆体；`WNFTheme.display` 给标题和字标，`WNFTheme.mono` 给工资条数字。

持久化：`StorageKey` 拥有 App 自己的 UserDefaults 键，包括引导完成键 `wnf.onboarding.completed`。`WNFShared` 拥有 App Group 和 Widget 快照键。启动参数 `-wnf.onboarding.completed`、`-wnf.test.now`、`-wnf.test.suppressClockOut`、`-wnf.test.stateID` 是测试入口。`WNF_SKIP_ONBOARDING` 由 RootView 读取。带了 `-wnf.test.stateID` 时，工资设置进 `wnf.uitest.<id>` 这套 UserDefaults，每日记录进 App 容器里的 `WNFUITest/<id>/DailyRecords.sqlite`。加班那条 UI 测试的两次启动共用同一个 id。

资源：引导五张图必须 1536×1024 且带 alpha：`OnboardingP1`、`OnboardingP2`、`OnboardingP4`、`OnboardingLunchSleep`、`OnboardingLunchWake`。首页视频集合以 `HomeMascotVideoClip.all` 为准，当前是 `home-typing`。四个 stitchable shader 都有 `ShaderLibrary` 调用：`wnfGoldShimmer`、`wnfPaperGrain`、`wnfMoltenGold`、`genie`。

升级兼容留着：旧 JSON / recovery / backup 路径、`DailyWageRecord` 缺字段默认值、Widget 旧 schema 和 `includeOvertime`。新装不走这些路径，不能据此删掉。

引导用 `TabView(.page)`，法务用 `NavigationStack` sheet。记录页顶上的黄色汇总是一整条，不是叠起来的色带。

## 验证

| 改动 | 命令 |
|---|---|
| 任何改动 | `./scripts/wnf build` |
| 状态、存储、工资、Widget | `./scripts/wnf test-unit` |
| 布局、手势、分享、tab | `./scripts/wnf test-ui` |
| bundle 内容、签名无关的 Release 构建 | `./scripts/wnf release-check` |
| 交接 | `./scripts/wnf verify` |

每次运行写入 `build/verification/runs/<run-id>/`。`build/verification/latest` 指向最近一次，失败也指向它。后面没跑到的阶段在 manifest 里是 `not_run`。`./scripts/wnf store-check` 只读核对商店元数据，不在 `verify` 里面，也不做 apply、submit 或远端删除。

L3 要保住这些 identifier：`home.money`、`home.share`、`home.privacy`、`tab.home`、`tab.records`、`tab.settings`、`records.period.week`、`records.period.month`、`records.period.year`、`records.chart`、`share.cancel`、`settings.legal.privacy`、`settings.legal.terms`、`clockout.overlay`、`clockout.confirm`、`clockout.overtime`、`clockout.dismiss`、`overtime.duration`、`overtime.confirm`、`overtime.cancel`。`JellyTourUITests.testGrandTour` 同时看守 TopBar 还在屏内。

这些检查各自证明的范围：

- 主流程 UI 测试主动跳过首次引导。
- `VoucherSnapshotTests` 只确认分享卡能栅格化、方向对，不拿参考图做像素回归。
- 静止截图不能证明首页视频循环，也不能证明切后台再回来。
- Widget 和灵动岛的模型测试不等于系统真的画出了那块界面。
- 默认巡演是一台模拟器上的一条路径。

## 发布与许可

可编辑版本是 `metadata/version/1.2`。不要把 `appInfoId` 写进仓库。公共 URL 已提交：<https://rottesya.github.io/wonangfei/>、`/privacy.html`、`/support.html`。截图规范源是 `store/screenshots/` 的 6.9 寸竖屏 1320×2868。支持邮箱 `raysyadesu@gmail.com`。版权 © 2026 SHE LINGZHAO。App 名「窝囊费」。副标题 `上班实时数钱，摸鱼也在回血`。关键词不要重复这个名字或副标题里已经有的词。分级 4+，类别 `public.app-category.finance`。

字体许可和 SHA-256 在 `docs/acknowledgements.html`。`WNFTheme.display` 是站酷庆科黄油体，`WNFTheme.mono` 是 JetBrains Mono。

## 还没做完

| 问题 | 影响 | 退出标准 |
|---|---|---|
| 站酷字体是全字形 TTF | IPA 被字库撑大 | 可重复的 glyph corpus、动态白名单、许可文本还在、有视觉回归 |
| 首页视频码率高 | 安装包偏大 | 6 或 8 Mbps 的无音轨 `hvc1`，时长、帧率、尺寸不变，循环和 seek 正常，SSIM≥0.98，单文件≤15MB，Release 模拟器 bundle ≤62MB。达不到就留原片 |
| Git 历史里留着已删的大资源 | 完整克隆比当前工作树大 | 所有者批准后才能改写历史 |
| 没有 CI | 验证靠本机 `./scripts/wnf verify` | 有一条和这个脚本等价的远端流水线 |
