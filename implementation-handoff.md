# Implementation Handoff

## Active Prototype Files

The runnable entry and live prototype files are:

- `WNF.xcodeproj` / `WNF/`：native SwiftUI iOS implementation of the current app design.
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

Current `main` note: commits after `bdaa6ef` reverted the earlier widget/core split. The active native implementation is the single `WNF/` app target with settings state and local persistence in `WNF/WageState.swift`; there is no current `WNFWidget/`, `WageCore.swift`, or `WageDisplayModel.swift` in this checkout.

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

Native source: `WNF/WageState.swift`

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

Daily record history is also owned by `WageState`:

- `wnf.records.daily` stores a JSON-encoded `[dateKey: DailyWageRecord]` dictionary, keyed as `yyyy-MM-dd` in the current calendar.
- `DailyWageRecord` captures `earnedToday`, `targetToday`, `elapsedPaidSeconds`, `workdayMinutes`, `hourlyRate`, salary/workday settings, `capturedAt`, and a `source` marker. Existing records without `source` decode as `observed`; auto-created gap records encode as `backfilled`.
- `WageState` closes the previous calendar day when its one-second `currentDate` clock crosses into a new day.
- If the app was not opened for multiple calendar days, `WageState` first closes the last observed day, then backfills every date from `lastObservedDate + 1 day` through yesterday. Dates whose Monday-through-Sunday index is in `selectedWeekdays` receive a complete standard workday snapshot; other dates receive a zero-yuan, zero-elapsed `backfilled` record.
- `WNFApp` asks `WageState` to persist the current-day snapshot when the scene leaves `.active`, so a day can still appear in records even if the app is not open at midnight.
- `RecordsView` reads daily records through `WageState.dailyRecord(for:includingLiveToday:)`; today is supplied from the live calculator, while historical dates only use landed snapshots.

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
- The home mascot slot now renders transparent `WNF/home-typing.mov` and `WNF/home-bored.mov` clips through an `AVPlayerLayer` SwiftUI wrapper. `HomeMascotVideoController` uses an `AVQueuePlayer`, keeps upcoming local clips prequeued, shuffles the clip order for each full cycle, avoids repeating the last clip at the cycle boundary, mutes playback, and pauses when the view disappears or the scene becomes inactive.
- Opening the share card blurs the existing home content and adds a full-bleed dimmed overlay that covers the status bar and bottom home-indicator areas.
- `RootView` owns the stable full-screen backdrop, share card presentation, and export sheet so the dimmed safe-area coverage does not depend on the card transition or tab-content transition; `HomeView` only requests presentation and blurs its own home content while the card is open.
- Share card presentation uses opacity-only insertion/removal so the card bounds stay fixed throughout the transition.
- Share card content must include `今日窝囊费` and `上班上了多久`.
- Share card title/subtitle copy is selected from `ShareCardCopy.pool` every time the home share action opens the card. The picker excludes the currently displayed pair when possible, so repeated opens visibly refresh the wording.
- Share card controls:
  - eye button masks/unmasks card-sensitive values only;
  - share button renders the card without controls and presents iOS `UIActivityViewController`;
  - x button closes the card.
- Tapping outside the card closes the card. While the card is open, bottom tab bar interaction is disabled.

### 记录页

- 周 / 月 / 年 tabs must switch datasets.
- Datasets must be derived from `wnf.records.daily`; do not reintroduce hard-coded chart multipliers.
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
- Current simulator validation used `iPhone 17` on iOS `26.5`; `build_sim` and `build_run_sim` both succeeded with no diagnostics.
- XcodeBuildMCP defaults are committed under `.xcodebuildmcp/config.yaml`, so agents can call `build_sim`, `build_run_sim`, `snapshot_ui`, `tap`, and `screenshot` without re-entering project defaults.
- 2026-05-17 onboarding hero replacement validation: five source PNGs from `/Users/shelingzhao/Documents/窝囊费素材/引导/` matched their target asset-catalog SHA-256 hashes, all target files reported `1536 x 1024` and `hasAlpha: yes`, and `build_sim` succeeded.
- Home share card verification covered opening the card, masking sensitive values, presenting the iOS share sheet, closing with the x button, and closing by tapping outside the card.
- The source prototype still includes Open Design canvas and tweak controls. For production, move only the screen components and shared tokens into the app shell.
- `assets/reference-screens/` contains visual inputs and may include duplicate imported versions. Treat it as reference material, not production bundle.
- `assets/mascot/hero-mascot.png` is currently used in both record achievement card and settings profile banner.
- The root app fixes the package asset paths through `WNF_MASCOT_ROOT`, so the same screen components work from both `/index.html` and `/assets/source/wonangfei.html`.
- The old 8-pose cow set remains useful for home screen state changes.
