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

struct WageCalculatorEdgeCaseTests {
    @Test("午休落在工作时段之外时不扣减计薪时长")
    func lunchOutsideWorkHoursIsNotDeducted() {
        // 上班 9:30–18:30（540 分钟），午休 20:00–21:00 完全在下班之后。
        let outsideLunch = edgeDay(
            now: DateComponents(hour: 18, minute: 30),
            hasLunchBreak: true,
            lunchStart: DateComponents(hour: 20, minute: 0),
            lunchEnd: DateComponents(hour: 21, minute: 0)
        )
        let noLunch = edgeDay(
            now: DateComponents(hour: 18, minute: 30),
            hasLunchBreak: false,
            lunchStart: DateComponents(hour: 20, minute: 0),
            lunchEnd: DateComponents(hour: 21, minute: 0)
        )

        #expect(outsideLunch.workdayMinutes == 9 * 60)
        #expect(outsideLunch.workdayMinutes == noLunch.workdayMinutes)
        #expect(abs(outsideLunch.hourlyRate - noLunch.hourlyRate) < 0.0001)
        #expect(abs(outsideLunch.earnedToday - outsideLunch.targetToday) < 0.001)
    }

    @Test("部分重叠的午休只扣减落在工作时段内的部分")
    func partiallyOverlappingLunchDeductsOnlyOverlap() {
        // 午休 18:00–19:00，下班 18:30 → 只有 30 分钟与工作时段重叠。
        let day = edgeDay(
            now: DateComponents(hour: 18, minute: 30),
            hasLunchBreak: true,
            lunchStart: DateComponents(hour: 18, minute: 0),
            lunchEnd: DateComponents(hour: 19, minute: 0)
        )

        #expect(day.workdayMinutes == 9 * 60 - 30)
    }

    private func edgeDay(
        now: DateComponents,
        hasLunchBreak: Bool,
        lunchStart: DateComponents,
        lunchEnd: DateComponents
    ) -> WageDay {
        WageCalculator.compute(
            monthlySalary: 22_000,
            workdaysPerMonth: 22,
            workStart: .minuteInDay(9 * 60 + 30),
            workEnd: .minuteInDay(18 * 60 + 30),
            lunchStart: .minuteInDay(lunchStart.minutesInDay),
            lunchEnd: .minuteInDay(lunchEnd.minutesInDay),
            hasLunchBreak: hasLunchBreak,
            includeOvertime: false,
            now: now
        )
    }
}

struct WageStateWorkWindowTests {
    @Test("加载倒挂的工作时段时回退到默认值")
    func invertedPersistedWindowFallsBackToDefault() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(20 * 60, forKey: StorageKey.workStartMinute)
        defaults.set(8 * 60, forKey: StorageKey.workEndMinute)

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        #expect(state.workStart.minutesInDay == 9 * 60 + 30)
        #expect(state.workEnd.minutesInDay == 18 * 60 + 30)
        #expect(state.workEnd.minutesInDay > state.workStart.minutesInDay)
    }

    @Test("把下班时间设到上班之前会被回滚")
    func settingEndBeforeStartRollsBack() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        let originalEnd = state.workEnd.minutesInDay
        state.workEnd = DateComponents(hour: 8, minute: 0)

        #expect(state.workEnd.minutesInDay == originalEnd)
    }

    @Test("把上班时间设到下班之后会被回滚")
    func settingStartAfterEndRollsBack() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        let originalStart = state.workStart.minutesInDay
        state.workStart = DateComponents(hour: 20, minute: 0)

        #expect(state.workStart.minutesInDay == originalStart)
    }
}

struct WageStateWeekdayGuardTests {
    @Test("不能取消最后一个工作日")
    func cannotDeselectLastWorkday() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([2], forKey: StorageKey.selectedWeekdays)

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        #expect(state.selectedWeekdays == [2])
        state.toggleWeekday(2)
        #expect(state.selectedWeekdays == [2])
    }

    @Test("加载到空工作日集合时回退到默认值")
    func emptyPersistedWeekdaysFallBackToDefault() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([Int](), forKey: StorageKey.selectedWeekdays)

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        #expect(state.selectedWeekdays == [0, 1, 2, 3, 4])
    }
}

struct WageStateBackfillBoundTests {
    @Test("时钟大幅前跳时回填记录数量有上限")
    func backfillIsBoundedOnLargeClockJump() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        let farFuture = try #require(
            DateComponents.calendar.date(byAdding: .year, value: 5, to: state.currentDayStart)
        )
        state.refreshCalendarDayIfNeeded(now: farFuture)

        // 没有上限时这里会写入约 1826 条记录；上限把它压在 31 天附近。
        #expect(state.dailyRecords.count > 0)
        #expect(state.dailyRecords.count <= 32)
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
