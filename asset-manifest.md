# Asset Manifest

## Mascot Assets

| Asset | Size | Current Role |
|---|---:|---|
| `assets/mascot/hero-mascot.png` | 1254 x 1254 | Current approved mascot thumbnail for record achievement and settings profile banner |
| `assets/mascot/cow-0-front-sad.png` | 512 x 576 | Cow pose: front sad |
| `assets/mascot/cow-1-three-q-sad.png` | 512 x 576 | Cow pose: three-quarter sad |
| `assets/mascot/cow-2-side-back.png` | 512 x 576 | Cow pose: side/back |
| `assets/mascot/cow-3-front-sad-2.png` | 512 x 576 | Cow pose: alternate front sad |
| `assets/mascot/cow-4-back.png` | 512 x 576 | Cow pose: back |
| `assets/mascot/cow-5-back-tail.png` | 512 x 576 | Cow pose: back with tail |
| `assets/mascot/cow-6-side-look.png` | 512 x 576 | Cow pose: side look |
| `assets/mascot/cow-7-three-q-sad-2.png` | 512 x 576 | Cow pose: alternate three-quarter |

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

## Native Onboarding Assets

These files are shipped through `WNF/Assets.xcassets` and are used by `WNF/OnboardingView.swift`.

| Source file | Asset catalog file | Current role |
|---|---|---|
| `/Users/shelingzhao/Documents/窝囊费素材/引导/p1.png` | `WNF/Assets.xcassets/OnboardingP1.imageset/onboarding-p1.png` | Page 1 hero |
| `/Users/shelingzhao/Documents/窝囊费素材/引导/p2.png` | `WNF/Assets.xcassets/OnboardingP2.imageset/onboarding-p2.png` | Page 2 salary setup hero |
| `/Users/shelingzhao/Documents/窝囊费素材/引导/p3午休.png` | `WNF/Assets.xcassets/OnboardingLunchSleep.imageset/onboarding-lunch-sleep.png` | Page 3 hero when lunch break is enabled |
| `/Users/shelingzhao/Documents/窝囊费素材/引导/p3睡醒.png` | `WNF/Assets.xcassets/OnboardingLunchWake.imageset/onboarding-lunch-wake.png` | Page 3 hero when lunch break is disabled |
| `/Users/shelingzhao/Documents/窝囊费素材/引导/p4.png` | `WNF/Assets.xcassets/OnboardingP4.imageset/onboarding-p4.png` | Page 4 completion hero |

All five onboarding hero PNGs should stay `1536 x 1024` with alpha. A white rectangle around the hero on device means the asset-catalog PNG lost transparency; the soft glow behind the hero is expected from `OnboardingImagePanel` / `LunchImagePanel`.

## Production Asset Guidance

- Do not ship all reference screens inside the production app.
- Keep `hero-mascot.png` and whichever `cow-*` poses are actually used by shipped screens.
- Compress large reference images only after deciding which are part of final marketing or App Store material.
- Preserve transparent PNG edges for cow poses; avoid placing yellow variants on yellow hero cards without contrast treatment.
- Preserve transparent PNG edges for onboarding hero assets, especially the two page-3 lunch-state variants.

## Native Home Media

These files are copied into the app bundle through the Xcode resources phase and are used by `WNF/HomeView.swift`.

| Source file | App resource | Current role |
|---|---|---|
| `/Users/shelingzhao/Documents/窝囊费素材/精灵图/打电脑.mp4` | `WNF/home-typing.mp4` | Home mascot loop clip |
| `/Users/shelingzhao/Documents/窝囊费素材/精灵图/无聊.mp4` | `WNF/home-bored.mp4` | Home mascot loop clip |

Both source clips are 960 x 960 mp4 files, about 15 seconds each. The native player mutes them and loops by shuffling the two clips once per cycle.
