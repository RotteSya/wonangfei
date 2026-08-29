import Foundation
import Testing
@testable import WNF

struct WageCalculatorTests {
    @Test("上班前金额为 0")
    func beforeWorkEarnsNothing() {
        let day = sampleDay(now: DateComponents(hour: 8, minute: 30), includeOvertime: false)

        #expect(day.earnedToday == 0)
        #expect(day.elapsedPaidSeconds == 0)
    }

    @Test("午休不计薪")
    func lunchBreakIsNotPaid() {
        let lunchStart = sampleDay(now: DateComponents(hour: 12, minute: 0), includeOvertime: false)
        let duringLunch = sampleDay(now: DateComponents(hour: 12, minute: 30), includeOvertime: false)

        #expect(abs(duringLunch.earnedToday - lunchStart.earnedToday) < 0.001)
        #expect(duringLunch.elapsedPaidSeconds == lunchStart.elapsedPaidSeconds)
    }

    @Test("下班后不计加班时，金额封顶")
    func afterWorkWithoutOvertimeCapsEarnings() {
        let atWorkEnd = sampleDay(now: DateComponents(hour: 18, minute: 30), includeOvertime: false)
        let afterWork = sampleDay(now: DateComponents(hour: 20, minute: 0), includeOvertime: false)

        #expect(abs(afterWork.earnedToday - atWorkEnd.earnedToday) < 0.001)
        #expect(abs(afterWork.earnedToday - afterWork.targetToday) < 0.001)
        #expect(afterWork.progress == 1)
    }

    @Test("下班后计加班时，金额继续增加")
    func afterWorkWithOvertimeKeepsEarning() {
        let atWorkEnd = sampleDay(now: DateComponents(hour: 18, minute: 30), includeOvertime: true)
        let afterWork = sampleDay(now: DateComponents(hour: 20, minute: 0), includeOvertime: true)

        #expect(afterWork.earnedToday > atWorkEnd.earnedToday)
        #expect(afterWork.earnedToday > afterWork.targetToday)
        #expect(afterWork.progress == 1)
    }

    @Test("下班早于上班时返回零值结果")
    func invalidWorkRangeReturnsZeroDay() {
        let day = WageCalculator.compute(
            monthlySalary: 22_000,
            workdaysPerMonth: 22,
            workStart: .minuteInDay(18 * 60 + 30),
            workEnd: .minuteInDay(9 * 60 + 30),
            lunchStart: .minuteInDay(12 * 60),
            lunchEnd: .minuteInDay(13 * 60),
            hasLunchBreak: true,
            includeOvertime: true,
            now: DateComponents(hour: 18, minute: 31)
        )

        #expect(day.workdayMinutes == 0)
        #expect(day.hourlyRate == 0)
        #expect(day.elapsedPaidSeconds == 0)
        #expect(day.earnedToday == 0)
        #expect(day.targetToday == 0)
        #expect(day.progress == 0)
    }

    @Test("午休早于上班时不扣减计薪时间")
    func lunchBeforeWorkDoesNotReducePaidTime() {
        let day = WageCalculator.compute(
            monthlySalary: 22_000,
            workdaysPerMonth: 22,
            workStart: .minuteInDay(9 * 60 + 30),
            workEnd: .minuteInDay(18 * 60 + 30),
            lunchStart: .minuteInDay(8 * 60),
            lunchEnd: .minuteInDay(9 * 60),
            hasLunchBreak: true,
            includeOvertime: false,
            now: DateComponents(hour: 10, minute: 0)
        )

        #expect(day.workdayMinutes == 9 * 60)
        #expect(day.elapsedPaidSeconds == 30 * 60)
    }

    @Test("午休晚于下班时不扣减计薪时间")
    func lunchAfterWorkDoesNotReducePaidTime() {
        let day = WageCalculator.compute(
            monthlySalary: 22_000,
            workdaysPerMonth: 22,
            workStart: .minuteInDay(9 * 60 + 30),
            workEnd: .minuteInDay(18 * 60 + 30),
            lunchStart: .minuteInDay(19 * 60),
            lunchEnd: .minuteInDay(20 * 60),
            hasLunchBreak: true,
            includeOvertime: false,
            now: DateComponents(hour: 18, minute: 30)
        )

        #expect(day.workdayMinutes == 9 * 60)
        #expect(day.elapsedPaidSeconds == 9 * 60 * 60)
    }

    @Test("午休部分重叠上班时只扣重叠部分")
    func partialLunchOverlapOnlySubtractsOverlap() {
        let day = WageCalculator.compute(
            monthlySalary: 22_000,
            workdaysPerMonth: 22,
            workStart: .minuteInDay(9 * 60 + 30),
            workEnd: .minuteInDay(18 * 60 + 30),
            lunchStart: .minuteInDay(9 * 60),
            lunchEnd: .minuteInDay(10 * 60),
            hasLunchBreak: true,
            includeOvertime: false,
            now: DateComponents(hour: 10, minute: 30)
        )

        #expect(day.workdayMinutes == 8 * 60 + 30)
        #expect(day.elapsedPaidSeconds == 30 * 60)
    }

    private func sampleDay(now: DateComponents, includeOvertime: Bool) -> WageDay {
        WageCalculator.compute(
            monthlySalary: 22_000,
            workdaysPerMonth: 22,
            workStart: .minuteInDay(9 * 60 + 30),
            workEnd: .minuteInDay(18 * 60 + 30),
            lunchStart: .minuteInDay(12 * 60),
            lunchEnd: .minuteInDay(13 * 60),
            hasLunchBreak: true,
            includeOvertime: includeOvertime,
            now: now
        )
    }
}

@MainActor
struct WageStateBackfillTests {
    @Test("跨日回填沿用上次观察时的薪资设置")
    func backfilledRecordsUseLastObservedSettingsSnapshot() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }

        let calendar = DateComponents.calendar
        let todayStart = calendar.startOfDay(for: Date())
        let lastObservedDate = try #require(calendar.date(byAdding: .day, value: -3, to: todayStart))
        let lastObservedSnapshot = LastObservedSnapshot(
            dateKey: WageState.dateKey(for: lastObservedDate),
            settings: WageCalculationSettingsSnapshot(
                monthlySalary: 12_000,
                workdaysPerMonth: 20,
                workStartMinute: 9 * 60,
                workEndMinute: 17 * 60,
                lunchStartMinute: 12 * 60,
                lunchEndMinute: 13 * 60,
                hasLunchBreak: true,
                includeOvertime: false,
                selectedWeekdays: Set(0...6)
            )
        )

        defaults.set(try JSONEncoder().encode(lastObservedSnapshot), forKey: StorageKey.lastObservedSnapshot)
        defaults.set(lastObservedSnapshot.dateKey, forKey: StorageKey.lastObservedDateKey)
        defaults.set(20_000, forKey: StorageKey.monthlySalary)
        defaults.set(10, forKey: StorageKey.workdaysPerMonth)
        defaults.set(Array(0...6), forKey: StorageKey.selectedWeekdays)

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        #expect(state.monthlySalary == 20_000)
        #expect(state.workdaysPerMonth == 10)

        for dayOffset in -3 ... -1 {
            let date = try #require(calendar.date(byAdding: .day, value: dayOffset, to: todayStart))
            let record = try #require(state.dailyRecords[WageState.dateKey(for: date)])

            #expect(record.monthlySalary == 12_000)
            #expect(record.workdaysPerMonth == 20)
            #expect(abs(record.targetToday - 600) < 0.001)
        }

        let observedRecord = try #require(state.dailyRecords[lastObservedSnapshot.dateKey])
        let backfilledDate = try #require(calendar.date(byAdding: .day, value: -2, to: todayStart))
        let backfilledRecord = try #require(state.dailyRecords[WageState.dateKey(for: backfilledDate)])

        #expect(observedRecord.source == .observed)
        #expect(backfilledRecord.source == .backfilled)
    }
}

@MainActor
struct WageStateSettlementTests {
    @Test("liveDay 在非选中工作日归零但 calculation 保留原始计薪")
    func liveDayIsZeroOnUnselectedWeekday() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }

        let now = try #require(dateToday(hour: 10, minute: 30))
        let todayWeekday = weekdayIndex(for: now)
        defaults.set(Array(Set(0...6).subtracting([todayWeekday])), forKey: StorageKey.selectedWeekdays)
        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        let rawDay = state.calculation(at: now)
        let liveDay = state.liveDay(at: now)

        #expect(rawDay.earnedToday > 0)
        #expect(liveDay.earnedToday == 0)
        #expect(liveDay.elapsedPaidSeconds == 0)
        #expect(liveDay.status == .off)
    }

    @Test("selectedWeekdays 变化会立即影响同一秒 liveDay")
    func selectedWeekdayChangeInvalidatesLiveDay() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }

        let now = try #require(dateToday(hour: 10, minute: 30))
        let todayWeekday = weekdayIndex(for: now)
        defaults.set(Array(0...6), forKey: StorageKey.selectedWeekdays)
        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        let paidDay = state.liveDay(at: now)
        state.selectedWeekdays = Set(0...6).subtracting([todayWeekday])
        let offDay = state.liveDay(at: now)

        #expect(paidDay.earnedToday > 0)
        #expect(offDay.earnedToday == 0)
        #expect(offDay.status == .off)
    }

    @Test("markTodaySettled() 后 isTodaySettled == true")
    func markTodaySettledMarksCurrentDay() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        state.markTodaySettled()

        #expect(state.isTodaySettled)
    }

    @Test("跨日后 isTodaySettled == false")
    func nextDayClearsTodaySettledPresentation() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        state.markTodaySettled()
        let tomorrow = try #require(
            DateComponents.calendar.date(byAdding: .day, value: 1, to: state.currentDayStart)
        )
        state.refreshCalendarDayIfNeeded(now: tomorrow)

        #expect(state.isTodaySettled == false)
    }

    @Test("初始化不自动标记已结算")
    func initializationDoesNotAutoMarkSettled() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        defaults.set(0, forKey: StorageKey.workEndMinute)
        defaults.set([weekdayIndex(for: Date())], forKey: StorageKey.selectedWeekdays)

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        #expect(state.isTodaySettled == false)
    }
}

struct RecordsAggregationTests {
    @Test("非选中工作日今日金额为 0")
    func unselectedWeekdayLiveRecordIsZero() throws {
        let now = try #require(dateOnFixedDay(hour: 10, minute: 30))
        let todayWeekday = weekdayIndex(for: now)
        let unselectedWeekdays = Set(0...6).subtracting([todayWeekday])
        let input = aggregationInput(currentDate: now, selectedWeekdays: unselectedWeekdays)

        let snapshot = RecordAggregator.make(input: input, now: now)
        let todayBar = try #require(snapshot.weekBars.first { $0.isToday })

        #expect(snapshot.todayEarned == 0)
        #expect(todayBar.amount == 0)
        #expect(snapshot.currentMonthSummary.amount == 0)
    }

    @Test("今日 live record 会计入本周/本月")
    func liveTodayRecordCountsInCurrentPeriods() throws {
        let now = try #require(dateOnFixedDay(hour: 10, minute: 30))
        let input = aggregationInput(currentDate: now, selectedWeekdays: [weekdayIndex(for: now)])

        let snapshot = RecordAggregator.make(input: input, now: now)
        let todayBar = try #require(snapshot.weekBars.first { $0.isToday })

        #expect(snapshot.todayEarned > 0)
        #expect(todayBar.amount == snapshot.todayEarned)
        #expect(snapshot.currentMonthSummary.amount == snapshot.todayEarned)
    }

    @Test("年聚合包含折叠月汇总并用 live today 替换今日已存快照")
    func yearlyAggregationIncludesMonthlySummariesAndDoesNotDoubleCountToday() throws {
        let now = try #require(dateOnFixedDay(hour: 10, minute: 30))
        let monthStart = DateComponents.calendar.date(from: DateComponents(
            year: DateComponents.calendar.component(.year, from: now),
            month: 3,
            day: 1
        ))
        let foldedMonth = try #require(monthStart)
        let todayRecord = sampleRecord(date: now, amount: 10, elapsedPaidSeconds: 600)
        var input = aggregationInput(currentDate: now, selectedWeekdays: [weekdayIndex(for: now)])
        input.dailyRecords = [todayRecord.dateKey: todayRecord]
        input.monthlyRecordSummaries = [
            monthKey(for: foldedMonth): MonthlyRecordSummary(
                monthKey: monthKey(for: foldedMonth),
                amount: 1234,
                recordedDays: 12,
                elapsedPaidSeconds: 42_000,
                updatedAt: now
            )
        ]

        let snapshot = RecordAggregator.make(input: input, now: now)
        let marchBar = try #require(snapshot.yearBars.first { $0.key == "3" })
        let todayWeekBar = try #require(snapshot.weekBars.first { $0.isToday })

        #expect(marchBar.amount == 1234)
        #expect(marchBar.recordedDays == 12)
        #expect(snapshot.todayEarned > todayRecord.earnedToday)
        #expect(todayWeekBar.amount == snapshot.todayEarned)
    }
}

@MainActor
struct DailyRecordSQLiteStoreTests {
    @Test("旧 UserDefaults envelope 会迁移到 SQLite 并清理大 payload")
    func migratesLegacyUserDefaultsPayload() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }

        let now = Date()
        let yesterday = try #require(DateComponents.calendar.date(byAdding: .day, value: -1, to: now))
        let records = [
            WageState.dateKey(for: yesterday): sampleRecord(date: yesterday, amount: 88, elapsedPaidSeconds: 3600),
            WageState.dateKey(for: now): sampleRecord(date: now, amount: 99, elapsedPaidSeconds: 4200)
        ]
        defaults.set(try JSONEncoder().encode(DailyRecordStorageEnvelope(records: records)), forKey: StorageKey.dailyRecords)

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        #expect(state.dailyRecords[WageState.dateKey(for: yesterday)]?.earnedToday == 88)
        #expect(defaults.data(forKey: StorageKey.dailyRecords) == nil)
        #expect(defaults.bool(forKey: StorageKey.dailyRecordsSQLiteMigrationCompleted))
        let backupPath = try #require(defaults.string(forKey: "\(StorageKey.dailyRecordsSQLiteMigrationCompleted).backupPath"))
        #expect(FileManager.default.fileExists(atPath: backupPath))
    }

    @Test("超过 400 天的每日记录会折叠成月汇总")
    func foldsRecordsOlderThanRetentionWindow() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }

        let store = DailyRecordSQLiteStore(userDefaults: defaults)
        let now = Date()
        let currentYear = DateComponents.calendar.component(.year, from: now)
        let oldA = try #require(DateComponents.calendar.date(from: DateComponents(year: currentYear - 2, month: 1, day: 10)))
        let oldB = try #require(DateComponents.calendar.date(from: DateComponents(year: currentYear - 2, month: 1, day: 11)))
        let recent = try #require(DateComponents.calendar.date(byAdding: .day, value: -1, to: now))

        let result = store.upsert([
            sampleRecord(date: oldA, amount: 11, elapsedPaidSeconds: 110),
            sampleRecord(date: oldB, amount: 22, elapsedPaidSeconds: 220),
            sampleRecord(date: recent, amount: 33, elapsedPaidSeconds: 330)
        ], now: now)

        let oldMonthSummary = try #require(result.monthlySummaries[monthKey(for: oldA)])
        #expect(result.records[WageState.dateKey(for: oldA)] == nil)
        #expect(result.records[WageState.dateKey(for: oldB)] == nil)
        #expect(result.records[WageState.dateKey(for: recent)]?.earnedToday == 33)
        #expect(oldMonthSummary.amount == 33)
        #expect(oldMonthSummary.recordedDays == 2)
        #expect(oldMonthSummary.elapsedPaidSeconds == 330)
    }
}

struct DailySettlementAggregationTests {
    @Test("累计窝囊费包含月汇总且今日 live 不重复计入")
    func cumulativeEarnedIncludesMonthlySummariesWithoutDoubleCountingToday() throws {
        let today = try #require(dateOnFixedDay(hour: 18, minute: 30))
        let yesterday = try #require(DateComponents.calendar.date(byAdding: .day, value: -1, to: today))
        let day = WageDay(
            startMinute: 9 * 60,
            endMinute: 18 * 60,
            lunchStartMinute: 12 * 60,
            lunchEndMinute: 13 * 60,
            workdayMinutes: 480,
            hourlyRate: 100,
            elapsedPaidMinutes: 480,
            elapsedPaidSeconds: 480 * 60,
            earnedToday: 100,
            targetToday: 100,
            status: .done,
            wallToEndMinutes: 0
        )
        let settlement = DailySettlement.derive(
            from: day,
            dailyRecords: [
                WageState.dateKey(for: yesterday): sampleRecord(date: yesterday, amount: 20, elapsedPaidSeconds: 1200),
                WageState.dateKey(for: today): sampleRecord(date: today, amount: 50, elapsedPaidSeconds: 3000)
            ],
            monthlyRecordSummaries: [
                "2025-01": MonthlyRecordSummary(
                    monthKey: "2025-01",
                    amount: 1000,
                    recordedDays: 20,
                    elapsedPaidSeconds: 80_000,
                    updatedAt: today
                )
            ],
            at: today
        )

        #expect(settlement.cumulativeEarned == 1120)
    }
}

struct WidgetProjectionTests {
    @Test("Widget snapshot 可以按分钟推导增长金额")
    func widgetSnapshotProjectsFutureMinute() throws {
        let now = try #require(dateOnFixedDay(hour: 10, minute: 0))
        let snapshot = widgetSnapshot(hidesSensitiveInfo: false, capturedAt: now, earningPerSecond: 1)

        let projected = snapshot.projected(at: now)

        #expect(projected.earnedToday == 30 * 60)
        #expect(projected.elapsedPaidMinutes == 30)
        #expect(projected.statusLabel == "上午搬砖中")
    }

    @Test("Widget reload 目标会跳到下一个选中工作日起点")
    func widgetSnapshotFindsNextSelectedWorkStart() throws {
        let now = try #require(dateOnFixedDay(hour: 19, minute: 0))
        let snapshot = widgetSnapshot(hidesSensitiveInfo: false, capturedAt: now, earningPerSecond: 1)

        let nextStart = try #require(snapshot.nextSelectedWorkStart(after: now))

        #expect(nextStart > now)
        #expect(DateComponents.calendar.component(.hour, from: nextStart) == 9)
        #expect(DateComponents.calendar.component(.minute, from: nextStart) == 30)
    }

    @Test("Widget timeline 会封顶较长的加班分钟 entries")
    func widgetTimelineCapsLongOvertimeWindow() throws {
        let now = try #require(dateOnFixedDay(hour: 10, minute: 0))
        let snapshot = widgetSnapshot(
            hidesSensitiveInfo: false,
            capturedAt: now,
            earningPerSecond: 1,
            includeOvertime: true
        )

        let plan = WNFWidgetTimeline.plan(for: snapshot, now: now, isPreview: false)

        #expect(plan.isCapped)
        #expect(plan.entryDates.count == WNFWidgetTimeline.maxFutureMinuteEntries + 1)
        #expect(plan.entryDates.count <= 241)
    }

    @Test("Widget timeline 封顶后会在窗口末尾附近 reload")
    func cappedWidgetTimelineReloadsNearCapWindowEnd() throws {
        let now = try #require(dateOnFixedDay(hour: 10, minute: 0))
        let snapshot = widgetSnapshot(
            hidesSensitiveInfo: false,
            capturedAt: now,
            earningPerSecond: 1,
            includeOvertime: true
        )

        let plan = WNFWidgetTimeline.plan(for: snapshot, now: now, isPreview: false)
        let lastEntryDate = try #require(plan.entryDates.last)

        #expect(plan.isCapped)
        #expect(plan.reloadDate > lastEntryDate)
        #expect(plan.reloadDate <= lastEntryDate.addingTimeInterval(61))
        #expect(WNFWidgetDate.dateKey(for: plan.reloadDate) == WNFWidgetDate.dateKey(for: now))
    }

    @Test("Widget timeline 未封顶时仍在下个选中工作日起点 reload")
    func uncappedWidgetTimelineReloadsAtNextSelectedWorkStart() throws {
        let now = try #require(dateOnFixedDay(hour: 17, minute: 0))
        let snapshot = widgetSnapshot(
            hidesSensitiveInfo: false,
            capturedAt: now,
            earningPerSecond: 1,
            includeOvertime: false
        )

        let plan = WNFWidgetTimeline.plan(for: snapshot, now: now, isPreview: false)
        let nextStart = try #require(snapshot.nextSelectedWorkStart(after: max(now, plan.projectionEndDate)))

        #expect(plan.isCapped == false)
        #expect(plan.reloadDate == nextStart)
        #expect(plan.reloadDate > now)
        #expect(DateComponents.calendar.component(.hour, from: plan.reloadDate) == 9)
        #expect(DateComponents.calendar.component(.minute, from: plan.reloadDate) == 30)
    }
}

struct WidgetSnapshotTests {
    @Test("privacy on 时 Widget 显示 ¥•••.••")
    func privacyOnDisplaysMaskedMoney() {
        let snapshot = widgetSnapshot(hidesSensitiveInfo: true)

        #expect(snapshot.earnedTodayText == "¥•••.••")
    }

    @Test("privacy off 时显示真实金额")
    func privacyOffDisplaysActualMoney() {
        let snapshot = widgetSnapshot(hidesSensitiveInfo: false)

        #expect(snapshot.earnedTodayText == "¥888.88")
    }
}

private enum TestSetupError: Error {
    case userDefaultsUnavailable
}

private func isolatedDefaults() throws -> (defaults: UserDefaults, suiteName: String, cleanup: () -> Void) {
    let suiteName = "WNFTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestSetupError.userDefaultsUnavailable
    }
    defaults.removePersistentDomain(forName: suiteName)

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WNFTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let databaseURL = root.appendingPathComponent("DailyRecords.sqlite")
    defaults.set(databaseURL.path, forKey: StorageKey.dailyRecordsSQLitePathOverride)

    let cleanup = {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
    return (defaults, suiteName, cleanup)
}

private func aggregationInput(currentDate: Date, selectedWeekdays: Set<Int>) -> RecordAggregationInput {
    RecordAggregationInput(
        currentDateKey: WageState.dateKey(for: currentDate),
        recordsRevision: 0,
        dailyRecords: [:],
        monthlySalary: 22_000,
        workdaysPerMonth: 22,
        workStartMinute: 9 * 60 + 30,
        workEndMinute: 18 * 60 + 30,
        lunchStartMinute: 12 * 60,
        lunchEndMinute: 13 * 60,
        hasLunchBreak: true,
        includeOvertime: false,
        selectedWeekdays: selectedWeekdays
    )
}

private func widgetSnapshot(
    hidesSensitiveInfo: Bool,
    capturedAt: Date = Date(),
    earningPerSecond: Double = 0,
    includeOvertime: Bool = false
) -> WNFWidgetSnapshot {
    WNFWidgetSnapshot(
        dateKey: WNFWidgetDate.dateKey(for: capturedAt),
        capturedAt: capturedAt,
        earnedToday: 888.88,
        elapsedPaidMinutes: 188,
        workStartMinute: 9 * 60 + 30,
        workEndMinute: 18 * 60 + 30,
        lunchStartMinute: 12 * 60,
        lunchEndMinute: 13 * 60,
        hasLunchBreak: true,
        includeOvertime: includeOvertime,
        workdayMinutes: 480,
        earningPerSecond: earningPerSecond,
        selectedWeekdays: Array(0...6),
        statusLabel: "正在搬砖",
        hidesSensitiveInfo: hidesSensitiveInfo
    )
}

private func sampleRecord(date: Date, amount: Double, elapsedPaidSeconds: Int) -> DailyWageRecord {
    DailyWageRecord(
        dateKey: WageState.dateKey(for: date),
        earnedToday: amount,
        targetToday: amount,
        elapsedPaidSeconds: elapsedPaidSeconds,
        workdayMinutes: 480,
        hourlyRate: 100,
        monthlySalary: 20_000,
        workdaysPerMonth: 22,
        capturedAt: date,
        source: .observed
    )
}

private func dateToday(hour: Int, minute: Int) -> Date? {
    var components = DateComponents.calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = hour
    components.minute = minute
    components.second = 0
    return DateComponents.calendar.date(from: components)
}

/// Monday 2026-08-17 in `DateComponents.calendar` — wall-clock-independent for pure calculation tests.
private func dateOnFixedDay(hour: Int, minute: Int) -> Date? {
    DateComponents.calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 17,
        hour: hour,
        minute: minute,
        second: 0
    ))
}

private func weekdayIndex(for date: Date) -> Int {
    let weekday = DateComponents.calendar.component(.weekday, from: date)
    return (weekday + 5) % 7
}

private func monthKey(for date: Date) -> String {
    let components = DateComponents.calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
}
