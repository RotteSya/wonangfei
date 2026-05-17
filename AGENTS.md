# WNF Agent Notes

## Project Surface

- Native app: `WNF.xcodeproj` / `WNF/`, scheme `WNF`, bundle id `com.wonangfei.app`, iOS deployment target `17.0`.
- Browser/design handoff: `index.html`, `assets/source/*.jsx`, `brand-tokens.css`, `design-tokens.json`.
- Treat the SwiftUI app as the implementation surface when the task is app behavior, build, or asset-catalog work. Treat the HTML/Open Design files as visual reference unless the task explicitly says prototype/design only.

## Build Defaults

XcodeBuildMCP defaults are persisted in `.xcodebuildmcp/config.yaml` for project `WNF.xcodeproj`, scheme `WNF`, configuration `Debug`, simulator `iPhone 17`, and bundle id `com.wonangfei.app`.

Preferred validation for native changes:

```sh
xcodebuild -project WNF.xcodeproj -scheme WNF -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

When XcodeBuildMCP is available, call `session_show_defaults` first, then `build_sim` or `build_run_sim`.

## Current Architecture Notes

- The active native checkout is a single app target. There is no current `WNFWidget/`, `WageCore.swift`, or `WageDisplayModel.swift` in this tree.
- `WNF/WageState.swift` owns editable salary, workday, weekday, time, lunch, overtime, and privacy state.
- `WNF/WageState.swift` persists those editable settings with `UserDefaults` keys under `wnf.settings.*`; first-launch completion remains separate at `wnf.onboarding.completed`.
- `WNF/WageState.swift` owns in-memory daily record history and the monotonic `recordsRevision`; `WNF/DailyRecordStorage.swift` owns the `wnf.records.daily` JSON envelope, legacy migration, recovery keys, and shared JSON coders. `WNFApp.swift` persists the current-day snapshot when the app leaves the active scene phase, and `WageState` closes the previous date when `currentDate` crosses into a new calendar day.
- `WNF/HomeView.swift`, `WNF/RecordsView.swift`, and `WNF/SettingsView.swift` consume shared state directly.
- `WNF/RecordsView.swift` must aggregate week/month/year chart data from the record-backed snapshot (`dailyRecords` payload, `recordsRevision` cache key, and current-day calculation); do not reintroduce hard-coded chart multipliers or full-dictionary cache equality for production records.
- `WNF/OnboardingView.swift` owns the first-launch onboarding flow and writes through the same `WageState` settings path.

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
