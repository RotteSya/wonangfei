import SwiftUI
import WidgetKit

struct WNFWidgetEntry: TimelineEntry {
    let date: Date
    let settings: WageSettings
}

struct WNFWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WNFWidgetEntry {
        WNFWidgetEntry(date: Date(), settings: .default)
    }

    func getSnapshot(in context: Context, completion: @escaping (WNFWidgetEntry) -> Void) {
        completion(WNFWidgetEntry(date: Date(), settings: loadSettings()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WNFWidgetEntry>) -> Void) {
        let now = Date()
        let settings = loadSettings()
        let day = WageCalculator.compute(settings: settings, now: now)
        let nextRefresh = refreshDate(for: day, from: now)
        completion(Timeline(entries: [WNFWidgetEntry(date: now, settings: settings)], policy: .after(nextRefresh)))
    }

    private func loadSettings() -> WageSettings {
        WNFSharedStore.loadSettings(from: WNFSharedStore.widgetDefaults, key: WNFSharedStore.widgetSettingsKey) ?? .default
    }

    private func refreshDate(for day: WageDay, from now: Date) -> Date {
        switch day.status {
        case .morning, .lunch, .afternoon, .overtime:
            now.addingTimeInterval(60)
        case .before:
            min(day.nextWorkStartDate ?? now.addingTimeInterval(30 * 60), now.addingTimeInterval(30 * 60))
        case .afterWork, .lateNight, .dayOff:
            now.addingTimeInterval(30 * 60)
        }
    }
}

struct WNFWidget: Widget {
    let kind = "WNFWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WNFWidgetProvider()) { entry in
            WNFWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("窝囊费")
        .description("一眼看今天到账、加班多挣和明日开工。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct WNFWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WNFWidgetEntry

    private var day: WageDay {
        WageCalculator.compute(settings: entry.settings, now: entry.date)
    }

    private var display: WageDisplayModel {
        WageDisplayModel(day: day, settings: entry.settings, now: entry.date)
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(day: day, display: display, privacy: entry.settings.privacyMode)
            case .systemMedium:
                MediumWidgetView(day: day, display: display, privacy: entry.settings.privacyMode, date: entry.date)
            default:
                LargeWidgetView(day: day, display: display, privacy: entry.settings.privacyMode)
            }
        }
        .containerBackground(WNFWidgetTheme.background, for: .widget)
    }
}

private struct SmallWidgetView: View {
    let day: WageDay
    let display: WageDisplayModel
    let privacy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetStatusPill(text: compactStatus)
            Spacer(minLength: 0)
            Text(compactHeadline)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(WNFWidgetTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
            Text(compactAmount)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(WNFWidgetTheme.yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(4)
    }

    private var compactStatus: String {
        switch day.status {
        case .overtime: "加班中"
        case .dayOff: "休息"
        case .afterWork, .lateNight: "收工了"
        default: display.statusLabel
        }
    }

    private var compactHeadline: String {
        switch day.status {
        case .overtime: "加班多挣"
        case .dayOff: "今天不窝囊"
        case .afterWork, .lateNight: "今天到账"
        default: "钱正在涨"
        }
    }

    private var compactAmount: String {
        switch day.status {
        case .overtime:
            WNFFormat.signedMoneyDecimal(day.overtimeEarnedToday, privacy: privacy)
        case .dayOff:
            "休息"
        default:
            WNFFormat.money(day.totalEarnedToday, privacy: privacy)
        }
    }
}

private struct MediumWidgetView: View {
    let day: WageDay
    let display: WageDisplayModel
    let privacy: Bool
    let date: Date

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetStatusPill(text: display.statusLabel)
                Text(display.headline.replacingOccurrences(of: " ", with: ""))
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(WNFWidgetTheme.muted)
                Text(primaryAmount)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(WNFWidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 7) {
                WidgetLine(title: day.status == .overtime ? "今日总计" : "已忍时长", value: day.status == .overtime ? WNFFormat.moneyDecimal(day.totalEarnedToday, privacy: privacy) : WNFFormat.duration(day.paidWorkMinutes))
                WidgetLine(title: day.status == .dayOff ? "下次开工" : "明日开工", value: nextHint)
            }
            .frame(width: 116, alignment: .leading)
        }
        .padding(6)
    }

    private var primaryAmount: String {
        day.status == .overtime ? WNFFormat.signedMoneyDecimal(day.overtimeEarnedToday, privacy: privacy) : WNFFormat.moneyDecimal(day.totalEarnedToday, privacy: privacy)
    }

    private var nextHint: String {
        WNFFormat.startHint(for: day.nextWorkStartDate, from: date)
    }
}

private struct LargeWidgetView: View {
    let day: WageDay
    let display: WageDisplayModel
    let privacy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetStatusPill(text: display.statusLabel)
                    Text(display.headline.replacingOccurrences(of: " ", with: ""))
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(WNFWidgetTheme.muted)
                    Text(primaryAmount)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(WNFWidgetTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer()

                Image(display.mascotAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(display.summaryRows.prefix(4)) { row in
                    WidgetLine(title: row.title, value: row.value)
                }
            }

            Text(day.status == .dayOff ? "休息日也要认真回血。" : "今日结算卡已准备好，之后可以做成日报分享图。")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WNFWidgetTheme.muted)
                .lineLimit(2)
        }
        .padding(6)
    }

    private var primaryAmount: String {
        day.status == .overtime ? WNFFormat.signedMoneyDecimal(day.overtimeEarnedToday, privacy: privacy) : WNFFormat.moneyDecimal(day.totalEarnedToday, privacy: privacy)
    }
}

private struct WidgetStatusPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(WNFWidgetTheme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.72), in: Capsule())
    }
}

private struct WidgetLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(WNFWidgetTheme.muted)
            Text(value)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(WNFWidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum WNFWidgetTheme {
    static let background = Color(red: 1.0, green: 0.965, blue: 0.9)
    static let ink = Color(red: 0.05, green: 0.05, blue: 0.05)
    static let muted = Color(red: 0.45, green: 0.42, blue: 0.35)
    static let yellow = Color(red: 1.0, green: 0.78, blue: 0.24)
}
