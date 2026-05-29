import AppIntents
import SwiftUI
import WidgetKit

private enum WNFWidgetShared {
    static let appGroupID = "group.com.wonangfei.app"
    static let widgetSnapshotKey = "wnf.widget.wage.snapshot.v1"
}

private struct WidgetSnapshot: Codable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var capturedAt: Date
    var earnedToday: Double
    var elapsedPaidMinutes: Int
    var workStartMinute: Int
    var workEndMinute: Int
    var statusLabel: String
    var hidesSensitiveInfo: Bool

    static let sample = WidgetSnapshot(
        schemaVersion: schemaVersion,
        capturedAt: Date(),
        earnedToday: 888.88,
        elapsedPaidMinutes: 188,
        workStartMinute: 9 * 60 + 30,
        workEndMinute: 18 * 60 + 30,
        statusLabel: "正在搬砖",
        hidesSensitiveInfo: false
    )

    init(
        schemaVersion: Int,
        capturedAt: Date,
        earnedToday: Double,
        elapsedPaidMinutes: Int,
        workStartMinute: Int,
        workEndMinute: Int,
        statusLabel: String,
        hidesSensitiveInfo: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.earnedToday = earnedToday
        self.elapsedPaidMinutes = elapsedPaidMinutes
        self.workStartMinute = workStartMinute
        self.workEndMinute = workEndMinute
        self.statusLabel = statusLabel
        self.hidesSensitiveInfo = hidesSensitiveInfo
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case capturedAt
        case earnedToday
        case elapsedPaidMinutes
        case workStartMinute
        case workEndMinute
        case statusLabel
        case hidesSensitiveInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        // A snapshot written by a newer app build must not decode into this older
        // widget's shape; throw so `loadSnapshot` falls back to `.sample` cleanly (E-9).
        guard decodedSchemaVersion <= Self.schemaVersion else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.schemaVersion],
                    debugDescription: "Unsupported widget snapshot schema version \(decodedSchemaVersion); newest supported is \(Self.schemaVersion)"
                )
            )
        }
        schemaVersion = decodedSchemaVersion
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        earnedToday = try container.decode(Double.self, forKey: .earnedToday)
        elapsedPaidMinutes = try container.decode(Int.self, forKey: .elapsedPaidMinutes)
        workStartMinute = try container.decode(Int.self, forKey: .workStartMinute)
        workEndMinute = try container.decode(Int.self, forKey: .workEndMinute)
        statusLabel = try container.decode(String.self, forKey: .statusLabel)
        hidesSensitiveInfo = try container.decodeIfPresent(Bool.self, forKey: .hidesSensitiveInfo) ?? false
    }
}

private struct WidgetPalette {
    static let bg = Color(red: 1.0, green: 0.9647, blue: 0.8980)
    static let surface = Color.white
    static let accent = Color(red: 1.0, green: 0.7843, blue: 0.2392)
    static let ink = Color.black
    static let muted = Color(red: 0.60, green: 0.58, blue: 0.54)
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
            snapshot: context.isPreview ? .sample : loadSnapshot() ?? .sample,
            isPreview: context.isPreview
        )
    }

    func timeline(for configuration: WNFWidgetConfigurationIntent, in context: Context) async -> Timeline<WNFWidgetEntry> {
        let snapshot = context.isPreview ? WidgetSnapshot.sample : loadSnapshot() ?? .sample
        let entry = WNFWidgetEntry(date: Date(), snapshot: snapshot, isPreview: context.isPreview)
        return Timeline(entries: [entry], policy: reloadPolicy(for: snapshot, now: Date()))
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: WNFWidgetShared.appGroupID)?.data(forKey: WNFWidgetShared.widgetSnapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    private func reloadPolicy(for snapshot: WidgetSnapshot, now: Date) -> TimelineReloadPolicy {
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

    var body: some View {
        content
            .containerBackground(for: .widget) {
                WidgetPalette.bg
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryRectangular:
            rectangularView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var inlineText: String {
        "窝囊费 \(moneyText)"
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日窝囊费")
                .font(.caption2.weight(.heavy))
            Text(moneyText)
                .font(.headline.weight(.black))
                .minimumScaleFactor(0.75)
            Text(entry.snapshot.statusLabel)
                .font(.caption2.weight(.semibold))
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader
            Spacer(minLength: 0)
            Text(moneyText)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(WidgetPalette.ink)
                .minimumScaleFactor(0.65)
            Text(entry.snapshot.statusLabel)
                .font(.caption.weight(.heavy))
                .foregroundStyle(WidgetPalette.muted)
        }
        .padding()
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                widgetHeader
                Text(moneyText)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetPalette.ink)
                    .minimumScaleFactor(0.62)
                Text("已忍 \(duration(entry.snapshot.elapsedPaidMinutes))")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(WidgetPalette.muted)
            }
            Spacer()
            Text("¥")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(WidgetPalette.accent)
                .frame(width: 78, height: 78)
                .background(WidgetPalette.surface, in: RoundedRectangle(cornerRadius: 24))
        }
        .padding()
    }

    private var widgetHeader: some View {
        HStack(spacing: 6) {
            Text("¥")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(WidgetPalette.accent, in: RoundedRectangle(cornerRadius: 5))
            Text("窝囊费")
                .font(.caption.weight(.black))
                .foregroundStyle(WidgetPalette.ink)
        }
    }

    private var moneyText: String {
        entry.snapshot.hidesSensitiveInfo ? "¥•••.••" : money(entry.snapshot.earnedToday)
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
