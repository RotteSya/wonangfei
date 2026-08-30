# Design QA

## Comparison target

- Source visual truth:
  - Home: `/Users/shelingzhao/.codex/generated_images/01a05092-3791-7850-978f-0361d7f41ea7/exec-32b5acf4-2920-48f6-822c-43727be8a3c6.png`
  - Records: `/Users/shelingzhao/.codex/generated_images/01a05092-3791-7850-978f-0361d7f41ea7/exec-16b26ba5-1335-4c28-9fed-3b1e24bc28b4.png`
  - Settings: `/Users/shelingzhao/.codex/generated_images/01a05092-3791-7850-978f-0361d7f41ea7/exec-d9f0cb1e-1965-49f0-a257-751b55a10c09.png`
- Final implementation evidence:
  - Home: `build/verification/visual/home-working-final-pass2b.png`
  - Records: `build/verification/visual/test-ui-attachments-pass3/5F45F416-67F0-40C7-B177-6ED5E19B4ADC.png`
  - Settings: `build/verification/visual/test-ui-attachments-pass3/A8534B58-3060-4CD8-BF07-760350E93AE9.png`
- Final side-by-side evidence:
  - `build/verification/visual/compare-home-pass2.png`
  - `build/verification/visual/compare-records-pass2.png`
  - `build/verification/visual/compare-settings-pass2.png`

## Normalization

- Device viewport: iPhone 17, 402 × 874 points, portrait, light appearance.
- Implementation captures: 1206 × 2622 pixels at 3× density.
- Source visuals: 852 × 1844 pixels. Each source was normalized to 1206 × 2622 before horizontal composition with the implementation capture.
- Native status-bar and home-indicator regions remain visible in the implementation evidence. They are operating-system chrome, not app content.
- States:
  - Home: active afternoon work period, visible wage, typing mascot frame.
  - Records: month selected, chart at rest.
  - Settings: default visible values, workdays and lunch controls visible.

## Full-view comparison

- Typography: the display face is reserved for the wordmark and app headings; the wage and settings numbers retain the rounded/monospaced hierarchy from the source. Labels remain legible without wrapping or truncation.
- Spacing and layout: all three screens use the same horizontal margins, 22–28 point card radii, restrained hairlines, and a full-width three-item bottom navigation. The Records header reads as one continuous yellow summary rather than stacked bands.
- Colors and tokens: cream background, fixed brand yellow, black active surfaces, warm secondary surfaces, and cyan mascot glow are sourced from `WNFTheme`. Contrast remains clear in the tested light appearance.
- Image quality: the existing bundled cow assets and HEVC mascot video are used directly. The final home evidence shows the coworker typing with a laptop; no placeholder, emoji, handcrafted SVG, or code-drawn character substitute is present.
- Copy: mascot lines are selected from a finite curated pool and describe the mascot's own neighboring-workstation activity. Records and settings copy remains short, concrete, and consistent with the selected visual direction.
- Interactions: the pager, tab buttons, privacy toggle, records period selector, chart scrub, settings controls, share entry point, and bundled legal page were exercised by the passing UI tour.

Focused crops were not required: the three normalized full-screen comparisons preserve 1206-pixel screen width, and the wordmark, amount typography, segmented control, chart labels, settings values, icons, dividers, and mascot copy are all readable at that resolution.

## Comparison history

### Pass 1 — blocked

- [P2] Bottom navigation was too compact and hid inactive labels. The source uses three consistently readable icon-and-label items across most of the screen width.
  - Fix: changed `AppTabBar` to three fixed-width labeled items while preserving the interpolated active pill, overscroll compression, accessibility identifiers, and pager behavior.
- [P2] Home bubble content could be generated at runtime, which produced lines outside the approved coworker voice and made screenshot output unstable.
  - Fix: reduced `BubbleQuoteEngine` to the curated status-specific pool and kept the afternoon lead line `我先眯会儿，钱还在涨。`.
- [P2] The home mascot alternated between contexts, so a capture could lose the work/laptop cue present in the source.
  - Fix: constrained the home video sequence to the typing clip; motion still runs, but the mascot remains an independent coworker at its own laptop.

### Pass 2 — passed

- Post-fix evidence: `compare-home-pass2.png`, `compare-records-pass2.png`, and `compare-settings-pass2.png`.
- No actionable P0, P1, or P2 differences remain.
- Accepted differences:
  - Native status bar and home indicator add system-safe-area height.
  - Monetary amounts, elapsed time, workday count, selected weekdays, and chart bars are live product data rather than hard-coded mock values.
  - The mascot is animated, so pose varies within the approved typing context.

## Follow-up polish

- [P3] A future screenshot suite could seed a richer month history so every Records chart bar is populated in visual regression captures. This does not affect layout, aggregation, or interaction behavior.

final result: passed
