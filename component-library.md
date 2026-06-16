# Component Library

组件来源：当前活跃原型 `assets/source/*.jsx`。以下是交付后可复用的产品组件定义。

## Foundation

### iOS Frame

- Source: `assets/source/窝囊费.html`
- Size: `402 x 874`
- Radius: `48px`
- Background: `#FFF6E5`
- Includes: Dynamic Island, iOS status bar, home indicator.
- Rule: Product screens are rendered inside the frame; do not bake frame chrome into individual screen components.

### Theme Tokens

- Source: `assets/source/shared.jsx`
- Export: `T`, `FONT_DISPLAY`, `FONT_BODY`, `FONT_MONO`
- Implementation baseline: `brand-tokens.css` and `design-tokens.json`

## Navigation

### TopBar

- Structure: `Wordmark` left, one right-side action.
- Home right action: share button, labeled `分享今日窝囊费`.
- Record/settings right action: `PrivacyToggle`.
- Native contract: owns full-width layout and `22pt` horizontal padding, so the left wordmark and right action align across all three primary screens.
- Prototype padding: `14px 20px 8px`.
- Use on: all three primary app screens.

### TabBar

- Type: floating iOS glass pill.
- Items: 首页, 记录, 我的.
- Active state: black pill background, yellow icon, white label.
- Inactive state: transparent item, ink-soft label/icon.
- Position: absolute bottom `18px`.
- Interaction: tap target is the full button, active item expands horizontally.
- Native (current): `AppTabBar(progress:onSelect:)` in `WNF/PagerShell.swift`. The ink pill is driven by a *continuous* pager position (`0…2`), so it glides, stretches, and squishes against the wall in lock-step with an in-progress swipe rather than snapping between discrete tabs. Tabs are an interactive jelly pager (see Jelly Pager Shell), not a slide+crossfade.

### Jelly Pager Shell

- Owner: `WNF/RootView.swift` (`tabPager`, `pagerDragGesture`, `commitPager`, `selectTab`).
- All three pages stay mounted in one horizontal strip; a `simultaneousGesture` drag steers it 1:1 with a directional axis lock (vertical scrolls inside a page win), rubber-banded ends, and a velocity-seeded `interpolatingSpring` settle.
- Feel: the strip squashes/stretches via `JellyStretch` while moving and wobbles out on arrival; outgoing pages get `PageDepthFX` parallax + dim + scale; landing fires a `rigid` haptic.
- `HorizontalGestureArbiter` resolves the swipe vs. the records chart-scrub for a single touch. `@GestureState` recovers cancelled gestures (system steal / app switch).
- Reduce Motion: swaps springs for short eases and drops the jelly/parallax.

## Brand

### Wordmark

- Composition: cow image + `窝囊费` + yen badge.
- Font: `FONT_DISPLAY`.
- Default size: `20px` in top bars.
- Rule: Keep as a compact UI lockup. For splash/marketing, create a larger lockup rather than scaling this blindly.

### Cow Mascot

- Source component: `Cow({ pose, size })`.
- Pose map:
  - `front-sad`: `assets/mascot/cow-0-front-sad.png`
  - `three-q`: `assets/mascot/cow-1-three-q-sad.png`
  - `side-back`: `assets/mascot/cow-2-side-back.png`
  - `front-sad-2`: `assets/mascot/cow-3-front-sad-2.png`
  - `back`: `assets/mascot/cow-4-back.png`
  - `back-tail`: `assets/mascot/cow-5-back-tail.png`
  - `side-look`: `assets/mascot/cow-6-side-look.png`
  - `three-q-2`: `assets/mascot/cow-7-three-q-sad-2.png`
- Current replacement mascot: `assets/mascot/hero-mascot.png`
- Rule: Avoid placing yellow-body mascot variants directly on full yellow backgrounds unless there is enough edge contrast.

### YenBadge

- Shape: rounded square, radius = `size * 0.22`.
- Fill: `linear-gradient(135deg, #FFE680 0%, #FFD24D 100%)`.
- Text: white `¥`, display font.
- Use: wordmark, profile labels, money tags.

## Cards And Content

### Hero Card

- Radius: `28px`
- Padding: `20px 22px 22px`
- Main fills:
  - record page: `#FFC83D`
  - settings profile banner: `#0D0D0D`
- Decoration: oversized low-opacity `¥` watermark only.
- Rule: one hero card should own the screen's primary message.

### Tile

- Purpose: compact financial or status metric.
- Fill: white.
- Radius: `20px`.
- Border: `0.5px solid rgba(13,13,13,0.08)`.
- Accent dot: yellow by default, cyan/coral for secondary metric classes.
- Numeric text: mono, tabular.

### Achievement Card

- Fill: `#0D0D0D`.
- Text: white + yellow highlight.
- Thumbnail: `hero-mascot.png`, `56 x 56`, radius `18px`.
- Use for celebratory/emotional state summaries, not routine metrics.

### Share Card

- Use on: home page share overlay.
- Container: rounded cream card, max width close to `330px` on iPhone 17 portrait.
- Header: yellow band with compact mascot, `窝囊费`, `今日窝囊战报`, and three icon controls.
- Copy behavior: `RootView` refreshes the active `ShareCardCopy` from `ShareCardCopy.pool` whenever the home share action opens the card. The current pair is excluded when possible, so consecutive opens do not repeat the same wording.
- Controls:
  - eye / eye slash masks only the card amount and duration;
  - share shows an inline loading spinner, disables repeat taps while rendering, and exports a control-free card image through iOS system share using the current `UIWindowScene.screen.scale`; the spinner pre-flight is UX/perceptual feedback only because `ImageRenderer.render(rasterizationScale:)` plus `UIGraphicsImageRenderer` remain main-thread bound; the activity presenter must provide a UIKit popover source view for iPad / Mac Catalyst;
  - x closes the overlay.
- Body: active headline pair, small cow pose, dashed-inner stats panel with `今日窝囊费` and `上班上了多久`, and branded footer.
- Active copy:
  - Title: `今天没有赢，但到账了。`
  - Subtitle: `工位把我按住，工资负责安慰。`
- Alternate title/subtitle copy pool:
  - `人在工位，钱在路上。` / `今天又把生活按时熬过一段。`
  - `今天也没翻身，但有进账。` / `打工的委屈，先折成数字存起来。`
  - `班是上的，钱是到账的。` / `没有热血剧情，只有稳定入账。`
  - `又被工作拿捏，也被工资哄好。` / `今天的窝囊，明天再继续算。`
  - `体面没赢，余额加分。` / `把不想上班的心情，换成可见进度。`
  - `工位困住我，到账放过我。` / `今天的辛苦，有数字替我作证。`
- Overlay: home content remains underneath but blurred and dimmed across the full screen, including status bar and bottom home-indicator areas; tapping outside closes the card.

### Clock-Out CTA

- Source: `WNF/DailySettlement.swift`.
- Use on: home page, directly below the progress track; hidden until the workday is done unless today is settled.
- Container: ink-filled rounded rectangle, radius `18px`, padding `12px 16px`, drop shadow.
- Leading icon: yellow circle (`36px`) with `tray.and.arrow.down.fill`.
- Copy adapts to `WorkStatus`:
  - `.before`, `.morning`, `.lunch`, `.afternoon`: hidden on Home.
  - `.done`: `下班！领今天的窝囊费` / `数据已自动保存，想收工时再点`
- Trailing affordance: small `arrow.right` chevron, white at 82%.
- Tap: opens settlement overlay via `RootView.presentSettlement()`.
- Product contract: daily records auto-save through state/storage; CTA only starts the optional clock-out ritual and must not be paired with forced popups, red dots, or repeat nagging.

### Settlement Overlay

- Source: `WNF/DailySettlement.swift`.
- Trigger: only from the home Clock-Out CTA.
- Phases:
  - `prep` → `burst` (≈0.85s, heavy haptic on entry, central yen + radial gradient explode outward into a coin/confetti shower)
  - `burst` → `reveal` (≈0.55s spring, settlement card scales/opacity in, amount text content-transitions 0 → today's amount)
  - 底部 action 行延后 0.18s ease-in 出现
- Skip control: top-right `跳过` capsule visible until `reveal` phase, completes burst immediately.
- Background: full-bleed black at 0.62 opacity during `reveal`, 0.32 during `burst`; tap-to-dismiss only enabled during `reveal`.
- Bottom action row:
  - Primary `存入资产`: ink fill, white text, persists today's snapshot through `WageState.persistCurrentDaySnapshot()` and emits success haptic.
  - Secondary `分享卡片`: white fill, ink text, drives system share through the existing `ImageRenderer` pipeline; shows `渲染中…` while preparing.
- Hides bottom tab bar while presented (same contract as share card).

### Clock-Out Reminder Row

- Source: `WNF/SettingsView.swift` (`clockOutReminderCard`), service in `WNF/ClockOutReminder.swift`.
- Use on: Settings page, dedicated `提醒` `SectionCard`.
- Default state: **OFF**. The toggle must reflect `WageState.clockOutReminderEnabled` and write through that binding so persistence + scheduling stay aligned.
- Primary row:
  - Title `下班结算提醒` (15pt heavy ink).
  - Subtitle `默认关闭。开启后每天 HH:MM 通知一次。`，时间从 `WageState.workEnd.clockText` 实时取值。
  - Trailing `WNFToggle` bound to a `Binding` that triggers `ClockOutReminderService.requestAuthorizationIfNeeded()` on flip-to-on.
- System-permission hint (only when toggle is on AND `UNAuthorizationStatus == .denied`):
  - Coral `exclamationmark.bubble.fill` glyph.
  - Copy `iOS 通知权限被关闭，到系统设置开启后才会真的弹通知。`
  - Trailing `arrow.up.right.square`; tap calls `UIApplication.open(UIApplication.openNotificationSettingsURLString)`.
- The hint banner must never appear when `clockOutReminderEnabled == false` (toggle off implies user opted out — no need to nag).

### Settlement Share Card

- Source: `WNF/DailySettlement.swift`.
- Use on: settlement overlay and the system share image.
- Container: rounded card, radius `30px`, max width `340pt` in overlay, fixed `360pt` width when exported.
- Header: yellow band, compact mascot, `窝囊费`, `今日下班结算`, and three icon controls (eye / share / close) when `showsControls == true`.
- Body order (top → bottom):
  - Dynamic headline + subcopy from `DailySettlement.headline` / `.subCopy`.
  - Amount panel: `今日窝囊费` label, sentiment badge (emoji + label), large yen-prefixed amount with content-transition driven `displayedAmount` for ticker animation.
  - Stats row (three tiles): `忍耐指数` (1-4 yellow stars), `已忍时长` (h/min split), `连续打工` (天 / 暂无，封顶 60 天).
  - `今日最佳忍耐时刻` quote card (`SettlementQuoteCard`, `quote.opening` glyph) — long-press to swap when shown in overlay.
  - `累积窝囊费` row: `tray.full.fill` glyph + value pill from `DailySettlement.cumulativeEarned`.
  - Footer: `丧萌有理 · 自嘲无罪` left, `来自窝囊费` right with yen badge.
- Privacy: eye toggle masks amount (`•••.••`), duration (`••h••min`), and cumulative (`¥•••.••`); fallback share text also honors the mask.
- Tear gesture is only active in overlay (`showsControls == true`); when the card is rendered for share-image export, `onTearBestMoment` is `nil` so no long-press hint shows up in the exported image.

### Settlement Quote Card

- Source: `WNF/DailySettlement.swift` (private subview `SettlementQuoteCard`).
- Use on: inside Settlement Share Card for `今日最佳忍耐时刻`.
- Container: white-translucent card, radius `16px`, hairline outline.
- Content: leading SF Symbol glyph + quote text. The text honors an `.id(combined)` modifier so SwiftUI plays insertion/removal transitions when the parent swaps the string.
- Tear gesture:
  - `.onLongPressGesture(minimumDuration: 0.4)` with `onPressingChanged` for visible compress feedback.
  - On commit: triggers `rigid` haptic and calls back to the parent, which picks a different pool entry (`DailySettlement.alternateBestMoment(excluding:)`) and wraps the swap in `withAnimation`.
  - Below the quote, an optional `hand.tap` + `长按可换一句` hint surfaces; the hint is omitted when no `onTear` is wired (e.g., in the exported share image).
- Accessibility: includes `accessibilityHint` describing the long-press affordance when active.

### Personal Time CTA

- Source: `WNF/DailySettlement.swift` (`ClockOutCTA` with `isSettled` flag), driven from `HomeView`.
- Active when `WageState.isTodaySettled == true` (today's date key matches `lastSettlementDateKey`).
- Visual differences vs default Clock-Out CTA:
  - Leading icon: `checkmark.circle.fill` (was `tray.and.arrow.down.fill`).
  - Title: `今日已结算 · 再看一眼`.
  - Subtitle: `进入个人时间，钱已经稳了`.
- Status chip on Home also swaps to `今日已结算 · 个人时间` when settled.
- Live wage amount, elapsed/remaining time, progress bar, and mascot all stay real-time — settled mode is a tone shift, not a data freeze.
- Day boundary naturally resets the state when `currentDateKey` advances past the stored date.

### Settings Page Order

The Settings (`我的`) scroll, top to bottom:

1. `profileBanner` (ink hero card with mascot)
2. `收入` SectionCard (salary, monthly workdays, hourly rate)
3. `weekdaysCard` (工作日)
4. `时间` SectionCard (work-start, work-end, lunch toggle + lunch rows; work-start/work-end edits route through `WageState` validated setters so end stays after start)
5. `clockOutReminderCard` (提醒 — see below)
6. `其它` SectionCard (计入加班 toggle)
7. `引导` SectionCard (重新设置工资/时间)
8. `legalFooter`
9. `footer` (algorithmic-cynicism note)

### Legal Footer

- Source: `WNF/SettingsView.swift` (`legalFooter`).
- Position: at the very bottom of the Settings scroll, just above the brand footer.
- Two text-button links separated by a `·`: `Terms of Use` and `Privacy Policy`, both opening `LegalDocumentView` as a sheet.
- Style: `11pt heavy` inkSoft, centered.

### Widget Cards

- Source: `WNFWidget/WNFWidget.swift`.
- Families: `.systemSmall`, `.systemMedium`, `.accessoryRectangular`, `.accessoryInline`.
- Shared data/projection source: `WNF/WidgetShared.swift` is compiled into both app and widget targets for App Group keys, snapshot schema, fixed sample data, projection, and capped timeline planning.
- Gallery/placeholder data: fixed sample amount such as `¥888.88`; never read real App Group wage data in preview mode.
- Real timeline: reads from the App Group snapshot only, emits capped near-term minute entries, and reloads near the cap window or the next selected workday start.
- Required rendering wrapper: `containerBackground(for: .widget)` on every widget view.
- Amount visibility follows App privacy mode through `hidesSensitiveInfo` in the App Group snapshot; masked value is `¥•••.••`.

### Onboarding Hero Panel

- Use on: native SwiftUI onboarding pages.
- Source: `WNF/OnboardingView.swift`.
- Static image pages: `OnboardingP1`, `OnboardingP2`, `OnboardingP4`.
- Page 1 wraps `OnboardingP1` in `OnboardingIntroPage`, using a taller visual area and no accessory card.
- Lunch-state page:
  - `OnboardingLunchSleep` appears when `WageState.hasLunchBreak` is true.
  - `OnboardingLunchWake` appears when `WageState.hasLunchBreak` is false.
- Visual treatment: transparent PNG over the panel's soft white/yellow glow, with slight saturation/contrast and a light shadow.
- Rule: replace the asset-catalog PNGs directly and verify alpha on the target files before building.

## Controls

### SegTabs / PeriodSwitcher

- Current use: 周 / 月 / 年 on record page.
- Native (current): `PeriodSwitcher` in `WNF/RecordsView.swift` — a hand-rolled segmented control where the ink pill slides between items via `matchedGeometryEffect` + spring (not a system `Picker`), riding on the hero card's yellow with a translucent track. Selection changes fire a `selection` haptic and a `.squish` press.
- Interaction: active tab changes chart dataset and resets selected bar.

### Odometer Money (home)

- Owner: `OdometerMoneyText` in `WNF/OdometerText.swift`; the home page's primary number.
- Each digit is an independent slot-machine wheel that rolls up gas-pump style on increase, with a per-wheel stagger cascading from the cents. Whole-yuan rollovers pop a `+¥1` chip and pulse the row; a gold shimmer sweeps the glyphs.
- Sizing: font tiers by integer-digit count plus a deterministic `fitScale` and a hard `maxWidth` layout cap (callers pass the readout column width). The cap is mandatory — a scaled view still claims its natural width, so without it a large salary clips and stretches the TopBar.
- Privacy mode renders masked dots; Reduce Motion swaps wheel rolls for crossfades and disables chips/shimmer.

### BarChart

- Current use: record page weekly/monthly/yearly data derived from a memoized `RecordsView` aggregation snapshot. The snapshot reads retained daily SQLite rows plus folded monthly summaries when rebuilt, but cache equality is keyed by `WageState.currentDateKey`, `WageState.recordsRevision`, live-day wage settings, `includeOvertime`, and `selectedWeekdays` rather than comparing the full storage dictionaries.
- Data contract: `RecordBar.amount` is an already-aggregated currency value; do not use visual-only multipliers for production records.
- Placement: promoted directly under the hero card (above the metric tiles) so the scrub gesture sits above the fold.
- Bars: yellow for completed/current periods until selected, ink only for selected, pale cream for future; today's bar carries a soft gold top-gradient + breathing glow.
- Entrance: on period change (`.id(period)`) bars grow from the floor with a per-bar spring stagger.
- Interaction:
  - scrub-to-read — press and drag across the chart to sweep the selection, with a `selection` haptic per bar boundary (arbitrated against the pager swipe via `HorizontalGestureArbiter`);
  - selected bar jumps by `-2px` with a spring callout above it;
  - a stationary tap on the already-selected bar clears state.
- Reduce Motion: skips the staggered grow-in and the today-bar glow.
- Week view groups Monday through Sunday, month view groups current-month 7-day buckets, and year view groups calendar months. Year bars include folded monthly summaries and replace today's persisted row with the current live-day calculation.
- Year view: compact bar gaps and smaller labels.

### SalaryEditor

- Pattern: stepper buttons around an inline editable money number.
- Step: `500`.
- Native SwiftUI behavior: tapping the center value opens a numeric quick-entry alert; confirming commits through the same bounded state setter used by the stepper buttons.
- Privacy mode: displays a masked value in the row, but the quick editor opens with the unmasked numeric salary from app state.

### Stepper

- Pattern: small minus / value / plus inside soft yellow shell.
- Use for bounded numeric settings like monthly workdays.
- Native SwiftUI behavior: the center value is also a button that opens a numeric quick-entry alert. Monthly workdays clamp to `1...31`; salary clamps to `0...100000`.

### TimeRow

- Input: native `<input type="time">`.
- Shell: soft yellow pill with stroked icon.
- Use for work start/end and lunch start/end.

### ToggleRow + Switch

- Switch size: `50 x 30`.
- On track: ink; on knob: yellow.
- Off track: `#D7D2C5`; off knob: white.
- Current toggles:
  - 午休: on = has lunch break, off = no lunch.
  - 计入加班.

### FoldAway

- Purpose: smoothly hide lunch time rows when 午休 is off.
- CSS: grid row transition from `1fr` to `0fr`.
- Timing: `0.3s cubic-bezier(.32,.72,0,1)`.

## Copy Tone

- Short, self-deprecating, specific.
- Use phrases like `再忍忍，钱在涨。`, `中午也在搬砖`, `丧但还顶得住`.
- Avoid corporate copy such as "提升效率", "智能洞察", "数据驱动".
