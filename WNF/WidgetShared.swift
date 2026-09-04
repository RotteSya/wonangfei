import Foundation

enum WNFShared {
    static let appGroupID = "group.com.wonangfei.app"
    static let widgetSnapshotKey = "wnf.widget.wage.snapshot.v1"
}

enum WorkStatus: CaseIterable {
    case off
    case before
    case morning
    case lunch
    case afternoon
    case done

    var label: String {
        switch self {
        case .off: "今天不用窝囊"
        case .before: "尚未开工"
        case .morning: "上午搬砖中"
        case .lunch: "午休回血"
        case .afternoon: "下午挺挺"
        case .done: "今日通关"
        }
    }
}

enum WNFWidgetDate {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    static func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func weekdayIndex(for date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func secondsInDay(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return ((components.hour ?? 0) * 60 + (components.minute ?? 0)) * 60 + (components.second ?? 0)
    }

    static func date(on startOfDay: Date, minute: Int) -> Date? {
        calendar.date(byAdding: .minute, value: max(0, min(24 * 60 - 1, minute)), to: startOfDay)
    }

    static func nextMinute(after date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let floor = calendar.date(from: components) ?? date
        return calendar.date(byAdding: .minute, value: 1, to: floor) ?? date.addingTimeInterval(60)
    }
}

struct WNFWidgetSnapshot: Codable, Equatable {
    static let schemaVersion = 3

    static var sample: WNFWidgetSnapshot {
        let now = Date()
        return WNFWidgetSnapshot(
            dateKey: WNFWidgetDate.dateKey(for: now),
            capturedAt: now,
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
            hidesSensitiveInfo: false,
            overtimeEnd: nil,
            overtimeSeconds: 0
        )
    }

    var schemaVersion: Int = Self.schemaVersion
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
    var overtimeEnd: Date?
    var overtimeSeconds: Int

    var earnedTodayText: String {
        hidesSensitiveInfo ? "¥•••.••" : String(format: "¥%.2f", earnedToday)
    }

    init(
        schemaVersion: Int = Self.schemaVersion,
        dateKey: String = WNFWidgetDate.dateKey(for: Date()),
        capturedAt: Date,
        earnedToday: Double,
        elapsedPaidMinutes: Int,
        workStartMinute: Int,
        workEndMinute: Int,
        lunchStartMinute: Int = 0,
        lunchEndMinute: Int = 0,
        hasLunchBreak: Bool = false,
        includeOvertime: Bool = false,
        workdayMinutes: Int = 1,
        earningPerSecond: Double = 0,
        selectedWeekdays: [Int] = Array(0...6),
        statusLabel: String,
        hidesSensitiveInfo: Bool = false,
        overtimeEnd: Date? = nil,
        overtimeSeconds: Int = 0
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
        self.overtimeEnd = overtimeEnd
        self.overtimeSeconds = max(0, overtimeSeconds)
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
        case overtimeEnd
        case overtimeSeconds
    }

    /// `Equatable` includes `capturedAt`, so a strict `==` between successive
    /// writes always differs even when nothing meaningful changed. This helper
    /// compares only the fields the widget actually renders — the gate used
    /// by `WNFWidgetSnapshotWriter.write` to suppress redundant disk writes
    /// + timeline reloads.
    func hasSameContent(as other: WNFWidgetSnapshot) -> Bool {
        schemaVersion == other.schemaVersion
            && dateKey == other.dateKey
            && earnedToday == other.earnedToday
            && elapsedPaidMinutes == other.elapsedPaidMinutes
            && workStartMinute == other.workStartMinute
            && workEndMinute == other.workEndMinute
            && lunchStartMinute == other.lunchStartMinute
            && lunchEndMinute == other.lunchEndMinute
            && hasLunchBreak == other.hasLunchBreak
            && includeOvertime == other.includeOvertime
            && workdayMinutes == other.workdayMinutes
            && earningPerSecond == other.earningPerSecond
            && selectedWeekdays == other.selectedWeekdays
            && statusLabel == other.statusLabel
            && hidesSensitiveInfo == other.hidesSensitiveInfo
            && overtimeEnd == other.overtimeEnd
            && overtimeSeconds == other.overtimeSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        dateKey = try container.decodeIfPresent(String.self, forKey: .dateKey) ?? WNFWidgetDate.dateKey(for: capturedAt)
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
        overtimeEnd = try container.decodeIfPresent(Date.self, forKey: .overtimeEnd)
        overtimeSeconds = try container.decodeIfPresent(Int.self, forKey: .overtimeSeconds) ?? 0
    }
}

extension WNFWidgetSnapshot {
    func projected(at date: Date) -> WNFWidgetSnapshot {
        guard earningPerSecond > 0 else { return self }
        guard isSelectedWorkday(date) else {
            return copy(
                at: date,
                earnedToday: 0,
                elapsedPaidMinutes: 0,
                statusLabel: WorkStatus.off.label
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

    func nextSelectedWorkStart(after date: Date) -> Date? {
        let calendar = WNFWidgetDate.calendar
        let selectedWeekdays = Set(selectedWeekdays)
        guard selectedWeekdays.isEmpty == false else { return nil }

        let startOfSearchDay = calendar.startOfDay(for: date)
        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfSearchDay),
                  selectedWeekdays.contains(WNFWidgetDate.weekdayIndex(for: day)),
                  let candidate = WNFWidgetDate.date(on: day, minute: workStartMinute)
            else { continue }
            if candidate > date { return candidate }
        }
        return nil
    }

    func isSelectedWorkday(_ date: Date) -> Bool {
        Set(selectedWeekdays).contains(WNFWidgetDate.weekdayIndex(for: date))
    }

    private func projectedElapsedPaidSeconds(at date: Date) -> Int {
        let nowSecond = WNFWidgetDate.secondsInDay(for: date)
        let startSecond = workStartMinute * 60
        let endSecond = workEndMinute * 60
        guard nowSecond > startSecond else { return 0 }

        // `includeOvertime` remains decodable for schema-v2 compatibility, but
        // projection only continues past the normal end when `overtimeEnd` is set.
        let capSecond: Int
        if let overtimeEnd,
           WNFWidgetDate.dateKey(for: date) == WNFWidgetDate.dateKey(for: overtimeEnd) {
            capSecond = max(endSecond, WNFWidgetDate.secondsInDay(for: overtimeEnd))
        } else {
            capSecond = endSecond
        }
        let paidThroughSecond = min(nowSecond, capSecond)
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
        let nowMinute = WNFWidgetDate.secondsInDay(for: date) / 60
        let rawLunchStart = hasLunchBreak ? min(lunchStartMinute, lunchEndMinute) : workEndMinute
        let rawLunchEnd = hasLunchBreak ? max(lunchStartMinute, lunchEndMinute) : workEndMinute
        let effectiveLunchStart = max(workStartMinute, rawLunchStart)
        let effectiveLunchEnd = min(workEndMinute, rawLunchEnd)
        let hasEffectiveLunch = effectiveLunchEnd > effectiveLunchStart

        if nowMinute < workStartMinute { return WorkStatus.before.label }
        if hasEffectiveLunch == false, nowMinute < workEndMinute { return WorkStatus.morning.label }
        if nowMinute < effectiveLunchStart { return WorkStatus.morning.label }
        if nowMinute < effectiveLunchEnd { return WorkStatus.lunch.label }
        if nowMinute < workEndMinute { return WorkStatus.afternoon.label }
        return WorkStatus.done.label
    }

    private func copy(
        at date: Date,
        earnedToday: Double,
        elapsedPaidMinutes: Int,
        statusLabel: String
    ) -> WNFWidgetSnapshot {
        WNFWidgetSnapshot(
            schemaVersion: schemaVersion,
            dateKey: WNFWidgetDate.dateKey(for: date),
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
            hidesSensitiveInfo: hidesSensitiveInfo,
            overtimeEnd: overtimeEnd,
            overtimeSeconds: overtimeSeconds
        )
    }
}

struct WNFWidgetTimelinePlan {
    var entryDates: [Date]
    var reloadDate: Date
    var projectionEndDate: Date
    var isCapped: Bool
}

enum WNFWidgetTimeline {
    static let maxFutureMinuteEntries = 240

    static func plan(for snapshot: WNFWidgetSnapshot, now: Date, isPreview: Bool) -> WNFWidgetTimelinePlan {
        guard isPreview == false else {
            return WNFWidgetTimelinePlan(
                entryDates: [now],
                reloadDate: now.addingTimeInterval(60 * 60),
                projectionEndDate: now,
                isCapped: false
            )
        }

        let projectionEndDate = projectionEndDate(for: snapshot, now: now)
        var entryDates = [now]

        if projectionEndDate > now {
            var futureEntryCount = 0
            var cursor = WNFWidgetDate.nextMinute(after: now)
            while cursor <= projectionEndDate && futureEntryCount < maxFutureMinuteEntries {
                entryDates.append(cursor)
                futureEntryCount += 1
                guard let next = WNFWidgetDate.calendar.date(byAdding: .minute, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        let lastEntryDate = entryDates.last ?? now
        let isCapped = lastEntryDate < projectionEndDate
        let reloadDate = isCapped
            ? WNFWidgetDate.nextMinute(after: lastEntryDate)
            : nextWorkdayReloadDate(for: snapshot, now: now, projectionEndDate: projectionEndDate)

        return WNFWidgetTimelinePlan(
            entryDates: entryDates,
            reloadDate: reloadDate,
            projectionEndDate: projectionEndDate,
            isCapped: isCapped
        )
    }

    static func projectionEndDate(for snapshot: WNFWidgetSnapshot, now: Date) -> Date {
        guard snapshot.isSelectedWorkday(now) else { return now }
        let startOfDay = WNFWidgetDate.calendar.startOfDay(for: now)
        let workEndDate = WNFWidgetDate.date(on: startOfDay, minute: snapshot.workEndMinute) ?? now
        if let overtimeEnd = snapshot.overtimeEnd,
           WNFWidgetDate.dateKey(for: now) == WNFWidgetDate.dateKey(for: overtimeEnd),
           overtimeEnd > workEndDate {
            return overtimeEnd
        }
        return workEndDate
    }

    private static func nextWorkdayReloadDate(
        for snapshot: WNFWidgetSnapshot,
        now: Date,
        projectionEndDate: Date
    ) -> Date {
        snapshot.nextSelectedWorkStart(after: max(now, projectionEndDate))
            ?? now.addingTimeInterval(6 * 60 * 60)
    }
}

#if canImport(ActivityKit)
import ActivityKit

/// Live Activity schema shared by the app (starts/updates) and the widget
/// extension (renders). Everything time-driven (离下班 countdown, progress
/// bar) uses `Text(timerInterval:)` / `ProgressView(timerInterval:)` so the
/// island stays alive between content updates.
struct WNFLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When this state was computed; the money figure is exact at this instant.
        var refDate: Date
        /// ¥ earned as of `refDate`.
        var earnedAtRef: Double
        /// Today's paid window, as concrete dates (for auto progress/countdown).
        var workdayStart: Date
        var workdayEnd: Date
        /// 下班了（含结算前的"待领取"状态）。
        var isDone: Bool
        /// 隐私模式：金额打码。
        var hidesAmount: Bool
        /// 加班续命中：倒计时指向加班截止时间。
        var isOvertime: Bool
        var overtimeEnd: Date?

        enum CodingKeys: String, CodingKey {
            case refDate
            case earnedAtRef
            case workdayStart
            case workdayEnd
            case isDone
            case hidesAmount
            case isOvertime
            case overtimeEnd
        }

        init(
            refDate: Date,
            earnedAtRef: Double,
            workdayStart: Date,
            workdayEnd: Date,
            isDone: Bool,
            hidesAmount: Bool,
            isOvertime: Bool = false,
            overtimeEnd: Date? = nil
        ) {
            self.refDate = refDate
            self.earnedAtRef = earnedAtRef
            self.workdayStart = workdayStart
            self.workdayEnd = workdayEnd
            self.isDone = isDone
            self.hidesAmount = hidesAmount
            self.isOvertime = isOvertime
            self.overtimeEnd = overtimeEnd
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            refDate = try container.decode(Date.self, forKey: .refDate)
            earnedAtRef = try container.decode(Double.self, forKey: .earnedAtRef)
            workdayStart = try container.decode(Date.self, forKey: .workdayStart)
            workdayEnd = try container.decode(Date.self, forKey: .workdayEnd)
            isDone = try container.decode(Bool.self, forKey: .isDone)
            hidesAmount = try container.decode(Bool.self, forKey: .hidesAmount)
            isOvertime = try container.decodeIfPresent(Bool.self, forKey: .isOvertime) ?? false
            overtimeEnd = try container.decodeIfPresent(Date.self, forKey: .overtimeEnd)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(refDate, forKey: .refDate)
            try container.encode(earnedAtRef, forKey: .earnedAtRef)
            try container.encode(workdayStart, forKey: .workdayStart)
            try container.encode(workdayEnd, forKey: .workdayEnd)
            try container.encode(isDone, forKey: .isDone)
            try container.encode(hidesAmount, forKey: .hidesAmount)
            try container.encode(isOvertime, forKey: .isOvertime)
            try container.encodeIfPresent(overtimeEnd, forKey: .overtimeEnd)
        }
    }

    /// One activity per calendar day.
    var dateKey: String
}
#endif
