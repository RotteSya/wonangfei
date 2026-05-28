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

    private var isLocked: Bool {
        !entry.snapshot.isPremiumUnlocked && !entry.isPreview
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
            if isLocked { rectangularLockedView } else { rectangularUnlockedView }
        case .systemMedium:
            if isLocked { mediumLockedView } else { mediumUnlockedView }
        default:
            if isLocked { smallLockedView } else { smallUnlockedView }
        }
    }

    // MARK: Unlocked (and preview) views

    private var inlineText: String {
        if isLocked { return "窝囊费 · 王牌打工人专属" }
        if !entry.snapshot.lockScreenShowsAmount {
            return "窝囊费 \(entry.snapshot.statusLabel)"
        }
        return "窝囊费 \(money(entry.snapshot.earnedToday))"
    }

    private var rectangularUnlockedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日窝囊费")
                .font(.caption2.weight(.heavy))
            Text(lockScreenAmountText)
                .font(.headline.weight(.black))
                .minimumScaleFactor(0.75)
            Text(entry.snapshot.statusLabel)
                .font(.caption2.weight(.semibold))
        }
    }

    private var smallUnlockedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader(showPremiumBadge: entry.isPreview)
            Spacer(minLength: 0)
            Text(money(entry.snapshot.earnedToday))
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(palette.ink)
                .minimumScaleFactor(0.65)
            Text(entry.snapshot.statusLabel)
                .font(.caption.weight(.heavy))
                .foregroundStyle(palette.muted)
        }
        .padding()
    }

    private var mediumUnlockedView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                widgetHeader(showPremiumBadge: entry.isPreview)
                Text(money(entry.snapshot.earnedToday))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .minimumScaleFactor(0.62)
                Text("已忍 \(duration(entry.snapshot.elapsedPaidMinutes))")
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

    // MARK: Locked views (王牌打工人专属)

    private var rectangularLockedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.black))
                Text("王牌打工人专属")
                    .font(.caption2.weight(.heavy))
            }
            Text("窝囊费小组件")
                .font(.headline.weight(.black))
                .minimumScaleFactor(0.75)
            Text("点击解锁")
                .font(.caption2.weight(.semibold))
        }
    }

    private var smallLockedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader(showPremiumBadge: true)
            Spacer(minLength: 0)
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(palette.accent)
            Text("王牌打工人专属")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(palette.ink)
                .minimumScaleFactor(0.65)
            Text("点击解锁今日窝囊费")
                .font(.caption.weight(.heavy))
                .foregroundStyle(palette.muted)
        }
        .padding()
    }

    private var mediumLockedView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                widgetHeader(showPremiumBadge: true)
                Text("王牌打工人专属")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .minimumScaleFactor(0.62)
                Text("点击解锁桌面/锁屏小组件")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(palette.muted)
            }
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(palette.surface)
                Image(systemName: "lock.fill")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(palette.accent)
            }
            .frame(width: 78, height: 78)
        }
        .padding()
    }

    // MARK: Shared chrome

    private func widgetHeader(showPremiumBadge: Bool) -> some View {
        HStack(spacing: 6) {
            Text("¥")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 5))
            Text("窝囊费")
                .font(.caption.weight(.black))
                .foregroundStyle(palette.ink)
            if showPremiumBadge {
                Text("王牌")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(palette.accent, in: Capsule())
            }
        }
    }

    private var lockScreenAmountText: String {
        if !entry.snapshot.lockScreenShowsAmount { return "¥•••.••" }
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
