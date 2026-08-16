# 窝囊费 WNF

上班时薪实时滚动的 iOS App。已上架 App Store，仓库当前版本 **1.1 (2)**。

[App Store](https://apps.apple.com/app/id6780135826) · 支持：<https://rottesya.github.io/wonangfei/support.html>

## 跑起来

- 前置：Xcode、iOS 26.5 runtime、`iPhone 17` 模拟器
- 打开 `WNF.xcodeproj`，scheme 只用 `WNF`（widget 经隐式依赖一并构建）
- 命令行构建 / 测试与环境自检见 [AGENTS.md](AGENTS.md) §2、§10

## 仓库结构

| 路径 | 内容 |
|---|---|
| `WNF/` | App 源码、Metal、字体、Asset Catalog、法务离线副本 |
| `WNFWidget/` | Widget + Live Activity UI |
| `WNFTests/` | 工资引擎与凭证渲染测试 |
| `WNFUITests/` | `testGrandTour` 巡演 |
| `docs/` | GitHub Pages（ASC 已提交的营销 / 隐私 / 支持页） |
| `metadata/` | asc CLI 按版本分目录的商店文案 |

## 给开发者（人或 AI）

本项目的单一真理源是 [AGENTS.md](AGENTS.md)。架构、不变量、构建契约、发布流程全部在那里。本 README 不重复任何细节。

## 版权

© 2026 SHE LINGZHAO
