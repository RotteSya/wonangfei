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

struct WageStateBackfillTests {
    @Test("跨日回填沿用上次观察时的薪资设置")
    func backfilledRecordsUseLastObservedSettingsSnapshot() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

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

struct WageStateSettlementTests {
    @Test("markTodaySettled() 后 isTodaySettled == true")
    func markTodaySettledMarksCurrentDay() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        state.markTodaySettled()

        #expect(state.isTodaySettled)
    }

    @Test("跨日后 isTodaySettled == false")
    func nextDayClearsTodaySettledPresentation() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
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
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
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
        let now = try #require(dateToday(hour: 10, minute: 30))
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
        let now = try #require(dateToday(hour: 10, minute: 30))
        let input = aggregationInput(currentDate: now, selectedWeekdays: [weekdayIndex(for: now)])

        let snapshot = RecordAggregator.make(input: input, now: now)
        let todayBar = try #require(snapshot.weekBars.first { $0.isToday })

        #expect(snapshot.todayEarned > 0)
        #expect(todayBar.amount == snapshot.todayEarned)
        #expect(snapshot.currentMonthSummary.amount == snapshot.todayEarned)
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

private func isolatedDefaults() throws -> (UserDefaults, String) {
    let suiteName = "WNFTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestSetupError.userDefaultsUnavailable
    }
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
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

private func widgetSnapshot(hidesSensitiveInfo: Bool) -> WNFWidgetSnapshot {
    WNFWidgetSnapshot(
        capturedAt: Date(),
        earnedToday: 888.88,
        elapsedPaidMinutes: 188,
        workStartMinute: 9 * 60 + 30,
        workEndMinute: 18 * 60 + 30,
        statusLabel: "正在搬砖",
        hidesSensitiveInfo: hidesSensitiveInfo
    )
}

private func dateToday(hour: Int, minute: Int) -> Date? {
    var components = DateComponents.calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = hour
    components.minute = minute
    components.second = 0
    return DateComponents.calendar.date(from: components)
}

private func weekdayIndex(for date: Date) -> Int {
    let weekday = DateComponents.calendar.component(.weekday, from: date)
    return (weekday + 5) % 7
}
