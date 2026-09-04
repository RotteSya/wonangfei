import Foundation

@MainActor
final class WageState: ObservableObject {
    @Published var monthlySalary: Double {
        didSet {
            userDefaults.set(monthlySalary, forKey: StorageKey.monthlySalary)
            recordCalculationSettingsChanged()
        }
    }

    @Published var workdaysPerMonth: Int {
        didSet {
            userDefaults.set(workdaysPerMonth, forKey: StorageKey.workdaysPerMonth)
            recordCalculationSettingsChanged()
        }
    }

    @Published var workStart: DateComponents {
        didSet {
            userDefaults.set(workStart.minutesInDay, forKey: StorageKey.workStartMinute)
            recordCalculationSettingsChanged()
        }
    }

    @Published var workEnd: DateComponents {
        didSet {
            userDefaults.set(workEnd.minutesInDay, forKey: StorageKey.workEndMinute)
            recordCalculationSettingsChanged()
            reconcileClockOutReminder()
        }
    }

    @Published var lunchStart: DateComponents {
        didSet {
            userDefaults.set(lunchStart.minutesInDay, forKey: StorageKey.lunchStartMinute)
            recordCalculationSettingsChanged()
        }
    }

    @Published var lunchEnd: DateComponents {
        didSet {
            userDefaults.set(lunchEnd.minutesInDay, forKey: StorageKey.lunchEndMinute)
            recordCalculationSettingsChanged()
        }
    }

    @Published var hasLunchBreak: Bool {
        didSet {
            userDefaults.set(hasLunchBreak, forKey: StorageKey.hasLunchBreak)
            recordCalculationSettingsChanged()
        }
    }

    @Published var privacyMode: Bool {
        didSet {
            userDefaults.set(privacyMode, forKey: StorageKey.privacyMode)
        }
    }

    @Published var selectedWeekdays: Set<Int> {
        didSet {
            userDefaults.set(selectedWeekdays.sorted(), forKey: StorageKey.selectedWeekdays)
            recordCalculationSettingsChanged()
            reconcileClockOutReminder()
        }
    }

    @Published var liveActivityEnabled: Bool {
        didSet {
            userDefaults.set(liveActivityEnabled, forKey: StorageKey.liveActivityEnabled)
            Task { @MainActor in
                WNFLiveActivityController.reconcile(state: self)
            }
        }
    }

    @Published var clockOutReminderEnabled: Bool {
        didSet {
            userDefaults.set(clockOutReminderEnabled, forKey: StorageKey.clockOutReminderEnabled)
            reconcileClockOutReminder()
        }
    }

    @Published private(set) var currentDateKey: String
    @Published private(set) var dailyRecords: [String: DailyWageRecord]
    @Published private(set) var monthlyRecordSummaries: [String: MonthlyRecordSummary]
    private(set) var recordsRevision = 0

    @Published private(set) var lastSettlementDateKey: String? {
        didSet {
            if let key = lastSettlementDateKey {
                userDefaults.set(key, forKey: StorageKey.lastSettlementDateKey)
            } else {
                userDefaults.removeObject(forKey: StorageKey.lastSettlementDateKey)
            }
        }
    }

    @Published private(set) var clockOutPhase: ClockOutPhase = .working
    @Published private(set) var clockOutRuntimeState: ClockOutRuntimeState?

    /// `true` when the user has explicitly completed (or saved) today's settlement.
    /// Used by Home to switch into the lightweight "personal time" presentation.
    /// Naturally resets when `currentDateKey` advances past the stored date.
    var isTodaySettled: Bool {
        lastSettlementDateKey == currentDateKey
    }

    var todayWorkEndMinute: Int {
        clockOutRuntimeState?.baseWorkEndMinute ?? workEnd.minutesInDay
    }

    func markTodaySettled() {
        lastSettlementDateKey = currentDateKey
        clockOutPhase = derivedClockOutPhase(now: WNFClock.now)
        Task { @MainActor in
            WNFLiveActivityController.reconcile(state: self)
        }
    }

    let userDefaults: UserDefaults
    private let dailyRecordStore: DailyRecordSQLiteStore
    // Task handles are cancelled from deinit, which is nonisolated.
    nonisolated(unsafe) private var dayBoundaryTask: Task<Void, Never>?
    nonisolated(unsafe) private var clockOutDeadlineTask: Task<Void, Never>?

    /// Cached result of the most recent `calculation(at:)` call. Keyed by the
    /// settings fingerprint (everything `WageCalculator` reads from `self`) and
    /// the second-precision bucket of the input date. Repeated reads from
    /// SettingsView, RecordsView, widget snapshot, etc. within the same second
    /// hit this cache instead of re-running the calendar component extraction
    /// and the compute step.
    private var calculationCache: (fingerprint: CalculationFingerprint, secondBucket: Int, day: WageDay)?
    private var liveDayCache: (fingerprint: LiveDayFingerprint, secondBucket: Int, day: WageDay)?

    init(userDefaults: UserDefaults = .standard, dailyRecordStore: DailyRecordSQLiteStore? = nil) {
        self.userDefaults = userDefaults
        self.dailyRecordStore = dailyRecordStore ?? DailyRecordSQLiteStore(userDefaults: userDefaults)

        let now = WNFClock.now
        let usesTestClock = WNFClock.isLaunchFrozen
        monthlySalary = Self.clampedMonthlySalary(userDefaults.doubleValue(forKey: StorageKey.monthlySalary) ?? Default.monthlySalary)
        workdaysPerMonth = Self.clampedWorkdaysPerMonth(userDefaults.integerValue(forKey: StorageKey.workdaysPerMonth) ?? Default.workdaysPerMonth)
        workStart = DateComponents.minuteInDay(userDefaults.integerValue(forKey: StorageKey.workStartMinute) ?? Default.workStartMinute)
        workEnd = DateComponents.minuteInDay(
            usesTestClock ? Default.workEndMinute : (userDefaults.integerValue(forKey: StorageKey.workEndMinute) ?? Default.workEndMinute)
        )
        lunchStart = DateComponents.minuteInDay(userDefaults.integerValue(forKey: StorageKey.lunchStartMinute) ?? Default.lunchStartMinute)
        lunchEnd = DateComponents.minuteInDay(userDefaults.integerValue(forKey: StorageKey.lunchEndMinute) ?? Default.lunchEndMinute)
        hasLunchBreak = userDefaults.boolValue(forKey: StorageKey.hasLunchBreak) ?? Default.hasLunchBreak
        privacyMode = userDefaults.boolValue(forKey: StorageKey.privacyMode) ?? Default.privacyMode
        var weekdays = userDefaults.weekdaySet(forKey: StorageKey.selectedWeekdays) ?? Default.selectedWeekdays
        if usesTestClock {
            weekdays.insert(Self.weekdayIndex(for: now))
        }
        selectedWeekdays = weekdays
        clockOutReminderEnabled = userDefaults.boolValue(forKey: StorageKey.clockOutReminderEnabled) ?? Default.clockOutReminderEnabled
        liveActivityEnabled = userDefaults.boolValue(forKey: StorageKey.liveActivityEnabled) ?? Default.liveActivityEnabled
        lastSettlementDateKey = usesTestClock ? nil : userDefaults.string(forKey: StorageKey.lastSettlementDateKey)
        let loadedRuntime = Self.decodeClockOutRuntimeState(from: userDefaults)
        if usesTestClock {
            clockOutRuntimeState = loadedRuntime?.dateKey == Self.dateKey(for: now) ? loadedRuntime : nil
        } else {
            clockOutRuntimeState = loadedRuntime
        }
        currentDateKey = Self.dateKey(for: now)
        let dailyRecordLoadResult = self.dailyRecordStore.load(now: now)
        dailyRecords = dailyRecordLoadResult.records
        monthlyRecordSummaries = dailyRecordLoadResult.monthlySummaries
        persistEditableSettings()

        closeLastObservedDayIfNeeded(now: now)
        ensureClockOutRuntime(for: now)
        rememberObservedSnapshot(now)
        reconcileClockOut(now: now)
        scheduleDayBoundaryTimer(from: now)
    }

    deinit {
        dayBoundaryTask?.cancel()
        clockOutDeadlineTask?.cancel()
    }

    var currentDayStart: Date {
        Self.date(fromDateKey: currentDateKey) ?? DateComponents.calendar.startOfDay(for: WNFClock.now)
    }

    var calculation: WageDay {
        calculation(at: WNFClock.now)
    }

    var liveDay: WageDay {
        liveDay(at: WNFClock.now)
    }

    func calculation(at date: Date) -> WageDay {
        let secondBucket = Int(date.timeIntervalSinceReferenceDate)
        let fingerprint = calculationFingerprint
        if let cache = calculationCache,
           cache.secondBucket == secondBucket,
           cache.fingerprint == fingerprint {
            return cache.day
        }

        let day = calculateWageDay(at: date, settings: currentSettingsSnapshot)
        calculationCache = (fingerprint, secondBucket, day)
        return day
    }

    func liveDay(at date: Date) -> WageDay {
        let secondBucket = Int(date.timeIntervalSinceReferenceDate)
        let fingerprint = liveDayFingerprint
        if let cache = liveDayCache,
           cache.secondBucket == secondBucket,
           cache.fingerprint == fingerprint {
            return cache.day
        }

        let settings = settingsForLiveCalculation(at: date)
        let day = calculateWageDay(at: date, settings: settings)
        guard isPaidWorkday(date, settings: settings) else {
            let off = Self.offDay(from: day)
            liveDayCache = (fingerprint, secondBucket, off)
            return off
        }

        let withOvertime = applyOvertimeIfNeeded(to: day, at: date)
        liveDayCache = (fingerprint, secondBucket, withOvertime)
        return withOvertime
    }

    private func settingsForLiveCalculation(at date: Date) -> WageCalculationSettingsSnapshot {
        var settings = currentSettingsSnapshot
        if Self.dateKey(for: date) == currentDateKey {
            settings.workEndMinute = todayWorkEndMinute
        }
        return settings
    }

    private func applyOvertimeIfNeeded(
        to day: WageDay,
        at date: Date
    ) -> WageDay {
        guard let runtime = clockOutRuntimeState,
              runtime.dateKey == Self.dateKey(for: date)
        else {
            return day
        }

        let startOfDay = Self.date(fromDateKey: runtime.dateKey)
            ?? DateComponents.calendar.startOfDay(for: date)
        let normalEnd = ClockOutRuntimeEngine.workEndDate(
            startOfDay: startOfDay,
            minute: runtime.baseWorkEndMinute
        )
        return WageCalculator.applyingOvertime(
            to: day,
            normalEnd: normalEnd,
            overtimeEnd: runtime.overtimeEnd,
            now: date
        )
    }

    private var liveDayFingerprint: LiveDayFingerprint {
        LiveDayFingerprint(
            monthlySalary: monthlySalary,
            workdaysPerMonth: workdaysPerMonth,
            workStartMinute: workStart.minutesInDay,
            workEndMinute: todayWorkEndMinute,
            lunchStartMinute: lunchStart.minutesInDay,
            lunchEndMinute: lunchEnd.minutesInDay,
            hasLunchBreak: hasLunchBreak,
            selectedWeekdays: selectedWeekdays.sorted(),
            overtimeEnd: clockOutRuntimeState?.overtimeEnd,
            dateKey: clockOutRuntimeState?.dateKey
        )
    }

    private var currentSettingsSnapshot: WageCalculationSettingsSnapshot {
        WageCalculationSettingsSnapshot(
            monthlySalary: monthlySalary,
            workdaysPerMonth: workdaysPerMonth,
            workStartMinute: workStart.minutesInDay,
            workEndMinute: workEnd.minutesInDay,
            lunchStartMinute: lunchStart.minutesInDay,
            lunchEndMinute: lunchEnd.minutesInDay,
            hasLunchBreak: hasLunchBreak,
            selectedWeekdays: selectedWeekdays
        )
    }

    private var calculationFingerprint: CalculationFingerprint {
        CalculationFingerprint(
            monthlySalary: monthlySalary,
            workdaysPerMonth: workdaysPerMonth,
            workStartMinute: workStart.minutesInDay,
            workEndMinute: workEnd.minutesInDay,
            lunchStartMinute: lunchStart.minutesInDay,
            lunchEndMinute: lunchEnd.minutesInDay,
            hasLunchBreak: hasLunchBreak,
            selectedWeekdays: selectedWeekdays.sorted()
        )
    }

    func persistCurrentDaySnapshot() {
        let now = WNFClock.now
        advanceCalendarDay(to: now)
        persistDailySnapshot(for: now, capturedAt: now)
        rememberObservedSnapshot(now)
    }

    func refreshCalendarDayIfNeeded(now: Date = WNFClock.now) {
        advanceCalendarDay(to: now)
        reconcileClockOut(now: now)
        scheduleDayBoundaryTimer(from: now)
    }

    func reconcileClockOut(now: Date = WNFClock.now) {
        advanceCalendarDay(to: now)
        ensureClockOutRuntime(for: now)
        applyTestClockOutSuppressionIfNeeded()
        let nextPhase = derivedClockOutPhase(now: now)
        let previousPhase = clockOutPhase
        if nextPhase != previousPhase {
            clockOutPhase = nextPhase
            if case .decisionDue = nextPhase {
                persistDailySnapshot(for: now, capturedAt: now)
                rememberObservedSnapshot(now)
            }
        }
        scheduleClockOutDeadlineTimer(from: now)
    }

    func dismissClockOutPrompt() {
        guard var runtime = clockOutRuntimeState else { return }
        runtime = ClockOutRuntimeEngine.dismiss(runtime)
        clockOutRuntimeState = runtime
        persistClockOutRuntimeState()
        clockOutPhase = derivedClockOutPhase(now: WNFClock.now)
        scheduleClockOutDeadlineTimer(from: WNFClock.now)
    }

    func beginOvertime(duration: TimeInterval, now: Date = WNFClock.now) {
        reconcileClockOut(now: now)
        guard isTodaySettled == false else { return }
        switch clockOutPhase {
        case .decisionDue, .promptDismissed:
            break
        default:
            return
        }
        guard let runtime = clockOutRuntimeState else { return }

        let startOfDay = currentDayStart
        let remaining = ClockOutRuntimeEngine.remainingOvertimeAllowance(now: now, startOfDay: startOfDay)
        guard remaining > 0, duration > 0 else { return }

        let nextRuntime = ClockOutRuntimeEngine.beginOvertime(
            runtime: runtime,
            duration: duration,
            now: now,
            startOfDay: startOfDay
        )
        clockOutRuntimeState = nextRuntime
        persistClockOutRuntimeState()
        persistDailySnapshot(for: now, capturedAt: now)
        rememberObservedSnapshot(now)
        clockOutPhase = derivedClockOutPhase(now: now)
        scheduleClockOutDeadlineTimer(from: now)
        reconcileOvertimeReminder(deadline: nextRuntime.overtimeEnd)
        Task { @MainActor in
            WNFLiveActivityController.reconcile(state: self, now: now)
        }
    }

    func confirmClockOut(now: Date = WNFClock.now) {
        reconcileClockOut(now: now)
        guard isTodaySettled == false else { return }
        persistDailySnapshot(for: now, capturedAt: now)
        rememberObservedSnapshot(now)
        markTodaySettled()
        reconcileOvertimeReminder(deadline: nil)
        scheduleClockOutDeadlineTimer(from: now)
    }

    func recaptureTodayWorkEndFromSettings() {
        guard var runtime = clockOutRuntimeState,
              runtime.dateKey == currentDateKey,
              runtime.overtimeEnd == nil,
              runtime.revision == 0,
              runtime.dismissedRevision == nil
        else {
            return
        }
        runtime.baseWorkEndMinute = workEnd.minutesInDay
        clockOutRuntimeState = runtime
        persistClockOutRuntimeState()
        reconcileClockOut()
    }

    func jumpTestClockPastDeadline() {
        guard WNFClock.isOverridden else { return }
        let deadline: Date
        switch clockOutPhase {
        case .overtimeRunning(let until, _):
            deadline = until
        case .working:
            deadline = ClockOutRuntimeEngine.workEndDate(
                startOfDay: currentDayStart,
                minute: todayWorkEndMinute
            )
        case .decisionDue(let existing, _), .promptDismissed(let existing, _):
            deadline = existing
        case .settled, .offDay:
            return
        }
        WNFClock.setOverride(deadline.addingTimeInterval(0.001))
        reconcileClockOut(now: WNFClock.now)
    }

    func pauseCalendarDayTimer() {
        dayBoundaryTask?.cancel()
        dayBoundaryTask = nil
        clockOutDeadlineTask?.cancel()
        clockOutDeadlineTask = nil
    }

    func resumeCalendarDayTimer(now: Date = WNFClock.now) {
        refreshCalendarDayIfNeeded(now: now)
    }

    func adjustMonthlySalary(by delta: Double) {
        setMonthlySalary(monthlySalary + delta)
    }

    func setMonthlySalary(_ value: Double) {
        monthlySalary = Self.clampedMonthlySalary(value)
    }

    func setMonthlySalary(from text: String) {
        guard let value = Double(text.numericCharactersOnly) else { return }
        setMonthlySalary(value)
    }

    func adjustWorkdaysPerMonth(by delta: Int) {
        setWorkdaysPerMonth(workdaysPerMonth + delta)
    }

    func setWorkdaysPerMonth(_ value: Int) {
        workdaysPerMonth = Self.clampedWorkdaysPerMonth(value)
    }

    func setWorkdaysPerMonth(from text: String) {
        guard let value = Int(text.numericCharactersOnly) else { return }
        setWorkdaysPerMonth(value)
    }

    func setWorkStart(_ components: DateComponents) {
        var startMinute = clampedMinuteInDay(components.minutesInDay)
        if startMinute >= workEnd.minutesInDay {
            if startMinute >= Self.lastMinuteInDay {
                startMinute = Self.lastMinuteInDay - 1
            }
            workEnd = DateComponents.minuteInDay(startMinute + 1)
        }
        workStart = DateComponents.minuteInDay(startMinute)
    }

    func setWorkEnd(_ components: DateComponents) {
        var endMinute = clampedMinuteInDay(components.minutesInDay)
        if endMinute <= workStart.minutesInDay {
            if endMinute <= 0 {
                endMinute = 1
            }
            workStart = DateComponents.minuteInDay(endMinute - 1)
        }
        workEnd = DateComponents.minuteInDay(endMinute)
    }

    func toggleWeekday(_ index: Int) {
        guard (0...6).contains(index) else { return }
        var nextWeekdays = selectedWeekdays
        if nextWeekdays.contains(index) {
            nextWeekdays.remove(index)
        } else {
            nextWeekdays.insert(index)
        }
        selectedWeekdays = nextWeekdays
    }

    private static func clampedMonthlySalary(_ value: Double) -> Double {
        min(max(value, 0), 100_000)
    }

    private static func clampedWorkdaysPerMonth(_ value: Int) -> Int {
        min(max(value, 1), 31)
    }

    private static let lastMinuteInDay = 23 * 60 + 59

    private func clampedMinuteInDay(_ value: Int) -> Int {
        min(max(value, 0), Self.lastMinuteInDay)
    }

    private func recordCalculationSettingsChanged() {
        let now = WNFClock.now
        advanceCalendarDay(to: now)
        rememberObservedSnapshot(now)
        reconcileClockOut(now: now)
    }

    private func advanceCalendarDay(to newDate: Date) {
        let newDateKey = Self.dateKey(for: newDate)
        guard newDateKey != currentDateKey else { return }

        let settings = lastObservedSnapshotForClosure()?.settings ?? currentSettingsSnapshot
        closeObservedDateRange(from: currentDayStart, to: newDate, capturedAt: newDate, settings: settings)
        currentDateKey = newDateKey
        clockOutRuntimeState = nil
        persistClockOutRuntimeState()
        ensureClockOutRuntime(for: newDate)
        rememberObservedSnapshot(newDate)
        clockOutPhase = derivedClockOutPhase(now: newDate)
    }

    private func scheduleDayBoundaryTimer(from date: Date) {
        dayBoundaryTask?.cancel()

        let calendar = DateComponents.calendar
        let startOfDay = calendar.startOfDay(for: date)
        let nextBoundary = calendar.date(byAdding: DateComponents(day: 1, second: 1), to: startOfDay)
            ?? date.addingTimeInterval(86_401)
        let delay = max(0, nextBoundary.timeIntervalSinceNow)

        dayBoundaryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refreshCalendarDayIfNeeded(now: WNFClock.now)
        }
    }

    private func closeLastObservedDayIfNeeded(now: Date) {
        guard let lastObservedSnapshot = lastObservedSnapshotForClosure(),
              lastObservedSnapshot.dateKey != Self.dateKey(for: now),
              let lastObservedDate = Self.date(fromDateKey: lastObservedSnapshot.dateKey)
        else {
            return
        }

        closeObservedDateRange(
            from: lastObservedDate,
            to: now,
            capturedAt: now,
            settings: lastObservedSnapshot.settings
        )
    }

    private func closeObservedDateRange(
        from lastObservedDate: Date,
        to now: Date,
        capturedAt: Date,
        settings: WageCalculationSettingsSnapshot
    ) {
        let calendar = DateComponents.calendar
        let lastObservedStart = calendar.startOfDay(for: lastObservedDate)
        let todayStart = calendar.startOfDay(for: now)
        guard lastObservedStart < todayStart else { return }

        var nextRecords = dailyRecords
        var recordsToWrite: [DailyWageRecord] = []

        let closedLastObservedRecord = makeDailyRecord(
            for: Self.endOfDay(for: lastObservedStart),
            capturedAt: capturedAt,
            source: .observed,
            settings: settings
        )
        nextRecords[closedLastObservedRecord.dateKey] = closedLastObservedRecord
        recordsToWrite.append(closedLastObservedRecord)

        var cursor = calendar.date(byAdding: .day, value: 1, to: lastObservedStart)
        while let date = cursor, date < todayStart {
            let dateKey = Self.dateKey(for: date)
            if nextRecords[dateKey] == nil {
                let record = makeBackfilledDailyRecord(for: date, capturedAt: capturedAt, settings: settings)
                nextRecords[record.dateKey] = record
                recordsToWrite.append(record)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: date)
        }

        persistDailyRecords(recordsToWrite, now: capturedAt)
    }

    private func persistDailySnapshot(for date: Date, capturedAt: Date) {
        let record = makeDailyRecord(
            for: date,
            capturedAt: capturedAt,
            source: .observed,
            settings: currentSettingsSnapshot
        )
        persistDailyRecords([record], now: capturedAt)
    }

    private func persistDailyRecords(_ records: [DailyWageRecord], now: Date) {
        guard records.isEmpty == false else { return }
        let result = dailyRecordStore.upsert(records, now: now)
        applyDailyRecordLoadResult(result)
    }

    private func applyDailyRecordLoadResult(_ result: DailyRecordLoadResult) {
        dailyRecords = result.records
        monthlyRecordSummaries = result.monthlySummaries
        recordsRevision += 1
    }

    private func makeBackfilledDailyRecord(
        for date: Date,
        capturedAt: Date,
        settings: WageCalculationSettingsSnapshot
    ) -> DailyWageRecord {
        makeDailyRecord(
            for: Self.endOfDay(for: date),
            capturedAt: capturedAt,
            source: .backfilled,
            settings: settings
        )
    }

    private func makeDailyRecord(
        for date: Date,
        capturedAt: Date,
        source: DailyRecordSource,
        settings: WageCalculationSettingsSnapshot
    ) -> DailyWageRecord {
        var recordSettings = settings
        let dateKey = Self.dateKey(for: date)
        if let runtime = clockOutRuntimeState, runtime.dateKey == dateKey {
            recordSettings.workEndMinute = runtime.baseWorkEndMinute
        }

        var day = calculateWageDay(at: date, settings: recordSettings)
        if isPaidWorkday(date, settings: recordSettings) {
            day = applyOvertimeIfNeeded(to: day, at: date)
        } else {
            return DailyWageRecord(
                dateKey: dateKey,
                earnedToday: 0,
                targetToday: 0,
                elapsedPaidSeconds: 0,
                workdayMinutes: day.workdayMinutes,
                hourlyRate: day.hourlyRate,
                monthlySalary: recordSettings.monthlySalary,
                workdaysPerMonth: recordSettings.workdaysPerMonth,
                capturedAt: capturedAt,
                source: source
            )
        }

        return DailyWageRecord(
            dateKey: dateKey,
            earnedToday: day.earnedToday,
            targetToday: day.targetToday,
            elapsedPaidSeconds: day.elapsedPaidSeconds,
            workdayMinutes: day.workdayMinutes,
            hourlyRate: day.hourlyRate,
            monthlySalary: recordSettings.monthlySalary,
            workdaysPerMonth: recordSettings.workdaysPerMonth,
            capturedAt: capturedAt,
            source: source,
            overtimeSeconds: day.overtimeSeconds,
            overtimeEarned: day.overtimeEarned
        )
    }

    private func calculateWageDay(at date: Date, settings: WageCalculationSettingsSnapshot) -> WageDay {
        let currentTime = DateComponents.calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return WageCalculator.compute(
            monthlySalary: settings.monthlySalary,
            workdaysPerMonth: settings.workdaysPerMonth,
            workStart: settings.workStart,
            workEnd: settings.workEnd,
            lunchStart: settings.lunchStart,
            lunchEnd: settings.lunchEnd,
            hasLunchBreak: settings.hasLunchBreak,
            now: currentTime
        )
    }

    private func isPaidWorkday(_ date: Date, settings: WageCalculationSettingsSnapshot) -> Bool {
        settings.selectedWeekdaySet.contains(Self.weekdayIndex(for: date))
    }

    private static func offDay(from day: WageDay) -> WageDay {
        WageDay(
            startMinute: day.startMinute,
            endMinute: day.endMinute,
            lunchStartMinute: day.lunchStartMinute,
            lunchEndMinute: day.lunchEndMinute,
            workdayMinutes: day.workdayMinutes,
            hourlyRate: day.hourlyRate,
            elapsedPaidMinutes: 0,
            elapsedPaidSeconds: 0,
            earnedToday: 0,
            targetToday: 0,
            status: .off,
            wallToEndMinutes: 0
        )
    }

    private func persistEditableSettings() {
        userDefaults.set(monthlySalary, forKey: StorageKey.monthlySalary)
        userDefaults.set(workdaysPerMonth, forKey: StorageKey.workdaysPerMonth)
        userDefaults.set(workStart.minutesInDay, forKey: StorageKey.workStartMinute)
        userDefaults.set(workEnd.minutesInDay, forKey: StorageKey.workEndMinute)
        userDefaults.set(lunchStart.minutesInDay, forKey: StorageKey.lunchStartMinute)
        userDefaults.set(lunchEnd.minutesInDay, forKey: StorageKey.lunchEndMinute)
        userDefaults.set(hasLunchBreak, forKey: StorageKey.hasLunchBreak)
        userDefaults.set(privacyMode, forKey: StorageKey.privacyMode)
        userDefaults.set(selectedWeekdays.sorted(), forKey: StorageKey.selectedWeekdays)
        userDefaults.set(clockOutReminderEnabled, forKey: StorageKey.clockOutReminderEnabled)
        userDefaults.set(liveActivityEnabled, forKey: StorageKey.liveActivityEnabled)
    }

    func reconcileClockOutReminder() {
        let enabled = clockOutReminderEnabled
        let workEnd = workEnd
        let selectedWeekdays = selectedWeekdays
        Task { @MainActor in
            await ClockOutReminderService.shared.reconcile(
                enabled: enabled,
                workEnd: workEnd,
                selectedWeekdays: selectedWeekdays
            )
        }
    }

    private func reconcileOvertimeReminder(deadline: Date?) {
        Task { @MainActor in
            await ClockOutReminderService.shared.reconcileOvertimeDeadline(deadline)
        }
    }

    private func derivedClockOutPhase(now: Date) -> ClockOutPhase {
        ClockOutRuntimeEngine.phase(
            isPaidWorkday: isPaidWorkday(now, settings: currentSettingsSnapshot),
            isSettled: lastSettlementDateKey == Self.dateKey(for: now),
            runtime: clockOutRuntimeState,
            now: now,
            startOfDay: DateComponents.calendar.startOfDay(for: now)
        )
    }

    private func ensureClockOutRuntime(for now: Date) {
        let dateKey = Self.dateKey(for: now)
        if let runtime = clockOutRuntimeState, runtime.dateKey == dateKey {
            return
        }

        if isPaidWorkday(now, settings: currentSettingsSnapshot) {
            clockOutRuntimeState = ClockOutRuntimeEngine.makeTodaySnapshot(
                dateKey: dateKey,
                workEndMinute: workEnd.minutesInDay
            )
        } else {
            clockOutRuntimeState = nil
        }
        persistClockOutRuntimeState()
    }

    private func applyTestClockOutSuppressionIfNeeded() {
        guard WNFClock.shouldSuppressClockOutPrompt(),
              var runtime = clockOutRuntimeState,
              runtime.dismissedRevision != runtime.revision
        else {
            return
        }
        runtime.dismissedRevision = runtime.revision
        clockOutRuntimeState = runtime
    }

    private func persistClockOutRuntimeState() {
        if let runtime = clockOutRuntimeState,
           let data = try? JSONEncoder().encode(runtime) {
            userDefaults.set(data, forKey: StorageKey.clockOutRuntimeState)
        } else {
            userDefaults.removeObject(forKey: StorageKey.clockOutRuntimeState)
        }
    }

    private static func decodeClockOutRuntimeState(from userDefaults: UserDefaults) -> ClockOutRuntimeState? {
        guard let data = userDefaults.data(forKey: StorageKey.clockOutRuntimeState) else {
            return nil
        }
        return try? JSONDecoder().decode(ClockOutRuntimeState.self, from: data)
    }

    private func scheduleClockOutDeadlineTimer(from date: Date) {
        clockOutDeadlineTask?.cancel()
        clockOutDeadlineTask = nil
        guard WNFClock.isOverridden == false else { return }

        let fireDate: Date?
        switch clockOutPhase {
        case .working:
            fireDate = ClockOutRuntimeEngine.workEndDate(
                startOfDay: DateComponents.calendar.startOfDay(for: date),
                minute: todayWorkEndMinute
            )
        case .overtimeRunning(let until, _):
            fireDate = until
        default:
            fireDate = nil
        }
        guard let fireDate, fireDate > date else { return }

        let delay = WNFClock.isOverridden ? fireDate.timeIntervalSince(WNFClock.now) : fireDate.timeIntervalSince(Date())
        guard delay > 0 else {
            clockOutPhase = derivedClockOutPhase(now: WNFClock.now)
            return
        }

        clockOutDeadlineTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.reconcileClockOut(now: WNFClock.now)
        }
    }

    private func rememberObservedSnapshot(_ date: Date) {
        let snapshot = LastObservedSnapshot(
            dateKey: Self.dateKey(for: date),
            settings: currentSettingsSnapshot
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: StorageKey.lastObservedSnapshot)
        }
        userDefaults.set(snapshot.dateKey, forKey: StorageKey.lastObservedDateKey)
    }

    private func lastObservedSnapshotForClosure() -> LastObservedSnapshot? {
        let mirroredDateKey = userDefaults.string(forKey: StorageKey.lastObservedDateKey)
        if let data = userDefaults.data(forKey: StorageKey.lastObservedSnapshot),
           let snapshot = try? JSONDecoder().decode(LastObservedSnapshot.self, from: data),
           Self.date(fromDateKey: snapshot.dateKey) != nil,
           mirroredDateKey == nil || mirroredDateKey == snapshot.dateKey {
            return snapshot
        }

        guard let dateKey = mirroredDateKey,
              Self.date(fromDateKey: dateKey) != nil
        else {
            return nil
        }

        return LastObservedSnapshot(dateKey: dateKey, settings: currentSettingsSnapshot)
    }

    nonisolated static func dateKey(for date: Date) -> String {
        let components = DateComponents.calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    nonisolated static func date(fromDateKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    nonisolated private static func endOfDay(for date: Date) -> Date {
        let startOfDay = DateComponents.calendar.startOfDay(for: date)
        return DateComponents.calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? date
    }

    nonisolated private static func weekdayIndex(for date: Date) -> Int {
        let weekday = DateComponents.calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }
}

struct LastObservedSnapshot: Codable, Equatable {
    var dateKey: String
    var settings: WageCalculationSettingsSnapshot
}

struct WageCalculationSettingsSnapshot: Codable, Equatable {
    var monthlySalary: Double
    var workdaysPerMonth: Int
    var workStartMinute: Int
    var workEndMinute: Int
    var lunchStartMinute: Int
    var lunchEndMinute: Int
    var hasLunchBreak: Bool
    var selectedWeekdays: [Int]

    init(
        monthlySalary: Double,
        workdaysPerMonth: Int,
        workStartMinute: Int,
        workEndMinute: Int,
        lunchStartMinute: Int,
        lunchEndMinute: Int,
        hasLunchBreak: Bool,
        selectedWeekdays: Set<Int>
    ) {
        self.monthlySalary = monthlySalary
        self.workdaysPerMonth = workdaysPerMonth
        self.workStartMinute = workStartMinute
        self.workEndMinute = workEndMinute
        self.lunchStartMinute = lunchStartMinute
        self.lunchEndMinute = lunchEndMinute
        self.hasLunchBreak = hasLunchBreak
        self.selectedWeekdays = selectedWeekdays
            .filter { (0...6).contains($0) }
            .sorted()
    }

    var workStart: DateComponents {
        .minuteInDay(workStartMinute)
    }

    var workEnd: DateComponents {
        .minuteInDay(workEndMinute)
    }

    var lunchStart: DateComponents {
        .minuteInDay(lunchStartMinute)
    }

    var lunchEnd: DateComponents {
        .minuteInDay(lunchEndMinute)
    }

    var selectedWeekdaySet: Set<Int> {
        Set(selectedWeekdays)
    }
}

private struct CalculationFingerprint: Equatable {
    let monthlySalary: Double
    let workdaysPerMonth: Int
    let workStartMinute: Int
    let workEndMinute: Int
    let lunchStartMinute: Int
    let lunchEndMinute: Int
    let hasLunchBreak: Bool
    let selectedWeekdays: [Int]
}

private struct LiveDayFingerprint: Equatable {
    let monthlySalary: Double
    let workdaysPerMonth: Int
    let workStartMinute: Int
    let workEndMinute: Int
    let lunchStartMinute: Int
    let lunchEndMinute: Int
    let hasLunchBreak: Bool
    let selectedWeekdays: [Int]
    let overtimeEnd: Date?
    let dateKey: String?
}

private enum Default {
    static let monthlySalary: Double = 18_000
    static let workdaysPerMonth = 26
    static let workStartMinute = 9 * 60 + 30
    static let workEndMinute = 18 * 60 + 30
    static let lunchStartMinute = 12 * 60
    static let lunchEndMinute = 13 * 60
    static let hasLunchBreak = true
    static let privacyMode = false
    static let selectedWeekdays: Set<Int> = [0, 1, 2, 3, 4]
    static let clockOutReminderEnabled = false
    static let liveActivityEnabled = true
}

private extension UserDefaults {
    func doubleValue(forKey key: String) -> Double? {
        object(forKey: key) == nil ? nil : double(forKey: key)
    }

    func integerValue(forKey key: String) -> Int? {
        object(forKey: key) == nil ? nil : integer(forKey: key)
    }

    func boolValue(forKey key: String) -> Bool? {
        object(forKey: key) == nil ? nil : bool(forKey: key)
    }

    func weekdaySet(forKey key: String) -> Set<Int>? {
        guard object(forKey: key) != nil else { return nil }
        let weekdays = (array(forKey: key) as? [Int] ?? []).filter { (0...6).contains($0) }
        return Set(weekdays)
    }
}

private extension String {
    var numericCharactersOnly: String {
        filter(\.isNumber)
    }
}
