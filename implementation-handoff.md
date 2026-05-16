# Implementation Handoff

## Active Prototype Files

The runnable entry and live prototype files are:

- `WNF.xcodeproj` / `WNF/`：native SwiftUI iOS implementation of the current app design.
- `WNF/WageCore.swift`：native fact-only settings, persistence helpers, calendar helpers, and wage calculation.
- `WNF/WageDisplayModel.swift`：native display derivation for homepage and Widget copy; keep titles and summary rows out of `WageCalculator`.
- `WNFWidget/`：WidgetKit extension source for small, medium, and large widgets.
- `WNFTests/WageCalculatorChecks.swift`：command-line calculation smoke checks.
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

## Core State

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

As of 2026-05-16, native iOS state has two persistence layers:

- App settings source: `WageSettings` encoded in standard `UserDefaults` under `wnf.settings.v1`.
- Widget handoff: the same configuration snapshot encoded in App Group `group.com.wonangfei.app` under `wnf.widget.settings.v1`.

The Widget does not persist independent settings and does not store display strings. It reads the snapshot, runs `WageCalculator`, then derives text through `WageDisplayModel`.

## Native Salary Math

Prototype reference source: `shared.jsx -> computeDay(cfg, nowMin)`. Native source of truth: `WNF/WageCore.swift -> WageCalculator.compute(settings:now:calendar:)`.

1. Parse work start/end and lunch start/end as minutes.
2. If `cfg.noLunch` is true, set lunch start and lunch end to end time.
3. Compute paid workday minutes:
   - `workdayLen = workEnd - workStart - lunchLen`
4. Compute hourly rate:
   - `hourlyRate = monthlySalary / (workdaysPerMonth * (workdayLen / 60))`
5. Compute elapsed paid minutes up to `nowMin`, subtracting lunch overlap.
6. Compute earned amount for the selected day:
   - `earnedToday = hourlyRate / 60 * elapsedPaid`

Native calculation is split from presentation:

- `WageCalculator` outputs fact fields such as `status`, `regularEarnedToday`, `overtimeEarnedToday`, `totalEarnedToday`, `regularTargetToday`, paid minutes, overtime minutes, progress, and next work start.
- `WageDisplayModel` derives homepage titles, speech copy, summary rows, mascot choice, and widget copy.
- Non-workdays resolve to `dayOff` before overtime is considered, so Saturday/Sunday or unselected weekdays never auto-start overtime.
- `includeOvertime` uses a `1.0x` multiplier in this pass. The field exists as `overtimeMultiplier`, but there is no settings UI for it.

## Widget Contract

- Target: `WNFWidget`, embedded in the `WNF` app target.
- Bundle id: `com.wonangfei.app.WNFWidget`.
- App Group: `group.com.wonangfei.app`.
- Supported families: small, medium, large.
- Refresh policy: work and overtime states refresh about every minute; settled and day-off states refresh at lower frequency.
- Display behavior:
  - small: one-glance status such as 收工了 / 加班中 / 休息.
  - medium: amount plus paid duration or next work start.
  - large: settlement card, mascot, summary rows, and share-hint copy.

Important: the settings UI label says `午休`. Switch on means "has lunch break"; switch off means "没有午休". The data flag remains `noLunch`.

## Interaction Requirements

### 记录页

- 周 / 月 / 年 tabs must switch datasets.
- Chart bars must be tappable except future bars.
- Selected chart bar must show a callout and can be cleared.
- Privacy toggle must mask all money strings with dot placeholders.
- Hero total must recompute from salary/workday/lunch settings.

### 我的页

- Salary number must be editable by click/tap.
- Salary step controls change in increments of 500.
- Monthly workdays stepper is bounded from 1 to 31.
- Weekday pills toggle active state.
- Time controls use native time input.
- 午休 switch hides/reveals lunch rows and recomputes hourly rate.
- 计入加班 and 截图隐藏工资 are interactive switches.
- When 计入加班 is on, show the explanatory copy: `下班后金额会继续增长，并单独显示为加班多挣。`
- During overtime, the homepage shows `加班多挣` as the primary number and exposes `结束今日`; ending the workday freezes the day until the next calendar day.

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
- Build validation command: `xcodebuild -project WNF.xcodeproj -scheme WNF -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build`.
- Calculation smoke command: `swiftc WNF/WageCore.swift WNF/WageDisplayModel.swift WNFTests/WageCalculatorChecks.swift -o /tmp/wnf-wage-checks && /tmp/wnf-wage-checks`.
- 2026-05-16 validation: XcodeBuildMCP `build_sim` succeeded for scheme `WNF`; `WageCalculatorChecks passed`.
- The source prototype still includes Open Design canvas and tweak controls. For production, move only the screen components and shared tokens into the app shell.
- `assets/reference-screens/` contains visual inputs and may include duplicate imported versions. Treat it as reference material, not production bundle.
- `assets/mascot/hero-mascot.png` is currently used in both record achievement card and settings profile banner.
- The root app fixes the package asset paths through `WNF_MASCOT_ROOT`, so the same screen components work from both `/index.html` and `/assets/source/wonangfei.html`.
- The old 8-pose cow set remains useful for home screen state changes.
