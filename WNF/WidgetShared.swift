import Foundation
import WidgetKit

enum WNFShared {
    static let appGroupID = "group.com.wonangfei.app"
    static let widgetSnapshotKey = "wnf.widget.wage.snapshot.v1"
}

struct WNFWidgetSnapshot: Codable, Equatable {
    static let schemaVersion = 2

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

    var earnedTodayText: String {
        hidesSensitiveInfo ? "¥•••.••" : String(format: "¥%.2f", earnedToday)
    }

    init(
        schemaVersion: Int = Self.schemaVersion,
        dateKey: String = WageState.dateKey(for: Date()),
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        dateKey = try container.decodeIfPresent(String.self, forKey: .dateKey) ?? WageState.dateKey(for: capturedAt)
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

enum WNFWidgetSnapshotWriter {
    /// Returns `true` when a new snapshot was actually persisted. The caller
    /// uses this to decide whether to schedule a widget timeline reload —
    /// rapid privacy toggles or fg/bg swaps would otherwise re-encode the
    /// same content multiple times per second.
    @discardableResult
    static func write(
        day: WageDay,
        workStartMinute: Int,
        workEndMinute: Int,
        lunchStartMinute: Int,
        lunchEndMinute: Int,
        hasLunchBreak: Bool,
        includeOvertime: Bool,
        selectedWeekdays: Set<Int>,
        statusLabel: String,
        hidesSensitiveInfo: Bool
    ) -> Bool {
        guard let userDefaults = UserDefaults(suiteName: WNFShared.appGroupID) else { return false }
        let capturedAt = Date()
        let snapshot = WNFWidgetSnapshot(
            dateKey: WageState.dateKey(for: capturedAt),
            capturedAt: capturedAt,
            earnedToday: day.earnedToday,
            elapsedPaidMinutes: day.elapsedPaidMinutes,
            workStartMinute: workStartMinute,
            workEndMinute: workEndMinute,
            lunchStartMinute: lunchStartMinute,
            lunchEndMinute: lunchEndMinute,
            hasLunchBreak: hasLunchBreak,
            includeOvertime: includeOvertime,
            workdayMinutes: day.workdayMinutes,
            earningPerSecond: day.hourlyRate / 3600,
            selectedWeekdays: selectedWeekdays.sorted(),
            statusLabel: statusLabel,
            hidesSensitiveInfo: hidesSensitiveInfo
        )

        if let existingData = userDefaults.data(forKey: WNFShared.widgetSnapshotKey),
           let existing = try? JSONDecoder().decode(WNFWidgetSnapshot.self, from: existingData),
           existing.hasSameContent(as: snapshot) {
            return false
        }

        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        userDefaults.set(data, forKey: WNFShared.widgetSnapshotKey)
        return true
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

    func nextSelectedWorkStart(after date: Date) -> Date? {
        let calendar = DateComponents.calendar
        let selectedWeekdays = Set(selectedWeekdays)
        guard selectedWeekdays.isEmpty == false else { return nil }

        let startOfSearchDay = calendar.startOfDay(for: date)
        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfSearchDay),
                  selectedWeekdays.contains(Self.weekdayIndex(for: day)),
                  let candidate = Self.date(on: day, minute: workStartMinute)
            else { continue }
            if candidate > date { return candidate }
        }
        return nil
    }

    private func isSelectedWorkday(_ date: Date) -> Bool {
        Set(selectedWeekdays).contains(Self.weekdayIndex(for: date))
    }

    private func projectedElapsedPaidSeconds(at date: Date) -> Int {
        let nowSecond = Self.secondsInDay(for: date)
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
        let nowMinute = Self.secondsInDay(for: date) / 60
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
    ) -> WNFWidgetSnapshot {
        WNFWidgetSnapshot(
            schemaVersion: schemaVersion,
            dateKey: WageState.dateKey(for: date),
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

    private static func secondsInDay(for date: Date) -> Int {
        let components = DateComponents.calendar.dateComponents([.hour, .minute, .second], from: date)
        return ((components.hour ?? 0) * 60 + (components.minute ?? 0)) * 60 + (components.second ?? 0)
    }

    private static func weekdayIndex(for date: Date) -> Int {
        let weekday = DateComponents.calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private static func date(on startOfDay: Date, minute: Int) -> Date? {
        DateComponents.calendar.date(byAdding: .minute, value: max(0, min(24 * 60 - 1, minute)), to: startOfDay)
    }
}

@MainActor
enum WNFWidgetReloader {
    private static var reloadTask: Task<Void, Never>?

    static func scheduleReload(after delay: TimeInterval = 0.8) {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            let nanoseconds = UInt64((delay * 1_000_000_000).rounded())
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
