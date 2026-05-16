# Asset Manifest

## Mascot Assets

| Asset | Size | Role |
|---|---:|---|
| `assets/mascot/hero-mascot.png` | 1254 x 1254 | Approved mascot thumbnail for record achievement and settings profile banner |
| `assets/mascot/cow-0-front-sad.png` | 512 x 576 | Cow pose: front sad |
| `assets/mascot/cow-1-three-q-sad.png` | 512 x 576 | Cow pose: three-quarter sad |
| `assets/mascot/cow-2-side-back.png` | 512 x 576 | Cow pose: side/back |
| `assets/mascot/cow-3-front-sad-2.png` | 512 x 576 | Cow pose: alternate front sad |
| `assets/mascot/cow-4-back.png` | 512 x 576 | Cow pose: back |
| `assets/mascot/cow-5-back-tail.png` | 512 x 576 | Cow pose: back with tail |
| `assets/mascot/cow-6-side-look.png` | 512 x 576 | Cow pose: side look |
| `assets/mascot/cow-7-three-q-sad-2.png` | 512 x 576 | Cow pose: alternate three-quarter |

## Native App Media

| Asset | Role |
|---|---|
| `WNF/HomeSprite.mov` | Bundled homepage mascot loop. `HomeView` uses it for all homepage states when present; state-specific static mascot assets remain the fallback if the MOV is missing. Current 2026-05-16 source replacement is `/Users/shelingzhao/Movies/CapCut/0515(1).mov` (`HEVC with Alpha`, 2160 x 2160, about 10.03s, 42,898,189 bytes). |

## Reference Screens

The folder `assets/reference-screens/` contains the imported visual material set. These files are preserved as references for palette, mascot direction, logo feel, app-surface rhythm, and brand manual material.

Key reference files:

- `logo.png` — wide logo reference, 2054 x 766.
- `image (1).png` and `image (1)-0e48ae82.png` — wide visual references, 3840 x 2160.
- `1.png` through `10.png` and hashed siblings — vertical app/brand reference boards.
- `1778750231385.png` — wide imported reference, 2048 x 1152.

## Source Snapshot

The folder `assets/source/` contains the current prototype implementation at packaging time:

- `窝囊费.html`
- `wonangfei.html` — ASCII filename copy of `窝囊费.html`
- `shared.jsx`
- `home.jsx`
- `stats.jsx`
- `settings.jsx`
- `cow.jsx`
- `ios-frame.jsx`
- `design-canvas.jsx`
- `tweaks-panel.jsx`

## Production Asset Guidance

- Do not ship all reference screens inside the production app.
- Keep `hero-mascot.png` and whichever `cow-*` poses are actually used by shipped screens.
- Compress large reference images only after deciding which are part of final marketing or App Store material.
- Preserve transparent PNG edges for cow poses; avoid placing yellow variants on yellow hero cards without contrast treatment.
