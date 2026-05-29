import AppIntents
import SwiftUI
import WidgetKit

private enum WNFWidgetShared {
    static let appGroupID = "group.com.wonangfei.app"
    static let widgetSnapshotKey = "wnf.widget.wage.snapshot.v1"
}

private struct WidgetSnapshot: Codable {
    var schemaVersion: Int
    var dateKey: String
    var capturedAt: Date
    var earnedToday: Double
    var elapsedPaidMinutes: Int
    var workStartMinute: Int
    var workEndMinute: Int
    var lunchStartMinute: Int
    var lunchEndMinute: Int
    var hasLunchBreak: Bool
    var includeOvertime: Bool
    var workdayMinutes: Int
    var earningPerSecond: Double
    var selectedWeekdays: [Int]
    var statusLabel: String
    var hidesSensitiveInfo: Bool

    static let sample = WidgetSnapshot(
        schemaVersion: 2,
        dateKey: WidgetDate.dateKey(for: Date()),
        capturedAt: Date(),
        earnedToday: 888.88,
        elapsedPaidMinutes: 188,
        workStartMinute: 9 * 60 + 30,
        workEndMinute: 18 * 60 + 30,
        lunchStartMinute: 12 * 60,
        lunchEndMinute: 13 * 60,
        hasLunchBreak: true,
        includeOvertime: false,
        workdayMinutes: 480,
        earningPerSecond: 888.88 / Double(188 * 60),
        selectedWeekdays: Array(0...4),
        statusLabel: "正在搬砖",
        hidesSensitiveInfo: false
    )

    init(
        schemaVersion: Int,
        dateKey: String,
        capturedAt: Date,
        earnedToday: Double,
        elapsedPaidMinutes: Int,
        workStartMinute: Int,
        workEndMinute: Int,
        lunchStartMinute: Int,
        lunchEndMinute: Int,
        hasLunchBreak: Bool,
        includeOvertime: Bool,
        workdayMinutes: Int,
        earningPerSecond: Double,
        selectedWeekdays: [Int],
        statusLabel: String,
        hidesSensitiveInfo: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.dateKey = dateKey
        self.capturedAt = capturedAt
        self.earnedToday = earnedToday
        self.elapsedPaidMinutes = elapsedPaidMinutes
        self.workStartMinute = workStartMinute
        self.workEndMinute = workEndMinute
        self.lunchStartMinute = lunchStartMinute
        self.lunchEndMinute = lunchEndMinute
        self.hasLunchBreak = hasLunchBreak
        self.includeOvertime = includeOvertime
        self.workdayMinutes = workdayMinutes
        self.earningPerSecond = earningPerSecond
        self.selectedWeekdays = selectedWeekdays.filter { (0...6).contains($0) }.sorted()
        self.statusLabel = statusLabel
        self.hidesSensitiveInfo = hidesSensitiveInfo
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case dateKey
        case capturedAt
        case earnedToday
        case elapsedPaidMinutes
        case workStartMinute
        case workEndMinute
        case lunchStartMinute
        case lunchEndMinute
        case hasLunchBreak
        case includeOvertime
        case workdayMinutes
        case earningPerSecond
        case selectedWeekdays
        case statusLabel
        case hidesSensitiveInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        dateKey = try container.decodeIfPresent(String.self, forKey: .dateKey) ?? WidgetDate.dateKey(for: capturedAt)
        earnedToday = try container.decode(Double.self, forKey: .earnedToday)
        elapsedPaidMinutes = try container.decode(Int.self, forKey: .elapsedPaidMinutes)
        workStartMinute = try container.decode(Int.self, forKey: .workStartMinute)
        workEndMinute = try container.decode(Int.self, forKey: .workEndMinute)
        lunchStartMinute = try container.decodeIfPresent(Int.self, forKey: .lunchStartMinute) ?? workEndMinute
        lunchEndMinute = try container.decodeIfPresent(Int.self, forKey: .lunchEndMinute) ?? workEndMinute
        hasLunchBreak = try container.decodeIfPresent(Bool.self, forKey: .hasLunchBreak) ?? false
        includeOvertime = try container.decodeIfPresent(Bool.self, forKey: .includeOvertime) ?? false
        workdayMinutes = try container.decodeIfPresent(Int.self, forKey: .workdayMinutes) ?? max(1, workEndMinute - workStartMinute)
        if let storedRate = try container.decodeIfPresent(Double.self, forKey: .earningPerSecond) {
            earningPerSecond = storedRate
        } else {
            let elapsedSeconds = max(0, elapsedPaidMinutes * 60)
            earningPerSecond = elapsedSeconds > 0 ? earnedToday / Double(elapsedSeconds) : 0
        }
        selectedWeekdays = (try container.decodeIfPresent([Int].self, forKey: .selectedWeekdays) ?? Array(0...6))
            .filter { (0...6).contains($0) }
            .sorted()
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
        let now = Date()
        let entries = timelineEntries(for: snapshot, now: now, isPreview: context.isPreview)
        return Timeline(entries: entries, policy: reloadPolicy(for: snapshot, now: now))
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: WNFWidgetShared.appGroupID)?.data(forKey: WNFWidgetShared.widgetSnapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    private func timelineEntries(for snapshot: WidgetSnapshot, now: Date, isPreview: Bool) -> [WNFWidgetEntry] {
        guard isPreview == false else {
            return [WNFWidgetEntry(date: now, snapshot: snapshot.projected(at: now), isPreview: true)]
        }

        let endDate = projectionEndDate(for: snapshot, now: now)
        var entries = [WNFWidgetEntry(date: now, snapshot: snapshot.projected(at: now), isPreview: false)]
        guard endDate > now else { return entries }

        var cursor = WidgetDate.nextMinute(after: now)
        while cursor <= endDate {
            entries.append(WNFWidgetEntry(date: cursor, snapshot: snapshot.projected(at: cursor), isPreview: false))
            guard let next = Calendar.current.date(byAdding: .minute, value: 1, to: cursor) else { break }
            cursor = next
        }
        return entries
    }

    private func projectionEndDate(for snapshot: WidgetSnapshot, now: Date) -> Date {
        guard snapshot.isSelectedWorkday(now) else { return now }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endMinute = snapshot.includeOvertime ? (24 * 60 - 1) : snapshot.workEndMinute
        return WidgetDate.date(on: startOfDay, minute: endMinute) ?? now
    }

    private func reloadPolicy(for snapshot: WidgetSnapshot, now: Date) -> TimelineReloadPolicy {
        let horizon = projectionEndDate(for: snapshot, now: now)
        let nextStart = WidgetDate.nextSelectedWorkStart(after: max(now, horizon), snapshot: snapshot)
            ?? now.addingTimeInterval(6 * 60 * 60)
        return .after(nextStart)
    }
}

private enum WidgetDate {
    static func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func weekdayIndex(for date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func secondsInDay(for date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return ((components.hour ?? 0) * 60 + (components.minute ?? 0)) * 60 + (components.second ?? 0)
    }

    static func date(on startOfDay: Date, minute: Int) -> Date? {
        Calendar.current.date(byAdding: .minute, value: max(0, min(24 * 60 - 1, minute)), to: startOfDay)
    }

    static func nextMinute(after date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let floor = calendar.date(from: components) ?? date
        return calendar.date(byAdding: .minute, value: 1, to: floor) ?? date.addingTimeInterval(60)
    }

    static func nextSelectedWorkStart(after date: Date, snapshot: WidgetSnapshot) -> Date? {
        let calendar = Calendar.current
        let selectedWeekdays = Set(snapshot.selectedWeekdays)
        guard selectedWeekdays.isEmpty == false else { return nil }

        let startOfSearchDay = calendar.startOfDay(for: date)
        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfSearchDay),
                  selectedWeekdays.contains(weekdayIndex(for: day)),
                  let candidate = self.date(on: day, minute: snapshot.workStartMinute)
            else { continue }
            if candidate > date { return candidate }
        }
        return nil
    }
}

private extension WidgetSnapshot {
    func projected(at date: Date) -> WidgetSnapshot {
        guard earningPerSecond > 0 else { return self }
        guard isSelectedWorkday(date) else {
            return copy(
                at: date,
                earnedToday: 0,
                elapsedPaidMinutes: 0,
                statusLabel: "今天不用窝囊"
            )
        }

        let elapsedSeconds = projectedElapsedPaidSeconds(at: date)
        return copy(
            at: date,
            earnedToday: earningPerSecond * Double(elapsedSeconds),
            elapsedPaidMinutes: elapsedSeconds / 60,
            statusLabel: projectedStatusLabel(at: date)
        )
    }

    func isSelectedWorkday(_ date: Date) -> Bool {
        Set(selectedWeekdays).contains(WidgetDate.weekdayIndex(for: date))
    }

    private func projectedElapsedPaidSeconds(at date: Date) -> Int {
        let nowSecond = WidgetDate.secondsInDay(for: date)
        let startSecond = workStartMinute * 60
        let endSecond = workEndMinute * 60
        guard nowSecond > startSecond else { return 0 }

        let paidThroughSecond = includeOvertime ? nowSecond : min(nowSecond, endSecond)
        let rawLunchStart = hasLunchBreak ? min(lunchStartMinute, lunchEndMinute) : workEndMinute
        let rawLunchEnd = hasLunchBreak ? max(lunchStartMinute, lunchEndMinute) : workEndMinute
        let lunchStartSecond = max(startSecond, rawLunchStart * 60)
        let lunchEndSecond = min(endSecond, rawLunchEnd * 60)
        let lunchOverlap = lunchEndSecond > lunchStartSecond
            ? max(0, min(paidThroughSecond, lunchEndSecond) - lunchStartSecond)
            : 0
        return max(0, paidThroughSecond - startSecond - lunchOverlap)
    }

    private func projectedStatusLabel(at date: Date) -> String {
        let nowMinute = WidgetDate.secondsInDay(for: date) / 60
        let rawLunchStart = hasLunchBreak ? min(lunchStartMinute, lunchEndMinute) : workEndMinute
        let rawLunchEnd = hasLunchBreak ? max(lunchStartMinute, lunchEndMinute) : workEndMinute
        let effectiveLunchStart = max(workStartMinute, rawLunchStart)
        let effectiveLunchEnd = min(workEndMinute, rawLunchEnd)
        let hasEffectiveLunch = effectiveLunchEnd > effectiveLunchStart

        if nowMinute < workStartMinute { return "尚未开工" }
        if hasEffectiveLunch == false, nowMinute < workEndMinute { return "上午搬砖中" }
        if nowMinute < effectiveLunchStart { return "上午搬砖中" }
        if nowMinute < effectiveLunchEnd { return "午休回血" }
        if nowMinute < workEndMinute { return "下午挺挺" }
        return "今日通关"
    }

    private func copy(
        at date: Date,
        earnedToday: Double,
        elapsedPaidMinutes: Int,
        statusLabel: String
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            schemaVersion: schemaVersion,
            dateKey: WidgetDate.dateKey(for: date),
            capturedAt: date,
            earnedToday: earnedToday,
            elapsedPaidMinutes: elapsedPaidMinutes,
            workStartMinute: workStartMinute,
            workEndMinute: workEndMinute,
            lunchStartMinute: lunchStartMinute,
            lunchEndMinute: lunchEndMinute,
            hasLunchBreak: hasLunchBreak,
            includeOvertime: includeOvertime,
            workdayMinutes: workdayMinutes,
            earningPerSecond: earningPerSecond,
            selectedWeekdays: selectedWeekdays,
            statusLabel: statusLabel,
            hidesSensitiveInfo: hidesSensitiveInfo
        )
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
