# WNF Agent Notes

截至 2026-05-16，真实实现面是原生 SwiftUI 工程 `WNF.xcodeproj`，不是单独的 HTML/Open Design 原型。HTML/JSX 文件仍是视觉和交接参考。

## Build And Checks

- App + Widget build: `xcodebuild -project WNF.xcodeproj -scheme WNF -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build`
- Calculation smoke check: `swiftc WNF/WageCore.swift WNF/WageDisplayModel.swift WNFTests/WageCalculatorChecks.swift -o /tmp/wnf-wage-checks && /tmp/wnf-wage-checks`

## Architecture Snapshot

- App settings persist through `WageSettings` in standard `UserDefaults` key `wnf.settings.v1`.
- Widget reads the same configuration snapshot from App Group `group.com.wonangfei.app`, key `wnf.widget.settings.v1`.
- `WageCalculator` should stay fact-only: status, regular/overtime/total income, paid minutes, overtime minutes, progress, and next work start.
- `WageDisplayModel` owns copy and display choices such as homepage headline, summary rows, mascot asset, and Widget wording.
- Non-workdays must resolve to `dayOff` before overtime logic. Do not let `includeOvertime` auto-start overtime on unselected weekdays.

## Working Rules

- Preserve local-first behavior; no remote backend is involved in this app state.
- Keep `HomeSprite.mov` as the homepage mascot media when it is bundled. Static mascot assets are the fallback for missing media, while Widget continues to use static `WageDisplayModel.mascotAsset` images.
- When changing Widget behavior, keep App and Widget on the same `WageSettings` / `WageCalculator` / `WageDisplayModel` contract.
