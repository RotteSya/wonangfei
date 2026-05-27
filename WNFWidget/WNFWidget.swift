import AppIntents
import SwiftUI
import WidgetKit

private enum WNFWidgetShared {
    static let appGroupID = "group.com.wonangfei.app"
    static let widgetSnapshotKey = "wnf.widget.wage.snapshot.v1"
    static let premiumURL = URL(string: "https://wonangfei.app/premium")!
}

private enum WidgetThemeID: String, Codable {
    case classic
    case nightShift
    case mintReceipt
    case punchCard
}

private struct WidgetSnapshot: Codable {
    var schemaVersion: Int
    var capturedAt: Date
    var earnedToday: Double
    var elapsedPaidMinutes: Int
    var workStartMinute: Int
    var workEndMinute: Int
    var statusLabel: String
    var isPremiumUnlocked: Bool
    var selectedTheme: WidgetThemeID
    var lockScreenShowsAmount: Bool

    static let sample = WidgetSnapshot(
        schemaVersion: 1,
        capturedAt: Date(),
        earnedToday: 888.88,
        elapsedPaidMinutes: 188,
        workStartMinute: 9 * 60 + 30,
        workEndMinute: 18 * 60 + 30,
        statusLabel: "正在搬砖",
        isPremiumUnlocked: true,
        selectedTheme: .classic,
        lockScreenShowsAmount: true
    )
}

private struct WidgetPalette {
    var bg: Color
    var surface: Color
    var accent: Color
    var ink: Color
    var muted: Color

    static func palette(for theme: WidgetThemeID) -> WidgetPalette {
        switch theme {
        case .classic:
            WidgetPalette(bg: Color(red: 1.0, green: 0.9647, blue: 0.8980), surface: .white, accent: Color(red: 1.0, green: 0.7843, blue: 0.2392), ink: .black, muted: Color(red: 0.60, green: 0.58, blue: 0.54))
        case .nightShift:
            WidgetPalette(bg: Color(red: 0.12, green: 0.14, blue: 0.19), surface: Color(red: 0.18, green: 0.20, blue: 0.27), accent: Color(red: 0.94, green: 0.78, blue: 0.30), ink: .white, muted: Color.white.opacity(0.68))
        case .mintReceipt:
            WidgetPalette(bg: Color(red: 0.94, green: 0.98, blue: 0.94), surface: .white, accent: Color(red: 0.72, green: 0.86, blue: 0.36), ink: Color(red: 0.08, green: 0.16, blue: 0.12), muted: Color(red: 0.48, green: 0.58, blue: 0.50))
        case .punchCard:
            WidgetPalette(bg: Color(red: 1.00, green: 0.94, blue: 0.90), surface: .white, accent: Color(red: 1.00, green: 0.70, blue: 0.32), ink: Color(red: 0.12, green: 0.08, blue: 0.08), muted: Color(red: 0.62, green: 0.46, blue: 0.42))
        }
    }
}

struct WNFWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "窝囊费小组件"
    static var description = IntentDescription("显示今日窝囊费。v1 暂无可配置参数，后续可加入每个小组件独立主题和隐私设置。")
}

private struct WNFWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
    var isPreview: Bool
}

private struct WNFWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WNFWidgetEntry {
        WNFWidgetEntry(date: Date(), snapshot: .sample, isPreview: true)
    }

    func snapshot(for configuration: WNFWidgetConfigurationIntent, in context: Context) async -> WNFWidgetEntry {
        WNFWidgetEntry(
            date: Date(),
            snapshot: context.isPreview ? .sample : loadSnapshot() ?? lockedSnapshot(),
            isPreview: context.isPreview
        )
    }

    func timeline(for configuration: WNFWidgetConfigurationIntent, in context: Context) async -> Timeline<WNFWidgetEntry> {
        let snapshot = context.isPreview ? WidgetSnapshot.sample : loadSnapshot() ?? lockedSnapshot()
        let entry = WNFWidgetEntry(date: Date(), snapshot: snapshot, isPreview: context.isPreview)
        return Timeline(entries: [entry], policy: reloadPolicy(for: snapshot, now: Date()))
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: WNFWidgetShared.appGroupID)?.data(forKey: WNFWidgetShared.widgetSnapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    private func lockedSnapshot() -> WidgetSnapshot {
        var sample = WidgetSnapshot.sample
        sample.isPremiumUnlocked = false
        sample.capturedAt = Date()
        return sample
    }

    private func reloadPolicy(for snapshot: WidgetSnapshot, now: Date) -> TimelineReloadPolicy {
        guard snapshot.isPremiumUnlocked else {
            return .after(now.addingTimeInterval(60 * 30))
        }

        let calendar = Calendar.current
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if minute >= snapshot.workStartMinute && minute <= snapshot.workEndMinute {
            return .after(now.addingTimeInterval(60))
        }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = snapshot.workStartMinute / 60
        components.minute = snapshot.workStartMinute % 60
        components.second = 0
        var nextStart = calendar.date(from: components) ?? now.addingTimeInterval(60 * 60)
        if nextStart <= now {
            nextStart = calendar.date(byAdding: .day, value: 1, to: nextStart) ?? now.addingTimeInterval(60 * 60)
        }
        return .after(nextStart)
    }
}

private struct WNFWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WNFWidgetEntry

    private var palette: WidgetPalette {
        WidgetPalette.palette(for: entry.snapshot.selectedTheme)
    }

    var body: some View {
        content
            .widgetURL(WNFWidgetShared.premiumURL)
            .containerBackground(for: .widget) {
                palette.bg
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryRectangular:
            rectangularLockScreen
        case .systemMedium:
            mediumWidget
        default:
            smallWidget
        }
    }

    private var inlineText: String {
        if entry.isPreview {
            return "窝囊费 ¥888.88 王牌打工人"
        }
        guard entry.snapshot.isPremiumUnlocked else {
            return "窝囊费 · 王牌打工人专属"
        }
        guard entry.snapshot.lockScreenShowsAmount else {
            return "窝囊费 \(entry.snapshot.statusLabel)"
        }
        return "窝囊费 \(money(entry.snapshot.earnedToday))"
    }

    private var rectangularLockScreen: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.snapshot.isPremiumUnlocked || entry.isPreview ? "今日窝囊费" : "王牌打工人专属")
                .font(.caption2.weight(.heavy))
            Text(lockScreenAmountText)
                .font(.headline.weight(.black))
                .minimumScaleFactor(0.75)
            Text(entry.snapshot.isPremiumUnlocked || entry.isPreview ? entry.snapshot.statusLabel : "解锁后打开")
                .font(.caption2.weight(.semibold))
        }
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader
            Spacer(minLength: 0)
            Text(entry.snapshot.isPremiumUnlocked || entry.isPreview ? money(entry.snapshot.earnedToday) : "王牌打工人")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(palette.ink)
                .minimumScaleFactor(0.65)
            Text(entry.snapshot.isPremiumUnlocked || entry.isPreview ? entry.snapshot.statusLabel : "解锁后查看今天进账")
                .font(.caption.weight(.heavy))
                .foregroundStyle(palette.muted)
        }
        .padding()
    }

    private var mediumWidget: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                widgetHeader
                Text(entry.snapshot.isPremiumUnlocked || entry.isPreview ? money(entry.snapshot.earnedToday) : "王牌打工人专属")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .minimumScaleFactor(0.62)
                Text(entry.snapshot.isPremiumUnlocked || entry.isPreview ? "已忍 \(duration(entry.snapshot.elapsedPaidMinutes))" : "打开 App 解锁桌面/锁屏小组件")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(palette.muted)
            }
            Spacer()
            Text("¥")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(palette.accent)
                .frame(width: 78, height: 78)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 24))
        }
        .padding()
    }

    private var widgetHeader: some View {
        HStack(spacing: 6) {
            Text("¥")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 5))
            Text("窝囊费")
                .font(.caption.weight(.black))
                .foregroundStyle(palette.ink)
            if entry.isPreview || !entry.snapshot.isPremiumUnlocked {
                Text("王牌打工人")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(palette.accent, in: Capsule())
            }
        }
    }

    private var lockScreenAmountText: String {
        if entry.isPreview { return "¥888.88" }
        guard entry.snapshot.isPremiumUnlocked else { return "解锁后查看" }
        guard entry.snapshot.lockScreenShowsAmount else { return "¥•••.••" }
        return money(entry.snapshot.earnedToday)
    }

    private func money(_ value: Double) -> String {
        String(format: "¥%.2f", value)
    }

    private func duration(_ minutes: Int) -> String {
        "\(minutes / 60)h\(minutes % 60)min"
    }
}

struct WNFWidget: Widget {
    let kind = "WNFWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WNFWidgetConfigurationIntent.self, provider: WNFWidgetProvider()) { entry in
            WNFWidgetView(entry: entry)
        }
        .configurationDisplayName("窝囊费")
        .description("在桌面和锁屏查看今天的窝囊费。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct WNFWidgetBundle: WidgetBundle {
    var body: some Widget {
        WNFWidget()
    }
}
