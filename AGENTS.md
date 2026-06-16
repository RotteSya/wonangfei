# WNF Agent Notes

## Project Surface

- Native app: `WNF.xcodeproj` / `WNF/`, scheme `WNF`, bundle id `com.wonangfei.app`, iOS deployment target `17.0`.
- Widget extension: `WNFWidget/`, bundle id `com.wonangfei.app.widget`, App Group `group.com.wonangfei.app`.
- Unit tests: `WNFTests/`.
- Browser/design handoff: `index.html`, `assets/source/*.jsx`, `brand-tokens.css`, `design-tokens.json`.
- Treat the SwiftUI app as the implementation surface when the task is app behavior, build, or asset-catalog work. Treat the HTML/Open Design files as visual reference unless the task explicitly says prototype/design only.

## Branch Naming

Use only these branch prefixes:

| Prefix | Use for | Example |
|---|---|---|
| `feat/` | New features or behavior changes | `feat/payslip-export` |
| `fix/` | Bug fixes | `fix/coin-animation-stutter` |
| `tweak/` | Visual polish, copy, spacing, animation feel, or asset swaps | `tweak/yellow-pill-radius` |

Do not use extra prefixes such as `codex/`, `chore/`, `design/`, or `release/` unless the user explicitly changes this convention.

## Build Defaults

XcodeBuildMCP defaults are persisted in `.xcodebuildmcp/config.yaml` for project `WNF.xcodeproj`, scheme `WNF`, configuration `Debug`, simulator `iPhone 17`, and bundle id `com.wonangfei.app`.

Preferred validation for native changes:

```sh
xcodebuild -project WNF.xcodeproj -scheme WNF -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

When XcodeBuildMCP is available, call `session_show_defaults` first, then `build_sim` or `build_run_sim`.

`WNFUITests/JellyTourUITests.swift` (`testGrandTour`) is a choreographed driver that walks every new interaction — money long-press fountain, privacy toggle, jelly swipes, chart scrub, period switches, tab-pill taps, share genie in/out — emitting `TOUR-MARK <t>s <label>` log lines. Run it while capturing video to film/verify the motion work:

```sh
xcrun simctl io 'iPhone 17' recordVideo --codec h264 --force tour.mov &
xcodebuild test -project WNF.xcodeproj -scheme WNF \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WNFUITests
```

It relies on accessibility identifiers (`home.money`, `home.share`, `home.privacy`, `tab.<home|records|settings>`, `records.period.<week|month|year>`, `records.chart`, `share.cancel`) — keep them when refactoring those controls. The test also acts as a layout guard: it once failed (button "off-screen") when an oversized home background expanded the layout and pushed the TopBar off-screen.

## Current Architecture Notes

- The active native checkout has the main app target, `WNFWidget`, `WNFTests`, and `WNFUITests`. There is no current `WageCore.swift` or `WageDisplayModel.swift` split.
- Motion/visual-FX layer (added in `feat/jelly-shell-and-gold-shaders`):
  - `WNF/WNFShaders.metal` holds the stitchable shaders: `wnfGoldShimmer` (diagonal glint sweep, colorEffect), `wnfPaperGrain` (static film grain, colorEffect), `wnfMoltenGold` (progress-bar liquid fill with lapping crest, colorEffect). `GenieEffect.metal` (share-card warp) is unchanged.
  - `WNF/ShaderFX.swift` wraps them in SwiftUI: `.goldShimmer(...)`, `.paperGrain(...)`, the `JellyStretch` squash-&-stretch modifier (`.jellyStretch(_:)`), `SquishButtonStyle` (`.buttonStyle(.squish)`), and the shared `WNFHaptics` generators. Every shimmer/grain clock is a `TimelineView(paused:)` gated by `isActive` + `accessibilityReduceMotion`, so off-screen pager pages and Reduce-Motion users cost zero frames. **`JellyStretch` is a plain transform, NOT a `distortionEffect`** — shader layer effects can't rasterize the home mascot's `AVPlayerLayer`, so do not convert it back to a shader.
  - `WNF/OdometerText.swift` is the home money readout (`OdometerMoneyText`): per-digit slot-machine wheels (gas-pump roll on increase), `+¥1` rollover chips, and a deterministic `fitScale` + `maxWidth` layout cap. The cap exists because `scaleEffect` shrinks glyphs visually but a scaled view still *claims* its natural width — without the `maxWidth`/font-size budget a large number stretches the enclosing `VStack` and pushes the home TopBar's trailing buttons off-screen. Always pass the readout column's content width.
  - `WNF/PagerShell.swift` owns the continuous `AppTabBar(progress:onSelect:)` (ink pill glides/stretches/squishes by fractional pager position, 0…2) and `HorizontalGestureArbiter` (one `ObservableObject` arbitrating the pager swipe vs. the records chart scrub for a single touch — whoever claims first wins; the chart attaches `.chartScrub`, the pager `.pager`). Also `PageDepthFX` (parallax + dim + scale by signed distance from viewport center) and the `pagerJellyStretch` environment key.
- `WNF/RootView.swift` runs the home↔records↔settings strip as an interactive jelly pager: all three pages stay mounted in one `HStack`, a `simultaneousGesture` `DragGesture` steers it 1:1 with a directional axis lock and rubber-banded ends, release settles with a velocity-seeded `interpolatingSpring`, and `@GestureState pagerTouchActive` catches cancelled gestures (system steal / app switch) that never deliver `onEnded`. `selectedTab` + `pagerDragOffset` are the source of truth; `pagerProgress` is derived. The `HorizontalGestureArbiter` is injected as an `environmentObject` for the pager and the chart — **any new `RecordsView`/`BarChart` preview must inject `HorizontalGestureArbiter()` or it will crash.** Tab taps and swipes both feed `commitPager`/`selectTab`, fire a `rigid` haptic, and forward `handleTabChange` to the mascot video session.
  - **Pager + ScrollView gotcha:** a tappable control (e.g. the `TopBar` privacy/share buttons) must NOT live inside a page's `ScrollView` — the scroll view's delayed-touch handling combined with the pager's `simultaneousGesture` drag swallows its taps (the privacy eye silently stopped toggling on records/settings until fixed). `HomeView`, `RecordsView`, and `SettingsView` all keep `TopBar` as a FIXED header in an outer `VStack(spacing: 0)` above the `ScrollView`. Keep it that way.
- `WNF/WageState.swift` owns editable salary, workday, weekday, time, lunch, overtime, and privacy state.
- `WNF/WageState.swift` persists those editable settings with `UserDefaults` keys under `wnf.settings.*`; first-launch completion remains separate at `wnf.onboarding.completed`.
- `WNF/WageState.swift` owns in-memory daily record history and the monotonic `recordsRevision`; `WNF/DailyRecordStorage.swift` owns the `wnf.records.daily` JSON envelope, legacy migration, recovery keys, and shared JSON coders. `WNFApp.swift` persists the current-day snapshot when the app leaves the active scene phase, and `WageState` closes the previous date when `currentDate` crosses into a new calendar day.
- `WNF/HomeView.swift`, `WNF/RecordsView.swift`, and `WNF/SettingsView.swift` consume shared state directly.
- `WNF/HomeView.swift` home page: the background is just `WNFTheme.bg` (the earlier drifting ambient glow was removed at the user's request). The progress bar is the `wnfMoltenGold` shader carved out of a full-width rect; long-pressing the money fires a keyframe-driven `CoinFountainBurst` (reduce-motion gated); the existing per-second `HomeCoinDropLayer` and `CoinSourceAnchorKey` are unchanged. Pass `isActive` (`abs(pagerProgress) < 1`) down so the off-screen page pauses its per-second `TimelineView` and shader clocks. **Layout guard:** never give the home page a background/sibling whose intrinsic size exceeds the page — an oversized view (e.g. big offset glow circles) expands the layout, centers the content, and shoves the TopBar's trailing buttons off-screen. If you add a background decoration, wrap it in `.background{}` with an explicit page-sized frame + `.clipped()`.
- `WNF/RecordsView.swift` page order is hero → **chart** → metric tiles → achievement → badges; the chart was promoted directly under the hero so the scrub gesture is above the fold. `PeriodSwitcher` is a hand-rolled `matchedGeometryEffect` segmented control. `BarChart` grows bars in with a per-bar spring stagger on period change (keyed by `.id(period)`), scrubs via a `minimumDistance: 0` drag arbitrated through `HorizontalGestureArbiter` (per-bar selection haptic), and glows today's bar.
- `WNF/RecordsView.swift` must aggregate week/month/year chart data from the record-backed snapshot (`dailyRecords` payload, `recordsRevision` cache key, and current-day calculation); do not reintroduce hard-coded chart multipliers or full-dictionary cache equality for production records.
- `WNF/OnboardingView.swift` owns the first-launch onboarding flow and writes through the same `WageState` settings path.
- `WNF/WidgetShared.swift` owns the App Group snapshot schema and reload helper shared between the app target and `WNFWidget`.
- `WNFWidget/WNFWidget.swift` reads only App Group mirrors. Widget preview/gallery paths must use fixed sample values, and all widget views must keep `containerBackground(for: .widget)`.
- Share-card export is still main-thread bound on iOS: `ImageRenderer.render(rasterizationScale:)` and the `UIGraphicsImageRenderer` context run synchronously on `MainActor`. The one-frame loading pre-flight in `RootView` is a UX/perceptual-feedback fix, not a real rendering-concurrency or P1 performance fix.
- `WNF/DailySettlement.swift` owns the下班结算 feature: pure-function snapshot derivation (`DailySettlement.derive`), 爆金币 burst animation, full-screen overlay, settlement share card, and home CTA. `RootView` is the only owner of overlay presentation state and reuses the existing share-render / `ActivityView` pipeline for system share. The settlement flow must not be triggered from anywhere other than the home Clock-Out CTA, and must not introduce new persistence keys — `存入资产` reuses `WageState.persistCurrentDaySnapshot()`, plus sets `WageState.lastSettlementDateKey` via `markTodaySettled()`. Personal-time mode keys off `WageState.isTodaySettled` (`lastSettlementDateKey == currentDateKey`); the only persistence key it adds is `wnf.settlement.lastCompletedDateKey`. Long-press tear on the two quote cards swaps content via `DailySettlement.alternate*` static helpers — pool entries are static data, no persistence.
- `WNF/ClockOutReminder.swift` owns the optional 下班结算提醒 local-notification service. The feature is **off by default** (`wnf.settings.clockOutReminderEnabled = false`) and can only be enabled from the Settings 提醒 section. `WageState.reconcileClockOutReminder()` must be called from any setting change that affects the schedule (`clockOutReminderEnabled` / `workEnd` / `selectedWeekdays`) and from `scenePhase == .active`. Do not schedule from view code directly — always go through `WageState`.

## Onboarding Asset Rules

Hero art source folder: `/Users/shelingzhao/Documents/窝囊费素材/引导/`.

| Source file | Asset catalog target |
|---|---|
| `p1.png` | `WNF/Assets.xcassets/OnboardingP1.imageset/onboarding-p1.png` |
| `p2.png` | `WNF/Assets.xcassets/OnboardingP2.imageset/onboarding-p2.png` |
| `p3午休.png` | `WNF/Assets.xcassets/OnboardingLunchSleep.imageset/onboarding-lunch-sleep.png` |
| `p3睡醒.png` | `WNF/Assets.xcassets/OnboardingLunchWake.imageset/onboarding-lunch-wake.png` |
| `p4.png` | `WNF/Assets.xcassets/OnboardingP4.imageset/onboarding-p4.png` |

Keep all five files as `1536 x 1024` PNGs with alpha. After replacing, verify the target files with:

```sh
sips -g pixelWidth -g pixelHeight -g hasAlpha WNF/Assets.xcassets/OnboardingP1.imageset/onboarding-p1.png
```

Repeat for all changed onboarding assets. A soft white/yellow glow behind the image is expected from `OnboardingImagePanel` and `LunchImagePanel`; a solid white rectangle means alpha was lost in the asset-catalog PNG.

## Documentation Hygiene

- Update `README.md` for user-facing setup and current implemented surfaces.
- Update `implementation-handoff.md` for behavior, state flow, verification, and active implementation details.
- Update `asset-manifest.md` for shipped or handoff-relevant visual assets.
- Update `component-library.md` when a UI component contract changes.
