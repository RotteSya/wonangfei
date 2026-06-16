# Implementation Handoff

## Active Prototype Files

The runnable entry and live prototype files are:

- `WNF.xcodeproj` / `WNF/`：native SwiftUI iOS implementation of the current app design.
- `WNFWidget/`：Widget extension for desktop and lock-screen widgets.
- `WNFTests/`：unit tests.
- `WNFUITests/`：XCUITest UI tour (`JellyTourUITests`) that drives and films every interaction.
- `.xcodebuildmcp/config.yaml`：persisted XcodeBuildMCP defaults for the native app, including project, scheme, simulator, and bundle id.
- `index.html`：implemented static app shell. It renders the actual product screens, keeps the iPhone frame as the primary surface, exposes desktop/mobile control panels, persists local state, and links back to the handoff docs.
- `窝囊费.html`：entry shell, tweak state, iPhone frame, three core screens and comparison boards.
- `wonangfei.html`：same entry shell copied with an ASCII filename for safer handoff.
- `shared.jsx`：theme tokens, money/time math, reusable UI primitives.
- `home.jsx`：single-screen home hero.
- `stats.jsx`：interactive record page.
- `settings.jsx`：interactive settings/profile page.
- `cow.jsx`：8-pose mascot helper.
- `ios-frame.jsx`：status bar and device chrome support.
- `design-canvas.jsx`：Open Design preview canvas and artboards.
- `tweaks-panel.jsx`：internal preview controls.

Current `main` note: The app target ships with `WNFWidget` and `WNFTests`. The wage/settings core remains in the app target; there is still no `WageCore.swift` or `WageDisplayModel.swift` split. Settings and daily-record lifecycle stay in `WNF/WageState.swift`, while SQLite daily-record storage, wage calculation, formatting, and Widget snapshot writing are split into dedicated Swift files.

## Motion & Visual FX (feat/jelly-shell-and-gold-shaders)

A dedicated FX layer drives the home/records polish and the interactive shell. New sources:

- `WNF/WNFShaders.metal` — stitchable shaders: `wnfGoldShimmer` (diagonal glint sweep), `wnfPaperGrain` (static printed-paper grain), `wnfMoltenGold` (progress-bar liquid fill, carves the visible body + lapping crest out of a full-width rect). `GenieEffect.metal` (share-card warp) is unchanged.
- `WNF/ShaderFX.swift` — SwiftUI wrappers: `.goldShimmer/.paperGrain` modifiers, `JellyStretch` (`.jellyStretch(_:)`, a squash-&-stretch *transform* — deliberately not a `distortionEffect` so it composes over the mascot's `AVPlayerLayer`), `SquishButtonStyle` (`.buttonStyle(.squish)`), and the shared `WNFHaptics` generators. All shimmer/grain/molten clocks are `TimelineView(paused:)`, gated by page visibility (`isActive`) and `accessibilityReduceMotion`.
- `WNF/OdometerText.swift` — `OdometerMoneyText`, the home money readout: per-digit gas-pump wheels, `+¥1` rollover chips + soft haptic, gold shimmer. Sized by digit-count font tiers plus a deterministic `fitScale`/`maxWidth` layout cap so a large salary never clips or stretches the TopBar.
- `WNF/PagerShell.swift` — continuous `AppTabBar(progress:onSelect:)` (pill tracks fractional pager position 0…2, squishes at the rubber-band walls) and `HorizontalGestureArbiter` (resolves pager-swipe vs. chart-scrub for one touch).

Interactive shell (`WNF/RootView.swift`): the three tabs are one mounted `HStack` strip steered by a `simultaneousGesture` drag — directional axis lock, rubber-banded ends, velocity-seeded `interpolatingSpring` settle, jelly squash via `jellyStretch`, and `@GestureState` cancel recovery. Tab taps and swipes share `commitPager`/`selectTab` (rigid haptic + mascot-session forwarding). `HorizontalGestureArbiter` is injected as an `environmentObject`; `RecordsView`/`BarChart` previews must supply one.

Home (`WNF/HomeView.swift`): molten-gold progress bar, long-press coin fountain (reduce-motion gated), rotating thought bubble, pulsing live-status dot, over a plain `WNFTheme.bg` (the earlier drifting ambient glow was removed at the user's request). Records (`WNF/RecordsView.swift`): chart promoted under the hero, `PeriodSwitcher` matched-geometry segmented control, springy staggered bar grow-in, scrub-to-read with per-bar haptics, today-bar glow, grain hero card with breathing watermark, staggered card entrance.

UI driver/guard: `WNFUITests/JellyTourUITests.swift` (`testGrandTour`) walks every interaction with `TOUR-MARK` log markers; run under `simctl io recordVideo` to film. It depends on the accessibility identifiers listed in `AGENTS.md`.

## Native Onboarding

Source: `WNF/OnboardingView.swift`

- Four pages: app framing, salary setup, work/lunch setup, completion summary.
- Page 1 uses a dedicated intro layout with a taller `OnboardingP1` hero and no accessory hint card; pages 2-4 keep the compact hero plus setup/summary card pattern.
- `OnboardingImageStore` preloads and prepares hero images off the main path before display.
- `OnboardingImagePanel` handles static hero rendering for pages 1, 2, and 4.
- `LunchImagePanel` crossfades page 3 between `OnboardingLunchSleep` and `OnboardingLunchWake` based on `WageState.hasLunchBreak`.
- `OnboardingP1`, `OnboardingP2`, `OnboardingLunchSleep`, `OnboardingLunchWake`, and `OnboardingP4` are all asset-catalog image names. Their PNG files live under `WNF/Assets.xcassets`.

Hero asset mapping from the local material folder:

| Source file | App asset |
|---|---|
| `/Users/shelingzhao/Documents/窝囊费素材/引导/p1.png` | `WNF/Assets.xcassets/OnboardingP1.imageset/onboarding-p1.png` |
| `/Users/shelingzhao/Documents/窝囊费素材/引导/p2.png` | `WNF/Assets.xcassets/OnboardingP2.imageset/onboarding-p2.png` |
| `/Users/shelingzhao/Documents/窝囊费素材/引导/p3午休.png` | `WNF/Assets.xcassets/OnboardingLunchSleep.imageset/onboarding-lunch-sleep.png` |
| `/Users/shelingzhao/Documents/窝囊费素材/引导/p3睡醒.png` | `WNF/Assets.xcassets/OnboardingLunchWake.imageset/onboarding-lunch-wake.png` |
| `/Users/shelingzhao/Documents/窝囊费素材/引导/p4.png` | `WNF/Assets.xcassets/OnboardingP4.imageset/onboarding-p4.png` |

All five target PNGs are expected to remain `1536 x 1024` with `hasAlpha: yes`. Before handing off a replacement, compare source/target hashes when possible and run `sips -g pixelWidth -g pixelHeight -g hasAlpha` on the target asset-catalog files.

## Core State

Native sources:

- `WNF/WageState.swift`: shared `ObservableObject`, editable settings, date-boundary lifecycle, current-day snapshots, and backfill orchestration.
- `WNF/DailyRecordStorage.swift`: `StorageKey`, `DailyWageRecord`, `MonthlyRecordSummary`, App Group SQLite store, legacy UserDefaults migration, migration backups, shared locked JSON coders, and storage logging.
- `WNF/WageCalculator.swift`: `WageDay`, `WorkStatus`, pure wage calculation, and `DateComponents` minute/clock helpers.
- `WNF/WorkStatusPresentation.swift`: presentation-only status labels, quotes, and mascot asset names consumed by home/share surfaces.
- `WNF/WageFormatting.swift`: amount and duration formatting helpers used by home, records, onboarding, and share surfaces.
- `WNF/ShareCard.swift`: share-card copy pool, dim backdrop, overlay, card layout, icon controls, and the `UIActivityViewController` wrapper.
- `WNF/DailySettlement.swift`: 下班结算数据模型 (`DailySettlement` + `SettlementSentiment`), 爆金币动画 (`SettlementCoinBurst`), 全屏结算 overlay (`DailySettlementOverlay`), 结算分享卡 (`DailySettlementShareCard`), 首页 CTA 入口 (`ClockOutCTA`). 数据派生纯函数从 `WageDay` + `dailyRecords` 计算情绪等级和连续打工天数, 不修改任何持久化路径.
- `WNF/ClockOutReminder.swift`: `ClockOutReminderService` (@MainActor 单例)，封装 `UNUserNotificationCenter` 权限查询/请求和按工作日 + workEnd 时间调度 `UNCalendarNotificationTrigger` 重复本地通知。idempotent `reconcile(enabled:workEnd:selectedWeekdays:)` 先清空 `wnf.clockout.weekday.*` 前缀的现有通知再按需重建；权限非 authorized/provisional/ephemeral 时静默跳过调度。
- `WNF/WidgetShared.swift`: App Group key/snapshot schema, fixed sample data, date helpers, projection logic, and capped timeline planning shared with `WNFWidget`.
- `WNF/WidgetSnapshotWriter.swift`: App-only snapshot writer and debounced WidgetKit reload helper.
- `WNF/Legal.swift`: `LegalDocument`, `LegalDocumentView`, and the remote-first / bundled-fallback `WKWebView` integration.
- `WNFWidget/WNFWidget.swift`: Widget configuration intent stub, App Group reader, timeline provider, and system/accessory widget layouts.

The native app owns editable settings in one shared `WageState` instance injected through `EnvironmentObject`. It initializes from `UserDefaults`, normalizes loaded values into the supported ranges, writes the normalized settings back during initialization, and writes every editable setting back on change:

- `wnf.settings.monthlySalary`
- `wnf.settings.workdaysPerMonth`
- `wnf.settings.workStartMinute`
- `wnf.settings.workEndMinute`
- `wnf.settings.lunchStartMinute`
- `wnf.settings.lunchEndMinute`
- `wnf.settings.hasLunchBreak`
- `wnf.settings.includeOvertime`
- `wnf.settings.privacyMode`
- `wnf.settings.selectedWeekdays`

Times are stored as minutes since midnight and normalize to `0...1439` on load. Selected weekdays are stored as a sorted `[Int]` using the same `0...6` Monday-through-Sunday index contract as the UI. Salary still clamps to `0...100000`; monthly workdays still clamp to `1...31`. First-launch completion remains separate at `wnf.onboarding.completed` via `RootView`.

Daily record history lifecycle is owned by `WageState`; SQLite storage, legacy decoding, migration, and backups live in `DailyRecordStorage.swift`:

- Main storage is `DailyRecords.sqlite` in App Group `group.com.wonangfei.app` (fallback: Application Support when the container URL is unavailable). The app target links `-lsqlite3`.
- `daily_records` stores retained daily rows keyed by `yyyy-MM-dd`. `monthly_record_summaries` stores folded older rows keyed by `yyyy-MM`.
- Retention window: keep the latest 400 calendar days as daily rows. Rows older than the cutoff are transactionally folded into `MonthlyRecordSummary` totals (`amount`, `recordedDays`, `elapsedPaidSeconds`) and deleted from `daily_records`.
- Existing `wnf.records.daily` envelope payloads, bare legacy dictionaries, and readable recovery/raw-backup keys are migrated on first launch. A JSON backup of migrated records is written beside the SQLite database under `DailyRecordBackups/`; after successful migration, the large daily-record `UserDefaults` payload/recovery keys are removed and `wnf.records.daily.sqliteMigrationCompleted` is set.
- Daily-record encode/decode paths still reuse one `JSONEncoder` and one `JSONDecoder`, guarded by `dailyRecordCoderLock`, but only for migration/backup compatibility. New writes use SQLite upserts, not whole-dictionary `UserDefaults` rewrites.
- `DailyWageRecord` captures `earnedToday`, `targetToday`, `elapsedPaidSeconds`, `workdayMinutes`, `hourlyRate`, salary/workday settings, `capturedAt`, and a `source` marker. Existing records without `source` decode as `observed`; corrupt `source` values still throw instead of being silently coerced. New optional/defaulted fields should continue to use explicit `decodeIfPresent` defaults in the custom decoder.
- `WageState` publishes `currentDateKey` only when the calendar date changes. A one-shot day-boundary timer, foreground refresh, and scene-phase snapshot path keep cross-midnight closure working without a global one-second `ObservableObject` tick.
- `WageState.liveDay(at:)` is the single display-facing live-day entrypoint. It returns `.off` and zero earned/elapsed/target values when the date is not in `selectedWeekdays`, while `calculation(at:)` remains the raw wage math used by settings/onboarding previews.
- `WNFApp` pauses the day-boundary timer whenever the scene leaves `.active`; returning to `.active` refreshes the date immediately and recreates the timer.
- `wnf.records.lastObservedSnapshot` stores the last observed date key plus the wage calculation settings active at that observation (`monthlySalary`, `workdaysPerMonth`, work/lunch minutes, lunch/overtime flags, selected weekdays). `wnf.records.lastObservedDateKey` remains as a legacy fallback and mirror.
- If the app was not opened for multiple calendar days, `WageState` first closes the last observed day, then backfills every date from `lastObservedDate + 1 day` through the calendar day before `now`. Observed closures and backfilled records are calculated from `lastObservedSnapshot`, not today's editable settings, so later salary changes do not rewrite historical estimates. Both paths use the snapshot's `selectedWeekdays` check: selected days receive a complete standard workday snapshot, while unselected days receive zero-yuan, zero-elapsed records with their original `source`.
- `WNFApp` asks `WageState` to persist the current-day snapshot when the scene leaves `.active`, so a day can still appear in records even if the app is not open at midnight.
- `HomeView` owns the one-second `TimelineView` used by the large live money number and passes `WageState.liveDay(at:)` into the home hero. Other tabs do not subscribe to that tick.
- `RecordsView` builds a memoized aggregation snapshot through internal `RecordAggregator` from `(currentDateKey, recordsRevision, retained daily records, folded monthly summaries, live-day settings, includeOvertime, selectedWeekdays)`. Cache equality compares the scalar `recordsRevision` instead of the full dictionaries, so week/month/year bars reuse the snapshot across body updates and only rebuild when the date key, stored-record revision, or wage settings change. The live today record returns zero amount / zero elapsed when `currentDateKey` is not in `selectedWeekdays`, and year bars add folded monthly summaries without double-counting today.

## Widget

- App Group suite: `group.com.wonangfei.app`.
- `WNFWidget` supports `.systemSmall`, `.systemMedium`, `.accessoryRectangular`, and `.accessoryInline`.
- v1 uses an empty `AppIntentConfiguration` stub so v1.x can add per-widget settings without replacing the configuration model.
- Every Widget view uses `containerBackground(for: .widget)` for iOS 17 rendering.
- Timeline policy: the provider reads one App Group snapshot and emits near-term minute-level future entries through `workEnd` (or end of day when overtime is enabled), capped at 240 future entries. If the cap is hit it reloads near the end of that window to refill; otherwise it schedules the next reload for the next selected workday start instead of reloading every 60 seconds.
- Widget wage display reads `wnf.widget.wage.snapshot.v1`; gallery and placeholder paths use the shared fixed sample and never read real wage data. The v2 snapshot includes the capture date key, selected weekdays, work/lunch schedule, overtime flag, workday minutes, per-second rate, and `hidesSensitiveInfo`. `WNF/WidgetShared.swift` is the single source for the schema/key/sample/projection/timeline pure logic across app and widget targets; decode failures fall back to sample data with a widget log entry. Widget projection derives each entry's amount/elapsed/status locally and renders `¥•••.••` when App privacy mode is on. `WNFApp` rewrites the snapshot when privacy or wage/schedule/workday settings change.
- Terms and Privacy links open remote URLs first and fall back to bundled `terms.html` / `privacy.html` through the local legal document viewer.

Default app state lives in `窝囊费.html` under `TWEAK_DEFAULTS`:

- `monthlySalary`: 18000
- `workdaysPerMonth`: 26
- `workStart`: `09:30`
- `workEnd`: `18:30`
- `lunchStart`: `12:00`
- `lunchEnd`: `13:00`
- `noLunch`: false
- `weekdays`: `[0,1,2,3,4]`
- `overtime`: true
- `privacy`: false
- `nowTime`: `15:24`

## Salary Math

Source: `shared.jsx -> computeDay(cfg, nowMin)`

1. Parse work start/end and lunch start/end as minutes.
2. If `cfg.noLunch` is true, set lunch start and lunch end to end time.
3. Compute paid workday minutes:
   - `workdayLen = workEnd - workStart - lunchLen`
4. Compute hourly rate:
   - `hourlyRate = monthlySalary / (workdaysPerMonth * (workdayLen / 60))`
5. Compute elapsed paid minutes up to `nowMin`, subtracting lunch overlap.
6. Compute current-day earnings:
   - `earnedToday = hourlyRate / 60 * elapsedPaid`

Native `WageCalculator.compute` returns a zero-value `WageDay` when `workEnd <= workStart`; Settings and Onboarding route work-start/work-end changes through `WageState.setWorkStart` / `setWorkEnd` to keep the editable pair valid. Lunch deduction is clamped to the overlap between lunch and the work interval, so lunch outside work hours does not reduce paid time.

Important: the settings UI label says `午休`. Switch on means "has lunch break"; switch off means "没有午休". The data flag remains `noLunch`.

## Interaction Requirements

### 全局 Tab

- 底部 `首页 / 记录 / 我的` tab 使用自定义 SwiftUI `AppTabBar`。
- 切换 tab 时，主内容按 tab 顺序做横向滑入/滑出并叠加淡入淡出：向右侧 tab 前进时新页面从右进入，返回左侧 tab 时新页面从左进入。
- 底部胶囊选中态和页面内容过渡共用同一次 `snappy` 动画。

### 引导页

- First launch shows the four-screen onboarding flow before the main tab UI.
- Header title changes per page and the skip button moves directly to the final page before completion.
- Page 2 salary controls commit through `WageState`, so slider and button edits persist like settings-page edits.
- Page 3 work time and lunch controls update the same persisted settings state used by the main app.
- Page 3 hero crossfades between the lunch sleep/wake assets when 午休 is toggled.

### 首页

- Top-right action opens the share card; it no longer toggles privacy on the home page.
- The home live amount is driven by a view-local one-second `TimelineView`, not by a global `WageState` publication.
- The home mascot slot now renders transparent `WNF/home-typing.mov` and `WNF/home-bored.mov` clips through an `AVPlayerLayer` SwiftUI wrapper. `RootView` owns one stable `HomeMascotVideoSessionCoordinator` and injects the coordinator's `HomeMascotVideoController` into Home, so tab transitions can recreate `HomeView` without rebuilding the `AVQueuePlayer` pipeline. The coordinator owns scene-phase and tab-change playback decisions; `HomeMascotVideoSequence` is only the rendering bridge. The controller keeps upcoming local clips prequeued, shuffles the clip order for each full cycle, avoids repeating the last clip at the cycle boundary, and mutes playback. Short inactive transitions and tab switches call `pauseTemporarily()` so the queue and playback request stay intact; `.active` resumes an already requested, non-empty queue with `player.play()` only. The coordinator releases the queue with `removeAllItems()` only when the app enters background, and `HomeMascotVideoController` also clears the queue on `UIApplication.didReceiveMemoryWarningNotification`.
- The mascot speech bubble and decorative yen coins are owned by the local `HomeMascotStage`. Coin offsets are calculated from that stage's actual layout width through `GeometryReader`, not from `UIScreen.main.bounds`, so iPad split view, Stage Manager, and rotation can reflow the home decoration.
- Opening the share card blurs the existing home content and adds a full-bleed dimmed overlay that covers the status bar and bottom home-indicator areas.
- `RootView` owns share card presentation state and export triggering so the dimmed safe-area coverage does not depend on the card transition or tab-content transition; `ShareCard.swift` owns the backdrop/overlay/card components plus the UIKit activity presenter, while `HomeView` only requests presentation and blurs its own home content while the card is open.
- Share card presentation uses opacity-only insertion/removal so the card bounds stay fixed throughout the transition.
- Share card content must include `今日窝囊费` and `上班上了多久`.
- Share card title/subtitle copy is selected from `ShareCardCopy.pool` every time the home share action opens the card. The picker excludes the currently displayed pair when possible, so repeated opens visibly refresh the wording.
- Share card controls:
  - eye button masks/unmasks card-sensitive values only;
  - share button enters a loading/disabled state and waits one frame so the spinner can render; this is a UX/perceptual-feedback fix, not a concurrency fix, because SwiftUI `ImageRenderer.render(rasterizationScale:)` and the explicit `UIGraphicsImageRenderer` context are still main-thread bound. Export uses the current `UIWindowScene.screen.scale`, then presents iOS `UIActivityViewController` from an attached presenter view with `popoverPresentationController.sourceView` configured for iPad / Mac Catalyst;
  - x button closes the card.
- Tapping outside the card closes the card. While the card is open, bottom tab bar interaction is disabled.
- 首页 progress track 下方的「下班结算」CTA 按钮 (`ClockOutCTA`) 是仪式入口，不是数据保存入口：下班前隐藏；下班后未结算时 title 为「下班！领今天的窝囊费」；用户点过「存入资产」后切到 settled 回看文案。点击触发 `RootView.presentSettlement()`，与右上角分享互相独立。不要自动弹窗、红点追赶或循环催促。

### 下班结算

- 入口仅在首页 CTA。`RootView` 拥有 `settlementPresented`、`settlementSnapshot`、`settlementHidesSensitiveInfo` 三个状态。
- `DailySettlement.derive(from:dailyRecords:at:)` 从当前 `WageDay` 与 `dailyRecords` 派生快照：金额、已忍时长、进度、忍耐指数 (`SettlementSentiment` 1-5 星，按 `progress` 落档并把 `.done && progress >= 1.0` 视为 heavy)、连续打工天数 (从今天向前回溯，遇到 `earnedToday > 0` 即继续，遇到 0 即停止，最多回溯 60 天)、动态 headline / subCopy（按情绪等级 + 连续天数动态拼接）、随机选中的今日最佳忍耐时刻文案。派生过程是纯函数，不修改任何持久化路径。
- 全屏 overlay 有三个阶段：`prep`（背景刚淡入） → `burst`（中心金币雨向外扩散，触发 heavy 触感反馈） → `reveal`（金币消散后结算卡 spring-in，数字 0 → 今日金额线性 ease-out 滚动，底部「存入资产 / 分享卡片」action 行延后 0.18s ease-in）。整个动画 < 2s，右上角始终有「跳过」按钮可立即完成 burst 跳到 reveal 态。`burst` 期间 settlement card 和 action row 通过 `allowsHitTesting(...)` 屏蔽 hit-test，避免透明态被误触。
- 结算卡的背景与 `WonangfeiShareCard` 保持一致的奶油白；header 同时提供眼睛（敏感信息打码）/ 分享 / 关闭按钮，与分享卡操作保持一致。
- 「存入资产」调用 `state.persistCurrentDaySnapshot()` + `state.markTodaySettled()` 写回当前快照并发出 `UINotificationFeedbackGenerator(.success)`，然后关闭 overlay。每日记录仍由场景切换、跨日补记等现有路径自动持久化；用户不点「存入资产」也不会丢数据。App 启动、回到前台、普通打开结算卡、关闭或跳过 overlay 都不会自动标记 settled。
- 「分享卡片」走与首页分享相同的渲染管线：`renderAndPresentSettlementShare` 同步生成 `DailySettlementShareCard` 的 `UIImage`（main-thread bound 的 `ImageRenderer.render(rasterizationScale:)`，使用 `windowSceneScale`，宽度固定 360pt），失败时退化到包含金额、已忍时长、连续打工天数的 fallback 文本。复用现有 `ActivityView` 和 `ActivityPresenterViewController`，避免 iPad / Mac Catalyst 弹窗崩溃。
- 共用一份 `isPreparingShareActivity` 标志：因为 settlement overlay 与原 share card 不会同时呈现，所以共用同一份「正在生成分享图」状态不冲突。
- 结算 overlay 打开时，bottom tab bar 同样被 opacity / hit-testing 屏蔽（与原 share card 行为对齐）。
- 结算卡内除金额/统计外，还包含一条 quote card「今日最佳忍耐时刻」：从 `DailySettlement.bestMomentPool` 随机选一句，支持长按 0.4s 撕碎换内容（rigid 触感 + `withAnimation` 包裹 state 切换 + `.id(combined)` 驱动 SwiftUI insertion/removal transition；pool 内会 exclude 当前文案，保证连续撕碎一定出新内容）。撕碎只发生在 overlay 内（`showsControls == true`）；导出分享图时 `onTearBestMoment` 传 nil 不渲染长按 hint。
- 结算卡底部增加「累积窝囊费」单行：从 `DailySettlement.cumulativeEarned` 渲染（所有历史 daily records earnedToday 求和 + 今日 live amount，避免重复计入今日 closed snapshot）。privacy 模式打码为 `¥•••.••`。

### 个人时间模式

- 触发：用户在 settlement overlay 点「存入资产」时，`RootView.saveSettlementAsAsset()` 在 `persistCurrentDaySnapshot()` 之后调用 `state.markTodaySettled()`，把 `WageState.lastSettlementDateKey` 设为今天的日期键。
- 持久化：`wnf.settlement.lastCompletedDateKey`（`UserDefaults` String，可为空）。
- 状态：`WageState.isTodaySettled` 计算属性 = (lastSettlementDateKey == currentDateKey)。跨日时 `currentDateKey` 自然推进，旧值不再相等，状态自动回归。
- 首页响应：
  - `StatusChip` label 改为「今日已下班 · 个人时间」（替代 `WorkStatusPresentation.label`）。
  - `ClockOutCTA` title / subtitle / icon 切到 settled 文案（「今日已下班 · 再看一眼」/「今日窝囊费已入账，剩下都是你的时间」/ `checkmark.circle.fill`）。点击仍打开 overlay，让用户回看结算卡。
- 不影响：金额、进度条、已忍/离下班时长、吉祥物视频、share card — 实时数据保持同步，避免遮蔽今天还在涨的窝囊费。
- 仅 `存入资产` 触发 settled 状态；X / 屏外 tap dismiss / 跳过 都不算 "完成"，避免误触。

### 下班结算提醒

- **默认关闭**。开关入口位于「我的」页 `提醒` section，复用 `WNFToggle`。
- 持久化键：`wnf.settings.clockOutReminderEnabled`（默认 `false`）。
- 用户在 Settings 中开启 toggle 时：先通过 `ClockOutReminderService.requestAuthorizationIfNeeded()` 请求 `[.alert, .sound]` 权限；不论权限结果，`state.clockOutReminderEnabled` 都会持久化为 `true`（toggle 反映用户意图，不强制系统权限）；之后 `state.reconcileClockOutReminder()` 触发实际调度。
- `WageState` 在 `clockOutReminderEnabled`、`workEnd`、`selectedWeekdays` 任一变更时 didSet 中调用 `reconcileClockOutReminder()`；`WNFApp.onChange(of: scenePhase)` 在 `.active` 时也调用一次，保证回到前台时系统通知排程与最新设置同步。
- 调度逻辑：`ClockOutReminderService.reconcile(...)` 先清空所有 `wnf.clockout.weekday.*` 前缀的 pending notification，再按每个选中工作日新建一条 `UNCalendarNotificationTrigger(dateMatching:repeats:true)`，时间 = workEnd 的 hour/minute，weekday = app 0-索引 (`周一=0`) 转 iOS Gregorian (`周日=1`)。
- 权限非 authorized/provisional/ephemeral 时静默不调度（OSLog 记录原因）；Settings 页在 `task` 中查询 `currentAuthorizationStatus()`，若返回 `.denied` 且 toggle 处于 ON，会展示 `iOS 通知权限被关闭，到系统设置开启后才会真的弹通知。` 行内引导，点击调 `UIApplication.openNotificationSettingsURLString` 跳转系统设置。
- 不引入 deep link / 自定义 action：通知点击只把 app 拉到前台，由用户自行点击首页 CTA 完成结算（避免在没有用户操作的情况下自动弹结算 overlay）。
- 通知文案目前固定：`今天可以结算窝囊费啦` / `点开 App 看看今天的窝囊战绩。`，后续可以加 i18n 或 A/B。

### 记录页

- 周 / 月 / 年 tabs must switch datasets.
- Datasets must be derived from SQLite daily rows plus folded monthly summaries; do not reintroduce hard-coded chart multipliers.
- Week view groups Monday through Sunday, month view groups 7-day buckets in the current month, and year view groups calendar months.
- Today must be included from the live `WageState.calculation` so the current bar updates before the daily snapshot is closed.
- Chart bars must be tappable except future bars.
- Selected chart bar must show a callout and can be cleared.
- Privacy toggle must mask all money strings with dot placeholders.
- Hero total, averages, peak value, monthly achievement copy, and badge count must recompute from the same record-backed bar data.

### 我的页

- Salary and monthly-workday rows use a shared SwiftUI value stepper: `- / +` buttons handle precise increments, and tapping the center value opens a numeric quick-entry alert.
- Salary quick entry accepts digits and clamps to `0...100000`; salary step controls change in increments of 500.
- Monthly workdays quick entry accepts digits and clamps to `1...31`; monthly workday step controls change in increments of 1.
- Weekday pills toggle active state.
- Time controls use native time input.
- 午休 switch hides/reveals lunch rows and recomputes hourly rate.
- 计入加班 is the only interactive switch in the 其它 section.
- All editable settings on this page persist through `WageState` and should survive app relaunch.

## Visual Implementation Rules

- Use `#FFF6E5` as the app background, not plain white.
- Use `#FFC83D` only for brand anchors, active chart bars, active switch knobs, and selected states.
- Use `#0D0D0D` for primary action surfaces, selected chart states, and high-emphasis typography.
- Keep borders at `0.5px` hairlines.
- Use rounded corners intentionally:
  - 10-12px for controls.
  - 18px for thumbnails.
  - 22px for standard cards.
  - 28px for hero cards.
  - 999px for pills.
- Numbers should use JetBrains Mono or platform mono with tabular numerics.
- Do not use emoji as feature icons; use the current stroked SVG icon language.

## Hand-off Notes

- Native iOS entry: open `WNF.xcodeproj`, scheme `WNF`, bundle id `com.wonangfei.app`, iOS deployment target `17.0`.
- Current simulator validation uses `iPhone 17` on iOS `26.5`.
- XcodeBuildMCP defaults are committed under `.xcodebuildmcp/config.yaml`, so agents can call `build_sim`, `build_run_sim`, `snapshot_ui`, `tap`, and `screenshot` without re-entering project defaults.
- Build validation: `xcodebuild -project WNF.xcodeproj -scheme WNF -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` must succeed before commit.
- External release blockers remain outside the repo: App Group/Associated Domains provisioning, AASA deployment, ASC product creation/localization/pricing, China备案/软著/ICP/privacy URL/customer support, and App Review notes. v1 does not ship paid features, subscriptions, or in-app purchases.
- 2026-05-17 onboarding hero replacement validation: five source PNGs from `/Users/shelingzhao/Documents/窝囊费素材/引导/` matched their target asset-catalog SHA-256 hashes, all target files reported `1536 x 1024` and `hasAlpha: yes`, and `build_sim` succeeded.
- 2026-05-17 home responsive-layout fix: `WNF/HomeView.swift` no longer reads `UIScreen.main.bounds.width` for the mascot-stage coin layout; use simulator rotation or iPad split-view checks when visually validating this area.
- Home share card verification covered opening the card, masking sensitive values, presenting the iOS share sheet, closing with the x button, and closing by tapping outside the card.
- The source prototype still includes Open Design canvas and tweak controls. For production, move only the screen components and shared tokens into the app shell.
- `assets/reference-screens/` contains visual inputs and may include duplicate imported versions. Treat it as reference material, not production bundle.
- `assets/mascot/hero-mascot.png` is currently used in both record achievement card and settings profile banner.
- The root app fixes the package asset paths through `WNF_MASCOT_ROOT`, so the same screen components work from both `/index.html` and `/assets/source/wonangfei.html`.
- The old 8-pose cow set remains useful for home screen state changes.
