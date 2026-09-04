import Foundation
import Testing
@testable import WNF

struct WageCalculatorTests {
    @Test("上班前金额为 0")
    func beforeWorkEarnsNothing() {
        let day = sampleDay(now: DateComponents(hour: 8, minute: 30))

        #expect(day.earnedToday == 0)
        #expect(day.elapsedPaidSeconds == 0)
    }

    @Test("午休不计薪")
    func lunchBreakIsNotPaid() {
        let lunchStart = sampleDay(now: DateComponents(hour: 12, minute: 0))
        let duringLunch = sampleDay(now: DateComponents(hour: 12, minute: 30))

        #expect(abs(duringLunch.earnedToday - lunchStart.earnedToday) < 0.001)
        #expect(duringLunch.elapsedPaidSeconds == lunchStart.elapsedPaidSeconds)
    }

    @Test("下班后金额在配置边界封顶")
    func afterWorkCapsEarnings() {
        let atWorkEnd = sampleDay(now: DateComponents(hour: 18, minute: 30))
        let afterWork = sampleDay(now: DateComponents(hour: 20, minute: 0))

        #expect(abs(afterWork.earnedToday - atWorkEnd.earnedToday) < 0.001)
        #expect(abs(afterWork.earnedToday - afterWork.targetToday) < 0.001)
        #expect(afterWork.progress == 1)
    }

    @Test("下班前一毫秒仍计薪，边界到达后不再增长")
    func offDutyBoundaryIsExactToTheMillisecond() {
        let before = sampleDay(now: DateComponents(hour: 18, minute: 29, second: 59, nanosecond: 999_000_000))
        let atBoundary = sampleDay(now: DateComponents(hour: 18, minute: 30))
        let after = sampleDay(now: DateComponents(hour: 18, minute: 30, nanosecond: 1_000_000))

        #expect(before.earnedToday < atBoundary.earnedToday)
        #expect(abs(atBoundary.earnedToday - atBoundary.targetToday) < 0.000_001)
        #expect(after.earnedToday == atBoundary.earnedToday)
        #expect(after.elapsedPaidSeconds == atBoundary.elapsedPaidSeconds)
        #expect(after.status == .done)
    }

    @Test("休眠跨过下班后重算仍封顶，午夜后新日归零")
    func delayedWakeAndMidnightUseWallClockBoundaries() {
        let atBoundary = sampleDay(now: DateComponents(hour: 18, minute: 30))
        let delayedWake = sampleDay(now: DateComponents(hour: 23, minute: 59, second: 59))
        let nextMidnight = sampleDay(now: DateComponents(hour: 0, minute: 0))

        #expect(delayedWake.earnedToday == atBoundary.earnedToday)
        #expect(delayedWake.elapsedPaidSeconds == atBoundary.elapsedPaidSeconds)
        #expect(nextMidnight.earnedToday == 0)
        #expect(nextMidnight.elapsedPaidSeconds == 0)
        #expect(nextMidnight.status == .before)
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
            now: DateComponents(hour: 10, minute: 30)
        )

        #expect(day.workdayMinutes == 8 * 60 + 30)
        #expect(day.elapsedPaidSeconds == 30 * 60)
    }

    private func sampleDay(now: DateComponents) -> WageDay {
        WageCalculator.compute(
            monthlySalary: 22_000,
            workdaysPerMonth: 22,
            workStart: .minuteInDay(9 * 60 + 30),
            workEnd: .minuteInDay(18 * 60 + 30),
            lunchStart: .minuteInDay(12 * 60),
            lunchEnd: .minuteInDay(13 * 60),
            hasLunchBreak: true,
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

struct RecordBadgeCatalogTests {
    @Test("徽章目录稳定包含十二枚且空记录不解锁")
    func emptyRecordKeepsAllBadgesLocked() {
        let badges = RecordBadgeCatalog.make(
            todayEarned: 0,
            currentMonthSummary: RecordSummary(),
            isTodaySettled: false
        )

        #expect(badges.count == 12)
        #expect(badges.allSatisfy { !$0.unlocked })
        #expect(Set(badges.map(\.id)).count == badges.count)
    }

    @Test("金额、坐班、工时与结算按真实阈值解锁")
    func thresholdsUnlockExpectedBadges() {
        let badges = RecordBadgeCatalog.make(
            todayEarned: 100,
            currentMonthSummary: RecordSummary(
                amount: 3_000,
                recordedDays: 10,
                elapsedPaidSeconds: 40 * 60 * 60
            ),
            isTodaySettled: true
        )
        let unlockedIDs = Set(badges.filter(\.unlocked).map(\.id))

        #expect(unlockedIDs == [
            "today-started",
            "lunch-money",
            "today-100",
            "today-settled",
            "month-days-3",
            "month-days-10",
            "month-1000",
            "month-3000",
            "month-hours-40"
        ])
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

    @Test("Widget timeline 会封顶较长的未来分钟 entries")
    func widgetTimelineCapsLongProjectionWindow() throws {
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

    @Test("Widget 旧快照的加班字段不能绕过下班上界")
    func legacyOvertimeFlagCannotBypassWorkEnd() throws {
        let atWorkEnd = try #require(dateOnFixedDay(hour: 18, minute: 30))
        let afterWork = try #require(dateOnFixedDay(hour: 22, minute: 0))
        let snapshot = widgetSnapshot(
            hidesSensitiveInfo: false,
            capturedAt: atWorkEnd,
            earningPerSecond: 1,
            includeOvertime: true
        )

        let atBoundary = snapshot.projected(at: atWorkEnd)
        let afterBoundary = snapshot.projected(at: afterWork)

        #expect(afterBoundary.earnedToday == atBoundary.earnedToday)
        #expect(afterBoundary.elapsedPaidMinutes == atBoundary.elapsedPaidMinutes)
        #expect(WNFWidgetTimeline.projectionEndDate(for: snapshot, now: atWorkEnd) == atWorkEnd)
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

struct WorkStatusLabelTests {
    @Test("WorkStatus.label 覆盖六个状态文案")
    func workStatusLabelsMatchContract() {
        #expect(WorkStatus.off.label == "今天不用窝囊")
        #expect(WorkStatus.before.label == "尚未开工")
        #expect(WorkStatus.morning.label == "上午搬砖中")
        #expect(WorkStatus.lunch.label == "午休回血")
        #expect(WorkStatus.afternoon.label == "下午挺挺")
        #expect(WorkStatus.done.label == "今日通关")
        #expect(WorkStatus.allCases.count == 6)
    }

    @Test("Widget 工作日投影与 WorkStatus.label 同源")
    func widgetProjectionUsesWorkStatusLabelsOnSelectedWorkday() throws {
        let cases: [(hour: Int, minute: Int, status: WorkStatus)] = [
            (8, 0, .before),
            (10, 0, .morning),
            (12, 30, .lunch),
            (15, 0, .afternoon),
            (19, 0, .done)
        ]
        for item in cases {
            let now = try #require(dateOnFixedDay(hour: item.hour, minute: item.minute))
            let snapshot = widgetSnapshot(
                hidesSensitiveInfo: false,
                capturedAt: now,
                earningPerSecond: 1,
                selectedWeekdays: [0, 1, 2, 3, 4]
            )
            #expect(snapshot.projected(at: now).statusLabel == item.status.label)
        }
    }

    @Test("Widget 非选中工作日投影使用 WorkStatus.off.label")
    func widgetProjectionUsesOffLabelOnUnselectedWeekday() throws {
        let now = try #require(dateOnFixedDay(hour: 10, minute: 0))
        let snapshot = widgetSnapshot(
            hidesSensitiveInfo: false,
            capturedAt: now,
            earningPerSecond: 1,
            selectedWeekdays: [1, 2, 3, 4]
        )
        #expect(snapshot.projected(at: now).statusLabel == WorkStatus.off.label)
    }

    @Test("WorkStatusPresentation.label 等于 WorkStatus.label")
    func presentationLabelMatchesWorkStatus() {
        for status in WorkStatus.allCases {
            #expect(WorkStatusPresentation(status: status).label == status.label)
        }
    }
}

struct AcknowledgementsBundleTests {
    @Test("App bundle includes OFL acknowledgements HTML")
    func bundledAcknowledgementsContainsOFLAndFontFilenames() throws {
        let url = try #require(Bundle.main.url(forResource: "acknowledgements", withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(html.contains("SIL Open Font License"))
        #expect(html.contains("JetBrainsMono-Regular.ttf"))
        #expect(html.contains("JetBrainsMono-Bold.ttf"))
        #expect(html.contains("ZCOOLQingKeHuangYou-Regular.ttf"))
    }
}

struct LegalWebNavigationPolicyTests {
    @Test("In-app legal WebView allows file loads and cancels http(s)")
    func cancelsHTTPAndHTTPS() {
        #expect(LegalWebNavigationPolicy.allows(URL(string: "file:///tmp/acknowledgements.html")))
        #expect(LegalWebNavigationPolicy.allows(URL(string: "about:blank")))
        #expect(LegalWebNavigationPolicy.allows(nil))
        #expect(!LegalWebNavigationPolicy.allows(URL(string: "https://github.com/JetBrains/JetBrainsMono")))
        #expect(!LegalWebNavigationPolicy.allows(URL(string: "http://scripts.sil.org/OFL")))
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
        selectedWeekdays: selectedWeekdays
    )
}

private func widgetSnapshot(
    hidesSensitiveInfo: Bool,
    capturedAt: Date = Date(),
    earningPerSecond: Double = 0,
    includeOvertime: Bool = false,
    selectedWeekdays: [Int] = Array(0...6)
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
        selectedWeekdays: selectedWeekdays,
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
