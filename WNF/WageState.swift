import Foundation

final class WageState: ObservableObject {
    @Published var monthlySalary: Double {
        didSet {
            userDefaults.set(monthlySalary, forKey: StorageKey.monthlySalary)
        }
    }

    @Published var workdaysPerMonth: Int {
        didSet {
            userDefaults.set(workdaysPerMonth, forKey: StorageKey.workdaysPerMonth)
        }
    }

    @Published var workStart: DateComponents {
        didSet {
            // The app does not model overnight shifts: the workday must be a
            // forward interval within a single calendar day. Reject a start that
            // would meet or cross the end and snap back to the last valid value,
            // otherwise `endMinute - startMinute` goes non-positive and the hourly
            // rate explodes via the `max(1, …)` floor in WageCalculator (E-2).
            guard workStart.minutesInDay < workEnd.minutesInDay else {
                workStart = oldValue
                return
            }
            userDefaults.set(workStart.minutesInDay, forKey: StorageKey.workStartMinute)
        }
    }

    @Published var workEnd: DateComponents {
        didSet {
            // Symmetric guard to `workStart`: the end must stay strictly after the
            // start (no overnight shifts). Roll back an invalid edit before it can
            // poison the wage calculation (E-2).
            guard workEnd.minutesInDay > workStart.minutesInDay else {
                workEnd = oldValue
                return
            }
            userDefaults.set(workEnd.minutesInDay, forKey: StorageKey.workEndMinute)
            reconcileClockOutReminder()
        }
    }

    @Published var lunchStart: DateComponents {
        didSet {
            userDefaults.set(lunchStart.minutesInDay, forKey: StorageKey.lunchStartMinute)
        }
    }

    @Published var lunchEnd: DateComponents {
        didSet {
            userDefaults.set(lunchEnd.minutesInDay, forKey: StorageKey.lunchEndMinute)
        }
    }

    @Published var hasLunchBreak: Bool {
        didSet {
            userDefaults.set(hasLunchBreak, forKey: StorageKey.hasLunchBreak)
        }
    }

    @Published var includeOvertime: Bool {
        didSet {
            userDefaults.set(includeOvertime, forKey: StorageKey.includeOvertime)
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
            reconcileClockOutReminder()
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

    /// `true` when the user has explicitly completed (or saved) today's settlement.
    /// Used by Home to switch into the lightweight "personal time" presentation.
    /// Naturally resets when `currentDateKey` advances past the stored date.
    var isTodaySettled: Bool {
        lastSettlementDateKey == currentDateKey
    }

    func markTodaySettled() {
        lastSettlementDateKey = currentDateKey
    }

    let userDefaults: UserDefaults
    var dailyRecordStorageMode: DailyRecordStorageMode
    private var dayBoundaryTimer: Timer?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        monthlySalary = Self.clampedMonthlySalary(userDefaults.doubleValue(forKey: StorageKey.monthlySalary) ?? Default.monthlySalary)
        workdaysPerMonth = Self.clampedWorkdaysPerMonth(userDefaults.integerValue(forKey: StorageKey.workdaysPerMonth) ?? Default.workdaysPerMonth)
        // Repair any overnight/degenerate window persisted by an older build before
        // the ordering guards existed; otherwise the bad value survives launch and
        // the hourly rate stays broken (E-2). Normalizing the loaded minutes keeps
        // the guards' invariant true from the first frame.
        let workWindow = Self.normalizedWorkWindow(
            start: userDefaults.integerValue(forKey: StorageKey.workStartMinute) ?? Default.workStartMinute,
            end: userDefaults.integerValue(forKey: StorageKey.workEndMinute) ?? Default.workEndMinute
        )
        workStart = DateComponents.minuteInDay(workWindow.start)
        workEnd = DateComponents.minuteInDay(workWindow.end)
        lunchStart = DateComponents.minuteInDay(userDefaults.integerValue(forKey: StorageKey.lunchStartMinute) ?? Default.lunchStartMinute)
        lunchEnd = DateComponents.minuteInDay(userDefaults.integerValue(forKey: StorageKey.lunchEndMinute) ?? Default.lunchEndMinute)
        hasLunchBreak = userDefaults.boolValue(forKey: StorageKey.hasLunchBreak) ?? Default.hasLunchBreak
        includeOvertime = userDefaults.boolValue(forKey: StorageKey.includeOvertime) ?? Default.includeOvertime
        privacyMode = userDefaults.boolValue(forKey: StorageKey.privacyMode) ?? Default.privacyMode
        // An empty set would make every day unpaid; treat persisted emptiness (from
        // data predating the "keep at least one day" guard) as "use the default". (E-3)
        let loadedWeekdays = userDefaults.weekdaySet(forKey: StorageKey.selectedWeekdays) ?? Default.selectedWeekdays
        selectedWeekdays = loadedWeekdays.isEmpty ? Default.selectedWeekdays : loadedWeekdays
        clockOutReminderEnabled = userDefaults.boolValue(forKey: StorageKey.clockOutReminderEnabled) ?? Default.clockOutReminderEnabled
        lastSettlementDateKey = userDefaults.string(forKey: StorageKey.lastSettlementDateKey)
        let now = Date()
        currentDateKey = Self.dateKey(for: now)
        let dailyRecordLoadResult = Self.loadDailyRecords(from: userDefaults)
        dailyRecords = dailyRecordLoadResult.records
        dailyRecordStorageMode = dailyRecordLoadResult.storageMode
        persistEditableSettings()

        closeLastObservedDayIfNeeded(now: now)
        rememberObservedDate(now)
        scheduleDayBoundaryTimer(from: now)
    }

    deinit {
        dayBoundaryTimer?.invalidate()
    }

    var currentDayStart: Date {
        Self.date(fromDateKey: currentDateKey) ?? DateComponents.calendar.startOfDay(for: Date())
    }

    var calculation: WageDay {
        calculation(at: Date())
    }

    func calculation(at date: Date) -> WageDay {
        let currentTime = DateComponents.calendar.dateComponents([.hour, .minute, .second], from: date)
        return WageCalculator.compute(
            monthlySalary: monthlySalary,
            workdaysPerMonth: workdaysPerMonth,
            workStart: workStart,
            workEnd: workEnd,
            lunchStart: lunchStart,
            lunchEnd: lunchEnd,
            hasLunchBreak: hasLunchBreak,
            includeOvertime: includeOvertime,
            now: currentTime
        )
    }

    func dailyRecord(for date: Date, includingLiveToday: Bool = false) -> DailyWageRecord? {
        let dateKey = Self.dateKey(for: date)
        if includingLiveToday, dateKey == currentDateKey {
            let now = Date()
            return makeDailyRecord(for: now, capturedAt: now, source: .observed)
        }

        return dailyRecords[dateKey]
    }

    func persistCurrentDaySnapshot() {
        let now = Date()
        advanceCalendarDay(to: now)
        persistDailySnapshot(for: now, capturedAt: now)
        rememberObservedDate(now)
    }

    func refreshCalendarDayIfNeeded(now: Date = Date()) {
        advanceCalendarDay(to: now)
        scheduleDayBoundaryTimer(from: now)
    }

    func pauseCalendarDayTimer() {
        dayBoundaryTimer?.invalidate()
        dayBoundaryTimer = nil
    }

    func resumeCalendarDayTimer(now: Date = Date()) {
        refreshCalendarDayIfNeeded(now: now)
    }

    func bindingForTime(_ keyPath: ReferenceWritableKeyPath<WageState, DateComponents>) -> Date {
        DateComponents.calendar.date(from: self[keyPath: keyPath]) ?? .now
    }

    func updateTime(_ keyPath: ReferenceWritableKeyPath<WageState, DateComponents>, date: Date) {
        self[keyPath: keyPath] = DateComponents.calendar.dateComponents([.hour, .minute], from: date)
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

    func toggleWeekday(_ index: Int) {
        guard (0...6).contains(index) else { return }
        var nextWeekdays = selectedWeekdays
        if nextWeekdays.contains(index) {
            // Always keep at least one workday selected; an empty set makes every
            // day unpaid and the whole app reads zero (E-3).
            guard nextWeekdays.count > 1 else { return }
            nextWeekdays.remove(index)
        } else {
            nextWeekdays.insert(index)
        }
        selectedWeekdays = nextWeekdays
    }

    /// Returns a work window guaranteed to be a forward, same-day interval. A
    /// non-positive span (overnight or inverted, e.g. start 20:00 / end 08:00)
    /// is replaced wholesale with the default day rather than partially repaired,
    /// so the user lands on a sane, obviously-default configuration. (E-2)
    private static func normalizedWorkWindow(start: Int, end: Int) -> (start: Int, end: Int) {
        end > start ? (start, end) : (Default.workStartMinute, Default.workEndMinute)
    }

    private static func clampedMonthlySalary(_ value: Double) -> Double {
        min(max(value, 0), 100_000)
    }

    private static func clampedWorkdaysPerMonth(_ value: Int) -> Int {
        min(max(value, 1), 31)
    }

    private func advanceCalendarDay(to newDate: Date) {
        let newDateKey = Self.dateKey(for: newDate)
        guard newDateKey != currentDateKey else { return }

        closeObservedDateRange(from: currentDayStart, to: newDate, capturedAt: newDate)
        currentDateKey = newDateKey
        rememberObservedDate(newDate)
    }

    private func scheduleDayBoundaryTimer(from date: Date) {
        dayBoundaryTimer?.invalidate()

        let calendar = DateComponents.calendar
        let startOfDay = calendar.startOfDay(for: date)
        let nextBoundary = calendar.date(byAdding: DateComponents(day: 1, second: 1), to: startOfDay)
            ?? date.addingTimeInterval(86_401)
        let timer = Timer(fire: nextBoundary, interval: 0, repeats: false) { [weak self] _ in
            self?.refreshCalendarDayIfNeeded(now: Date())
        }
        RunLoop.main.add(timer, forMode: .common)
        dayBoundaryTimer = timer
    }

    private func closeLastObservedDayIfNeeded(now: Date) {
        guard let lastObservedDateKey = userDefaults.string(forKey: StorageKey.lastObservedDateKey),
              lastObservedDateKey != Self.dateKey(for: now),
              let lastObservedDate = Self.date(fromDateKey: lastObservedDateKey)
        else {
            return
        }

        closeObservedDateRange(from: lastObservedDate, to: now, capturedAt: now)
    }

    private func closeObservedDateRange(from lastObservedDate: Date, to now: Date, capturedAt: Date) {
        let calendar = DateComponents.calendar
        let lastObservedStart = calendar.startOfDay(for: lastObservedDate)
        let todayStart = calendar.startOfDay(for: now)
        guard lastObservedStart < todayStart else { return }

        var nextRecords = dailyRecords

        let closedLastObservedRecord = makeDailyRecord(
            for: Self.endOfDay(for: lastObservedStart),
            capturedAt: capturedAt,
            source: .observed
        )
        nextRecords[closedLastObservedRecord.dateKey] = closedLastObservedRecord

        // Bound how far back we synthesize `.backfilled` records. If the system
        // clock jumps forward by months or years (debugging, timezone tricks, or a
        // manual date change), an unbounded loop would insert thousands of records
        // and force a full-dictionary reserialize on every save (E-4). We only ever
        // backfill the most recent `maxBackfillDays`; the genuine last-observed day
        // is still closed above, and older gaps simply stay unrecorded.
        let maxBackfillDays = 31
        let earliestBackfillStart = calendar.date(byAdding: .day, value: -maxBackfillDays, to: todayStart) ?? lastObservedStart
        let backfillFromStart = max(lastObservedStart, earliestBackfillStart)

        var cursor = calendar.date(byAdding: .day, value: 1, to: backfillFromStart)
        while let date = cursor, date < todayStart {
            let dateKey = Self.dateKey(for: date)
            if nextRecords[dateKey] == nil {
                let record = makeBackfilledDailyRecord(for: date, capturedAt: capturedAt)
                nextRecords[record.dateKey] = record
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: date)
        }

        replaceDailyRecords(nextRecords)
        saveDailyRecords()
    }

    private func persistDailySnapshot(for date: Date, capturedAt: Date) {
        let record = makeDailyRecord(for: date, capturedAt: capturedAt, source: .observed)
        var nextRecords = dailyRecords
        nextRecords[record.dateKey] = record
        replaceDailyRecords(nextRecords)
        saveDailyRecords()
    }

    /// INVARIANT: this is the only path allowed to mutate `dailyRecords` after the
    /// initial load in `init`, and it MUST bump `recordsRevision` on every change.
    /// `RecordAggregationInput.==` intentionally ignores the `dailyRecords` payload
    /// and keys its cache off `recordsRevision` alone — any write that bypasses this
    /// method leaves the revision stale and serves the aggregation cache outdated
    /// data (E-6). The `dailyRecords` setter is `private(set)` to keep this honest;
    /// do not add a second write path.
    private func replaceDailyRecords(_ records: [String: DailyWageRecord]) {
        dailyRecords = records
        recordsRevision += 1
    }

    /// Synthesizes a record for a day the app never observed live. Note that
    /// `calculation(at:)` reads the *current* salary settings, so the amount reflects
    /// today's pay rate applied to that past date — see the capture-semantics note on
    /// `DailyWageRecord` (E-5).
    private func makeBackfilledDailyRecord(for date: Date, capturedAt: Date) -> DailyWageRecord {
        makeDailyRecord(for: Self.endOfDay(for: date), capturedAt: capturedAt, source: .backfilled)
    }

    private func makeDailyRecord(for date: Date, capturedAt: Date, source: DailyRecordSource) -> DailyWageRecord {
        let day = calculation(at: date)
        guard isPaidWorkday(date) else {
            return DailyWageRecord(
                dateKey: Self.dateKey(for: date),
                earnedToday: 0,
                targetToday: 0,
                elapsedPaidSeconds: 0,
                workdayMinutes: day.workdayMinutes,
                hourlyRate: day.hourlyRate,
                monthlySalary: monthlySalary,
                workdaysPerMonth: workdaysPerMonth,
                capturedAt: capturedAt,
                source: source
            )
        }

        return DailyWageRecord(
            dateKey: Self.dateKey(for: date),
            earnedToday: day.earnedToday,
            targetToday: day.targetToday,
            elapsedPaidSeconds: day.elapsedPaidSeconds,
            workdayMinutes: day.workdayMinutes,
            hourlyRate: day.hourlyRate,
            monthlySalary: monthlySalary,
            workdaysPerMonth: workdaysPerMonth,
            capturedAt: capturedAt,
            source: source
        )
    }

    private func isPaidWorkday(_ date: Date) -> Bool {
        selectedWeekdays.contains(Self.weekdayIndex(for: date))
    }

    private func persistEditableSettings() {
        userDefaults.set(monthlySalary, forKey: StorageKey.monthlySalary)
        userDefaults.set(workdaysPerMonth, forKey: StorageKey.workdaysPerMonth)
        userDefaults.set(workStart.minutesInDay, forKey: StorageKey.workStartMinute)
        userDefaults.set(workEnd.minutesInDay, forKey: StorageKey.workEndMinute)
        userDefaults.set(lunchStart.minutesInDay, forKey: StorageKey.lunchStartMinute)
        userDefaults.set(lunchEnd.minutesInDay, forKey: StorageKey.lunchEndMinute)
        userDefaults.set(hasLunchBreak, forKey: StorageKey.hasLunchBreak)
        userDefaults.set(includeOvertime, forKey: StorageKey.includeOvertime)
        userDefaults.set(privacyMode, forKey: StorageKey.privacyMode)
        userDefaults.set(selectedWeekdays.sorted(), forKey: StorageKey.selectedWeekdays)
        userDefaults.set(clockOutReminderEnabled, forKey: StorageKey.clockOutReminderEnabled)
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

    private func rememberObservedDate(_ date: Date) {
        userDefaults.set(Self.dateKey(for: date), forKey: StorageKey.lastObservedDateKey)
    }

    static func dateKey(for date: Date) -> String {
        let components = DateComponents.calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(fromDateKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func endOfDay(for date: Date) -> Date {
        let startOfDay = DateComponents.calendar.startOfDay(for: date)
        return DateComponents.calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? date
    }

    private static func weekdayIndex(for date: Date) -> Int {
        let weekday = DateComponents.calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }
}

private enum Default {
    static let monthlySalary: Double = 18_000
    static let workdaysPerMonth = 26
    static let workStartMinute = 9 * 60 + 30
    static let workEndMinute = 18 * 60 + 30
    static let lunchStartMinute = 12 * 60
    static let lunchEndMinute = 13 * 60
    static let hasLunchBreak = true
    static let includeOvertime = true
    static let privacyMode = false
    static let selectedWeekdays: Set<Int> = [0, 1, 2, 3, 4]
    static let clockOutReminderEnabled = false
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
