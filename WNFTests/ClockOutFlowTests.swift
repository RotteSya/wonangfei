import Foundation
import SQLite3
import Testing
@testable import WNF

struct WNFClockParseTests {
    @Test("测试时钟能解析本地 ISO 时间")
    func parsesLocalISODate() throws {
        let date = try #require(WNFClock.parse("2026-08-17T19:00:00"))
        let components = DateComponents.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 17)
        #expect(components.hour == 19)
        #expect(components.minute == 0)
    }
}

struct ClockOutReminderPolicyTests {
    @Test("加班提醒同时受 App 开关和截止时间约束")
    func overtimeDeadlineRequiresEnabledFutureDeadline() throws {
        let now = try #require(dateOnFixedDay(hour: 19, minute: 0))
        let future = try #require(dateOnFixedDay(hour: 20, minute: 0))
        let past = try #require(dateOnFixedDay(hour: 18, minute: 0))

        #expect(
            ClockOutReminderService.schedulableOvertimeDeadline(
                enabled: false,
                deadline: future,
                now: now
            ) == nil
        )
        #expect(
            ClockOutReminderService.schedulableOvertimeDeadline(
                enabled: true,
                deadline: past,
                now: now
            ) == nil
        )
        #expect(
            ClockOutReminderService.schedulableOvertimeDeadline(
                enabled: true,
                deadline: future,
                now: now
            ) == future
        )
    }
}

struct ClockOutRuntimeEngineTests {
    @Test("同一截止 revision 只自动弹一次，关闭后不再弹")
    func dismissKeepsSameRevisionFromAutoPrompting() throws {
        let start = try #require(dateOnFixedDay(hour: 0, minute: 0))
        let now = try #require(dateOnFixedDay(hour: 19, minute: 0))
        var runtime = ClockOutRuntimeEngine.makeTodaySnapshot(
            dateKey: "2026-08-17",
            workEndMinute: 18 * 60 + 30
        )

        let due = ClockOutRuntimeEngine.phase(
            isPaidWorkday: true,
            isSettled: false,
            runtime: runtime,
            now: now,
            startOfDay: start
        )
        guard case .decisionDue(_, let revision) = due else {
            Issue.record("expected decisionDue")
            return
        }
        #expect(revision == 0)

        runtime = ClockOutRuntimeEngine.dismiss(runtime)
        let dismissed = ClockOutRuntimeEngine.phase(
            isPaidWorkday: true,
            isSettled: false,
            runtime: runtime,
            now: now,
            startOfDay: start
        )
        guard case .promptDismissed(_, let dismissedRevision) = dismissed else {
            Issue.record("expected promptDismissed")
            return
        }
        #expect(dismissedRevision == 0)
    }

    @Test("新加班截止产生新 revision，可再次弹出")
    func overtimeCreatesNewRevisionThatCanPromptAgain() throws {
        let start = try #require(dateOnFixedDay(hour: 0, minute: 0))
        let now = try #require(dateOnFixedDay(hour: 19, minute: 0))
        var runtime = ClockOutRuntimeEngine.makeTodaySnapshot(
            dateKey: "2026-08-17",
            workEndMinute: 18 * 60 + 30
        )
        runtime = ClockOutRuntimeEngine.dismiss(runtime)
        runtime = ClockOutRuntimeEngine.beginOvertime(
            runtime: runtime,
            duration: 60 * 60,
            now: now,
            startOfDay: start
        )
        #expect(runtime.revision == 1)
        #expect(runtime.dismissedRevision == nil)

        let running = ClockOutRuntimeEngine.phase(
            isPaidWorkday: true,
            isSettled: false,
            runtime: runtime,
            now: now,
            startOfDay: start
        )
        guard case .overtimeRunning(let until, let revision) = running else {
            Issue.record("expected overtimeRunning")
            return
        }
        #expect(revision == 1)
        #expect(ClockOutRuntimeEngine.clockText(for: until) == "20:00")

        let afterDeadline = try #require(dateOnFixedDay(hour: 20, minute: 0))
        let dueAgain = ClockOutRuntimeEngine.phase(
            isPaidWorkday: true,
            isSettled: false,
            runtime: runtime,
            now: afterDeadline,
            startOfDay: start
        )
        guard case .decisionDue(_, let nextRevision) = dueAgain else {
            Issue.record("expected decisionDue after overtime")
            return
        }
        #expect(nextRevision == 1)
    }

    @Test("加班最晚停在当天 23:59:59")
    func overtimeCannotCrossMidnight() throws {
        let start = try #require(dateOnFixedDay(hour: 0, minute: 0))
        let now = try #require(dateOnFixedDay(hour: 23, minute: 30))
        let runtime = ClockOutRuntimeEngine.beginOvertime(
            runtime: ClockOutRuntimeEngine.makeTodaySnapshot(
                dateKey: "2026-08-17",
                workEndMinute: 18 * 60 + 30
            ),
            duration: 3 * 60 * 60,
            now: now,
            startOfDay: start
        )
        let endOfDay = ClockOutRuntimeEngine.endOfDay(for: start)
        #expect(runtime.overtimeEnd == endOfDay)
    }

    @Test("非工作日不生成 decision")
    func unpaidDayStaysOff() throws {
        let start = try #require(dateOnFixedDay(hour: 0, minute: 0))
        let now = try #require(dateOnFixedDay(hour: 19, minute: 0))
        let phase = ClockOutRuntimeEngine.phase(
            isPaidWorkday: false,
            isSettled: false,
            runtime: ClockOutRuntimeEngine.makeTodaySnapshot(
                dateKey: "2026-08-17",
                workEndMinute: 18 * 60 + 30
            ),
            now: now,
            startOfDay: start
        )
        #expect(phase == .offDay)
    }
}

struct OvertimeMathTests {
    @Test("加班不改变基础时薪和正常日薪目标")
    func overtimeDoesNotChangeBaseRateOrTarget() {
        let base = sampleDay(now: DateComponents(hour: 18, minute: 30))
        let start = dateOnFixedDay(hour: 0, minute: 0)!
        let normalEnd = ClockOutRuntimeEngine.workEndDate(startOfDay: start, minute: 18 * 60 + 30)
        let overtimeEnd = dateOnFixedDay(hour: 20, minute: 0)!
        let now = dateOnFixedDay(hour: 19, minute: 30)!

        let overtime = WageCalculator.applyingOvertime(
            to: base,
            normalEnd: normalEnd,
            overtimeEnd: overtimeEnd,
            now: now
        )

        #expect(overtime.hourlyRate == base.hourlyRate)
        #expect(overtime.targetToday == base.targetToday)
        #expect(overtime.workdayMinutes == base.workdayMinutes)
        #expect(overtime.progress == 1)
        #expect(overtime.overtimeSeconds == 60 * 60)
        #expect(abs(overtime.overtimeEarned - base.hourlyRate) < 0.000_001)
        #expect(abs(overtime.earnedToday - (base.earnedToday + overtime.overtimeEarned)) < 0.000_001)
        #expect(overtime.elapsedPaidSeconds == base.elapsedPaidSeconds + 3600)
    }

    @Test("晚进入后确认加班会从正常截止时间补算，并在新截止封顶")
    func lateOvertimeBackfillsFromNormalEndThenCaps() {
        let base = sampleDay(now: DateComponents(hour: 19, minute: 0))
        let start = dateOnFixedDay(hour: 0, minute: 0)!
        let normalEnd = ClockOutRuntimeEngine.workEndDate(startOfDay: start, minute: 18 * 60 + 30)
        let overtimeEnd = dateOnFixedDay(hour: 20, minute: 0)!

        let atConfirm = WageCalculator.applyingOvertime(
            to: base,
            normalEnd: normalEnd,
            overtimeEnd: overtimeEnd,
            now: dateOnFixedDay(hour: 19, minute: 0)!
        )
        let atCap = WageCalculator.applyingOvertime(
            to: base,
            normalEnd: normalEnd,
            overtimeEnd: overtimeEnd,
            now: dateOnFixedDay(hour: 20, minute: 0)!
        )
        let afterCap = WageCalculator.applyingOvertime(
            to: base,
            normalEnd: normalEnd,
            overtimeEnd: overtimeEnd,
            now: dateOnFixedDay(hour: 21, minute: 0)!
        )

        #expect(atConfirm.overtimeSeconds == 30 * 60)
        #expect(atCap.overtimeSeconds == 90 * 60)
        #expect(afterCap.overtimeSeconds == atCap.overtimeSeconds)
        #expect(afterCap.earnedToday == atCap.earnedToday)
    }

    @Test("多次延长连续计算，不重复或漏算")
    func repeatedExtensionsStayContinuous() {
        let base = sampleDay(now: DateComponents(hour: 18, minute: 30))
        let start = dateOnFixedDay(hour: 0, minute: 0)!
        let normalEnd = ClockOutRuntimeEngine.workEndDate(startOfDay: start, minute: 18 * 60 + 30)
        let firstEnd = dateOnFixedDay(hour: 20, minute: 0)!
        let secondEnd = dateOnFixedDay(hour: 21, minute: 30)!
        let now = dateOnFixedDay(hour: 21, minute: 0)!

        let stacked = WageCalculator.applyingOvertime(
            to: base,
            normalEnd: normalEnd,
            overtimeEnd: secondEnd,
            now: now
        )
        #expect(stacked.overtimeSeconds == Int(now.timeIntervalSince(normalEnd)))
        #expect(stacked.overtimeSeconds > Int(firstEnd.timeIntervalSince(normalEnd)))
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
struct ClockOutWageStateTests {
    @Test("下班前一毫秒仍计薪，到达下班时间自动封顶，晚进入金额相同")
    func autoStopCapsWithoutButton() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let before = try #require(dateToday(hour: 18, minute: 29, second: 59, nanosecond: 999_000_000))
        let atBoundary = try #require(dateToday(hour: 18, minute: 30))
        let late = try #require(dateToday(hour: 21, minute: 0))
        defaults.set([weekdayIndex(for: atBoundary)], forKey: StorageKey.selectedWeekdays)
        defaults.set(18 * 60 + 30, forKey: StorageKey.workEndMinute)

        WNFClock.setOverride(before)
        defer { WNFClock.resetOverride() }
        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        let stillPaid = state.liveDay(at: before)
        state.reconcileClockOut(now: atBoundary)
        let capped = state.liveDay(at: atBoundary)
        let lateDay = state.liveDay(at: late)

        #expect(stillPaid.earnedToday < capped.earnedToday)
        #expect(abs(capped.earnedToday - capped.targetToday) < 0.000_001)
        #expect(lateDay.earnedToday == capped.earnedToday)
        guard case .decisionDue = state.clockOutPhase else {
            Issue.record("expected decisionDue after work end")
            return
        }
    }

    @Test("非工作日不生成 decision，次日不补弹旧日 decision")
    func unpaidAndNextDayDoNotPromptOldDecision() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let today = try #require(dateToday(hour: 19, minute: 0))
        let todayWeekday = weekdayIndex(for: today)
        defaults.set(Array(Set(0...6).subtracting([todayWeekday])), forKey: StorageKey.selectedWeekdays)

        WNFClock.setOverride(today)
        defer { WNFClock.resetOverride() }
        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }
        state.reconcileClockOut(now: today)
        #expect(state.clockOutPhase == .offDay)

        defaults.set(Array(0...6), forKey: StorageKey.selectedWeekdays)
        let workdayState = WageState(userDefaults: defaults)
        defer { workdayState.pauseCalendarDayTimer() }
        workdayState.selectedWeekdays = Set(0...6)
        workdayState.reconcileClockOut(now: today)
        guard case .decisionDue = workdayState.clockOutPhase else {
            Issue.record("expected decisionDue on a workday")
            return
        }

        let tomorrowMorning = try #require(
            DateComponents.calendar.date(byAdding: DateComponents(day: 1, hour: -9), to: today)
        )
        workdayState.refreshCalendarDayIfNeeded(now: tomorrowMorning)
        if case .decisionDue = workdayState.clockOutPhase {
            Issue.record("must not re-prompt yesterday")
        }
        #expect(workdayState.clockOutPhase != .settled)
    }

    @Test("关闭后同一 revision 不再自动弹，新加班截止可再弹")
    func dismissThenOvertimeRepromptsOnNewRevision() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let now = try #require(dateToday(hour: 19, minute: 0))
        defaults.set([weekdayIndex(for: now)], forKey: StorageKey.selectedWeekdays)
        WNFClock.setOverride(now)
        defer { WNFClock.resetOverride() }

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }
        state.reconcileClockOut(now: now)
        state.dismissClockOutPrompt()
        guard case .promptDismissed(_, let revision) = state.clockOutPhase else {
            Issue.record("expected promptDismissed")
            return
        }
        state.reconcileClockOut(now: now)
        guard case .promptDismissed(_, let sameRevision) = state.clockOutPhase else {
            Issue.record("reconcile must not revive the same prompt")
            return
        }
        #expect(sameRevision == revision)

        state.beginOvertime(duration: 60 * 60, now: now)
        guard case .overtimeRunning = state.clockOutPhase else {
            Issue.record("expected overtimeRunning")
            return
        }
        let later = now.addingTimeInterval(60 * 60)
        state.reconcileClockOut(now: later)
        guard case .decisionDue(_, let nextRevision) = state.clockOutPhase else {
            Issue.record("expected a new decision after overtime")
            return
        }
        #expect(nextRevision == revision + 1)
    }

    @Test("App 重启后恢复 overtime deadline")
    func restartRestoresOvertimeDeadline() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let now = try #require(dateToday(hour: 19, minute: 0))
        defaults.set([weekdayIndex(for: now)], forKey: StorageKey.selectedWeekdays)
        WNFClock.setOverride(now)
        defer { WNFClock.resetOverride() }

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }
        state.reconcileClockOut(now: now)
        state.beginOvertime(duration: 60 * 60, now: now)
        let expectedEnd = state.clockOutRuntimeState?.overtimeEnd

        let restored = WageState(userDefaults: defaults)
        defer { restored.pauseCalendarDayTimer() }
        restored.reconcileClockOut(now: now.addingTimeInterval(15 * 60))
        guard case .overtimeRunning(let until, _) = restored.clockOutPhase else {
            Issue.record("expected restored overtimeRunning")
            return
        }
        #expect(until == expectedEnd)
    }

    @Test("重复调用 reconcile 不重复结算，confirm 后不能再加班")
    func reconcileIsIdempotentAndSettledBlocksOvertime() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let now = try #require(dateToday(hour: 19, minute: 0))
        defaults.set([weekdayIndex(for: now)], forKey: StorageKey.selectedWeekdays)
        WNFClock.setOverride(now)
        defer { WNFClock.resetOverride() }

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }
        state.reconcileClockOut(now: now)
        state.reconcileClockOut(now: now)
        #expect(state.isTodaySettled == false)

        state.confirmClockOut(now: now)
        #expect(state.isTodaySettled)
        #expect(state.clockOutPhase == .settled)
        state.confirmClockOut(now: now)
        state.beginOvertime(duration: 60 * 60, now: now)
        #expect(state.clockOutPhase == .settled)
        #expect(state.clockOutRuntimeState?.overtimeEnd == nil || state.isTodaySettled)
    }

    @Test("修改默认下班时间不改变当天快照")
    func changingDefaultWorkEndDoesNotMutateTodaySnapshot() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let morning = try #require(dateToday(hour: 10, minute: 0))
        let evening = try #require(dateToday(hour: 19, minute: 0))
        defaults.set([weekdayIndex(for: morning)], forKey: StorageKey.selectedWeekdays)
        defaults.set(18 * 60 + 30, forKey: StorageKey.workEndMinute)
        WNFClock.setOverride(morning)
        defer { WNFClock.resetOverride() }

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }
        let snapshotEnd = state.todayWorkEndMinute
        state.setWorkEnd(.minuteInDay(20 * 60))
        #expect(state.workEnd.minutesInDay == 20 * 60)
        #expect(state.todayWorkEndMinute == snapshotEnd)

        let late = state.liveDay(at: evening)
        #expect(abs(late.earnedToday - late.targetToday) < 0.000_001)
        state.reconcileClockOut(now: evening)
        guard case .decisionDue = state.clockOutPhase else {
            Issue.record("today must still stop at the snapshotted end")
            return
        }
    }

    @Test("旧记录的加班字段默认为 0")
    func legacyDailyRecordDecodesZeroOvertime() throws {
        let json = """
        {
          "dateKey": "2026-08-17",
          "earnedToday": 88,
          "targetToday": 88,
          "elapsedPaidSeconds": 3600,
          "workdayMinutes": 480,
          "hourlyRate": 100,
          "monthlySalary": 20000,
          "workdaysPerMonth": 22,
          "capturedAt": 0,
          "source": "observed"
        }
        """.data(using: .utf8)!
        let record = try JSONDecoder().decode(DailyWageRecord.self, from: json)
        #expect(record.overtimeSeconds == 0)
        #expect(record.overtimeEarned == 0)
    }

    @Test("已有 SQLite 库会幂等加上加班列")
    func sqliteAddsOvertimeColumnsWithoutRebuilding() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let path = try #require(defaults.string(forKey: StorageKey.dailyRecordsSQLitePathOverride))
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        let create = """
        CREATE TABLE daily_records (
            date_key TEXT PRIMARY KEY NOT NULL,
            earned_today REAL NOT NULL,
            target_today REAL NOT NULL,
            elapsed_paid_seconds INTEGER NOT NULL,
            workday_minutes INTEGER NOT NULL,
            hourly_rate REAL NOT NULL,
            monthly_salary REAL NOT NULL,
            workdays_per_month INTEGER NOT NULL,
            captured_at REAL NOT NULL,
            source TEXT NOT NULL
        );
        """
        #expect(sqlite3_exec(db, create, nil, nil, nil) == SQLITE_OK)
        let insert = """
        INSERT INTO daily_records VALUES ('2026-08-17', 88, 88, 3600, 480, 100, 20000, 22, 0, 'observed');
        """
        #expect(sqlite3_exec(db, insert, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let store = DailyRecordSQLiteStore(userDefaults: defaults, databaseURL: URL(fileURLWithPath: path))
        let loaded = store.load(now: dateOnFixedDay(hour: 10, minute: 0)!)
        let record = try #require(loaded.records["2026-08-17"])
        #expect(record.overtimeSeconds == 0)
        #expect(record.overtimeEarned == 0)
        #expect(record.earnedToday == 88)
    }
}

struct ClockOutWidgetTests {
    @Test("新快照在 overtimeEnd 前继续投影，之后严格封顶")
    func overtimeEndProjectsThenCaps() throws {
        let atNineteen = try #require(dateOnFixedDay(hour: 19, minute: 0))
        let atTwenty = try #require(dateOnFixedDay(hour: 20, minute: 0))
        let atTwentyOne = try #require(dateOnFixedDay(hour: 21, minute: 0))
        let snapshot = WNFWidgetSnapshot(
            capturedAt: atNineteen,
            earnedToday: 8 * 3600,
            elapsedPaidMinutes: 8 * 60,
            workStartMinute: 9 * 60 + 30,
            workEndMinute: 18 * 60 + 30,
            lunchStartMinute: 12 * 60,
            lunchEndMinute: 13 * 60,
            hasLunchBreak: true,
            includeOvertime: false,
            workdayMinutes: 480,
            earningPerSecond: 1,
            selectedWeekdays: Array(0...6),
            statusLabel: WorkStatus.done.label,
            overtimeEnd: atTwenty,
            overtimeSeconds: 30 * 60
        )

        let projected = snapshot.projected(at: atNineteen)
        let capped = snapshot.projected(at: atTwenty)
        let after = snapshot.projected(at: atTwentyOne)
        #expect(projected.elapsedPaidMinutes == 8 * 60 + 30)
        #expect(capped.earnedToday == after.earnedToday)
        #expect(WNFWidgetTimeline.projectionEndDate(for: snapshot, now: atNineteen) == atTwenty)
    }

    @Test("schema v2 快照仍能解码，旧 includeOvertime=true 不能绕过边界")
    func schemaV2DecodesAndLegacyFlagCannotBypass() throws {
        let capturedAt = try #require(dateOnFixedDay(hour: 18, minute: 30))
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "dateKey": "2026-08-17",
            "capturedAt": capturedAt.timeIntervalSinceReferenceDate,
            "earnedToday": 100.0,
            "elapsedPaidMinutes": 480,
            "workStartMinute": 9 * 60 + 30,
            "workEndMinute": 18 * 60 + 30,
            "lunchStartMinute": 12 * 60,
            "lunchEndMinute": 13 * 60,
            "hasLunchBreak": true,
            "includeOvertime": true,
            "workdayMinutes": 480,
            "earningPerSecond": 1.0,
            "selectedWeekdays": [0, 1, 2, 3, 4, 5, 6],
            "statusLabel": "今日通关",
            "hidesSensitiveInfo": false
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(WNFWidgetSnapshot.self, from: data)
        #expect(decoded.schemaVersion == 2)
        #expect(decoded.includeOvertime)
        #expect(decoded.overtimeEnd == nil)
        #expect(decoded.overtimeSeconds == 0)

        let afterWork = try #require(dateOnFixedDay(hour: 22, minute: 0))
        let projected = decoded.projected(at: afterWork)
        let atEnd = decoded.projected(at: capturedAt)
        #expect(projected.earnedToday == atEnd.earnedToday)
    }
}

@MainActor
struct ClockOutLiveActivityTests {
    @Test("Live Activity 在正常、加班、待领取、已结算状态间正确切换")
    func liveActivityContentTracksPhase() throws {
        let (defaults, _, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let afternoon = try #require(dateToday(hour: 15, minute: 0))
        let afterWork = try #require(dateToday(hour: 19, minute: 0))
        defaults.set([weekdayIndex(for: afternoon)], forKey: StorageKey.selectedWeekdays)
        WNFClock.setOverride(afternoon)
        defer { WNFClock.resetOverride() }

        let state = WageState(userDefaults: defaults)
        defer { state.pauseCalendarDayTimer() }

        let working = WNFLiveActivityController.contentState(
            state: state,
            day: state.liveDay(at: afternoon),
            phase: .working,
            now: afternoon
        )
        #expect(working.isDone == false)
        #expect(working.isOvertime == false)

        state.reconcileClockOut(now: afterWork)
        let pending = WNFLiveActivityController.contentState(
            state: state,
            day: state.liveDay(at: afterWork),
            phase: state.clockOutPhase,
            now: afterWork
        )
        #expect(pending.isDone)
        #expect(pending.isOvertime == false)

        state.beginOvertime(duration: 60 * 60, now: afterWork)
        let overtime = WNFLiveActivityController.contentState(
            state: state,
            day: state.liveDay(at: afterWork),
            phase: state.clockOutPhase,
            now: afterWork
        )
        #expect(overtime.isOvertime)
        #expect(overtime.isDone == false)
        #expect(overtime.overtimeEnd != nil)

        state.confirmClockOut(now: afterWork)
        #expect(state.isTodaySettled)
        #expect(state.clockOutPhase == .settled)
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
        WNFClock.resetOverride()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
    return (defaults, suiteName, cleanup)
}

private func dateToday(hour: Int, minute: Int, second: Int = 0, nanosecond: Int = 0) -> Date? {
    var components = DateComponents.calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = hour
    components.minute = minute
    components.second = second
    components.nanosecond = nanosecond
    return DateComponents.calendar.date(from: components)
}

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
