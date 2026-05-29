import SwiftUI

struct ClockOutCTA: View {
    var status: WorkStatus
    var isSettled: Bool = false
    var action: () -> Void

    private var title: String {
        if isSettled { return "今日已下班 · 再看一眼" }
        switch status {
        case .before, .morning, .afternoon, .lunch: return "查看今天挣多少"
        case .done: return "下班！领今天的窝囊费"
        }
    }

    private var subtitle: String {
        if isSettled { return "今日窝囊费已入账，剩下都是你的时间" }
        switch status {
        case .before: return "今天的窝囊费还没开张"
        case .morning: return "已经熬过早上的两小时最值钱"
        case .lunch: return "午休回血中，要不要看看今天挣多少"
        case .afternoon: return "再忍忍，也可以提前看看战绩"
        case .done: return "数据已自动保存，想收工时再点"
        }
    }

    private var iconName: String {
        isSettled ? "checkmark.circle.fill" : "tray.and.arrow.down.fill"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(WNFTheme.ink)
                        .frame(width: 36, height: 36)
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(WNFTheme.yellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(WNFTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(WNFTheme.inkSoft)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WNFTheme.ink.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(WNFTheme.yellow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: WNFTheme.yellow.opacity(0.4), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
