# Component Library

组件来源：2026-05-16 活跃原型 `assets/source/*.jsx`。以下是交付后可复用的产品组件定义。

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
- Right action in the 2026-05-16 prototype: `PrivacyToggle`.
- Padding: `14px 20px 8px`.
- Use on: all three primary app screens.

### TabBar

- Type: floating iOS glass pill.
- Items: 首页, 记录, 我的.
- Active state: black pill background, yellow icon, white label.
- Inactive state: transparent item, ink-soft label/icon.
- Position: absolute bottom `18px`.
- Interaction: tap target is the full button, active item expands horizontally.

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
- Replacement mascot in the 2026-05-16 package: `assets/mascot/hero-mascot.png`
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

## Controls

### SegTabs

- 2026-05-16 use: 周 / 月 / 年 on record page.
- Container: ink pill, `padding: 3px`, radius `999px`.
- Active item: yellow fill, ink text.
- Inactive item: transparent, white at 65%.
- Interaction: active tab changes chart dataset and resets selected bar.

### BarChart

- 2026-05-16 use: record page weekly/monthly/yearly data.
- Bars: yellow for completed days, ink for selected day, pale cream for future days.
- Interaction:
  - tap available bar to select;
  - selected bar jumps by `-2px`;
  - callout appears above selected bar;
  - tap again or "取消选中" clears state.
- Year view: compact bar gaps and smaller labels.

### SalaryEditor

- Pattern: stepper buttons around an inline editable money number.
- Step: `500`.
- Keyboard:
  - Enter commits.
  - Escape restores previous value.
  - Blur commits.
- Privacy mode: displays masked value, but still allows editing when clicked.

### Stepper

- Pattern: small minus / value / plus inside soft yellow shell.
- Use for bounded numeric settings like monthly workdays.

### TimeRow

- Input: native `<input type="time">`.
- Shell: soft yellow pill with stroked icon.
- Use for work start/end and lunch start/end.

### ToggleRow + Switch

- Switch size: `50 x 30`.
- On track: ink; on knob: yellow.
- Off track: `#D7D2C5`; off knob: white.
- 2026-05-16 toggles:
  - 午休: on = has lunch break, off = no lunch.
  - 计入加班.
  - 截图隐藏工资.

### FoldAway

- Purpose: smoothly hide lunch time rows when 午休 is off.
- CSS: grid row transition from `1fr` to `0fr`.
- Timing: `0.3s cubic-bezier(.32,.72,0,1)`.

## Copy Tone

- Short, self-deprecating, specific.
- Use phrases like `再忍忍，钱在涨。`, `中午也在搬砖`, `丧但还顶得住`.
- Avoid corporate copy such as "提升效率", "智能洞察", "数据驱动".
