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
- Native transition: tab content slides horizontally by tab order and crossfades; bottom selected state animates with the same snappy timing.

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
  - share shows an inline loading spinner, disables repeat taps while rendering, and exports a control-free card image through iOS system share using the current `UIWindowScene.screen.scale`; the activity presenter must provide a UIKit popover source view for iPad / Mac Catalyst;
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

### SegTabs

- Current use: 周 / 月 / 年 on record page.
- Container: ink pill, `padding: 3px`, radius `999px`.
- Active item: yellow fill, ink text.
- Inactive item: transparent, white at 65%.
- Interaction: active tab changes chart dataset and resets selected bar.

### BarChart

- Current use: record page weekly/monthly/yearly data derived from a memoized `RecordsView` aggregation snapshot. The snapshot reads stored daily records when rebuilt, but cache equality is keyed by `WageState.currentDateKey`, `WageState.recordsRevision`, and live-day wage settings rather than comparing the full records dictionary.
- Data contract: `RecordBar.amount` is an already-aggregated currency value; do not use visual-only multipliers for production records.
- Bars: yellow for completed/current periods until selected, ink only for selected, pale cream for future.
- Interaction:
  - tap available bar to select;
  - selected bar jumps by `-2px`;
  - callout appears above selected bar;
  - tap the selected bar again to clear state.
- Week view groups Monday through Sunday, month view groups current-month 7-day buckets, and year view groups calendar months.
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
