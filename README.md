# 窝囊费 WNF

上班时薪实时滚动的原生 SwiftUI iOS App。打开首页就能看见今天已经挣到的钱，一秒一秒往上滚。

- App Store：<https://apps.apple.com/app/id6780135826>
- 支持：<https://rottesya.github.io/wonangfei/support.html>

## 唯一启动命令

需要 macOS、Xcode、以及 iOS 26.5 simulator runtime。在仓库根目录执行：

```sh
./scripts/wnf verify
```

这是唯一的 bootstrap：环境自检、必要时创建 iPhone 17 模拟器、静态门禁、Debug 构建、单元测试、UI 测试、静态分析、unsigned Release 模拟器构建和 bundle 审计。不要另写一份 xcodebuild 菜谱。

阶段失败时先跑：

```sh
./scripts/wnf doctor
```

UI 测试经启动参数跳过引导，不必先手动点完 Onboarding。

可选、且不计入 `verify`：`./scripts/wnf store-check` 只读核对 App Store 元数据（需要 ASC 凭据；缺失凭据会说明原因并退出。禁止 apply / submit / 远端删除）。

## 交接

[AGENTS.md](AGENTS.md) 是唯一的交接文档。身份、架构、不可破坏契约、验证矩阵、发布边界、资产与许可、技术债都在那里。本 README 只负责把人领进门。

© 2026 SHE LINGZHAO
