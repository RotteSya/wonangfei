import Foundation

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

    @Published var includeOvertime: Bool {
        didSet {
            userDefaults.set(includeOvertime, forKey: StorageKey.includeOvertime)
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

    /// Cached result of the most recent `calculation(at:)` call. Keyed by the
    /// settings fingerprint (everything `WageCalculator` reads from `self`) and
    /// the second-precision bucket of the input date. Repeated reads from
    /// SettingsView, RecordsView, widget snapshot, etc. within the same second
    /// hit this cache instead of re-running the calendar component extraction
    /// and the compute step.
    private var calculationCache: (fingerprint: CalculationFingerprint, secondBucket: Int, day: WageDay)?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        monthlySalary = Self.clampedMonthlySalary(userDefaults.doubleValue(forKey: StorageKey.monthlySalary) ?? Default.monthlySalary)
        workdaysPerMonth = Self.clampedWorkdaysPerMonth(userDefaults.integerValue(forKey: StorageKey.workdaysPerMonth) ?? Default.workdaysPerMonth)
        workStart = DateComponents.minuteInDay(userDefaults.integerValue(forKey: StorageKey.workStartMinute) ?? Default.workStartMinute)
        workEnd = DateComponents.minuteInDay(userDefaults.integerValue(forKey: StorageKey.workEndMinute) ?? Default.workEndMinute)
        lunchStart = DateComponents.minuteInDay(userDefaults.integerValue(forKey: StorageKey.lunchStartMinute) ?? Default.lunchStartMinute)
        lunchEnd = DateComponents.minuteInDay(userDefaults.integerValue(forKey: StorageKey.lunchEndMinute) ?? Default.lunchEndMinute)
        hasLunchBreak = userDefaults.boolValue(forKey: StorageKey.hasLunchBreak) ?? Default.hasLunchBreak
        includeOvertime = userDefaults.boolValue(forKey: StorageKey.includeOvertime) ?? Default.includeOvertime
        privacyMode = userDefaults.boolValue(forKey: StorageKey.privacyMode) ?? Default.privacyMode
        selectedWeekdays = userDefaults.weekdaySet(forKey: StorageKey.selectedWeekdays) ?? Default.selectedWeekdays
        clockOutReminderEnabled = userDefaults.boolValue(forKey: StorageKey.clockOutReminderEnabled) ?? Default.clockOutReminderEnabled
        lastSettlementDateKey = userDefaults.string(forKey: StorageKey.lastSettlementDateKey)
        let now = Date()
        currentDateKey = Self.dateKey(for: now)
        let dailyRecordLoadResult = Self.loadDailyRecords(from: userDefaults)
        dailyRecords = dailyRecordLoadResult.records
        dailyRecordStorageMode = dailyRecordLoadResult.storageMode
        persistEditableSettings()

        closeLastObservedDayIfNeeded(now: now)
        rememberObservedSnapshot(now)
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

    private var currentSettingsSnapshot: WageCalculationSettingsSnapshot {
        WageCalculationSettingsSnapshot(
            monthlySalary: monthlySalary,
            workdaysPerMonth: workdaysPerMonth,
            workStartMinute: workStart.minutesInDay,
            workEndMinute: workEnd.minutesInDay,
            lunchStartMinute: lunchStart.minutesInDay,
            lunchEndMinute: lunchEnd.minutesInDay,
            hasLunchBreak: hasLunchBreak,
            includeOvertime: includeOvertime,
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
            includeOvertime: includeOvertime
        )
    }

    func dailyRecord(for date: Date, includingLiveToday: Bool = false) -> DailyWageRecord? {
        let dateKey = Self.dateKey(for: date)
        if includingLiveToday, dateKey == currentDateKey {
            let now = Date()
            return makeDailyRecord(
                for: now,
                capturedAt: now,
                source: .observed,
                settings: currentSettingsSnapshot
            )
        }

        return dailyRecords[dateKey]
    }

    func persistCurrentDaySnapshot() {
        let now = Date()
        advanceCalendarDay(to: now)
        persistDailySnapshot(for: now, capturedAt: now)
        rememberObservedSnapshot(now)
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
        let components = DateComponents.calendar.dateComponents([.hour, .minute], from: date)
        if keyPath == \WageState.workStart {
            setWorkStart(components)
        } else if keyPath == \WageState.workEnd {
            setWorkEnd(components)
        } else {
            self[keyPath: keyPath] = components
        }
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
        let now = Date()
        advanceCalendarDay(to: now)
        rememberObservedSnapshot(now)
    }

    private func advanceCalendarDay(to newDate: Date) {
        let newDateKey = Self.dateKey(for: newDate)
        guard newDateKey != currentDateKey else { return }

        let settings = lastObservedSnapshotForClosure()?.settings ?? currentSettingsSnapshot
        closeObservedDateRange(from: currentDayStart, to: newDate, capturedAt: newDate, settings: settings)
        currentDateKey = newDateKey
        rememberObservedSnapshot(newDate)
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

        let closedLastObservedRecord = makeDailyRecord(
            for: Self.endOfDay(for: lastObservedStart),
            capturedAt: capturedAt,
            source: .observed,
            settings: settings
        )
        nextRecords[closedLastObservedRecord.dateKey] = closedLastObservedRecord

        var cursor = calendar.date(byAdding: .day, value: 1, to: lastObservedStart)
        while let date = cursor, date < todayStart {
            let dateKey = Self.dateKey(for: date)
            if nextRecords[dateKey] == nil {
                let record = makeBackfilledDailyRecord(for: date, capturedAt: capturedAt, settings: settings)
                nextRecords[record.dateKey] = record
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: date)
        }

        replaceDailyRecords(nextRecords)
        saveDailyRecords()
    }

    private func persistDailySnapshot(for date: Date, capturedAt: Date) {
        let record = makeDailyRecord(
            for: date,
            capturedAt: capturedAt,
            source: .observed,
            settings: currentSettingsSnapshot
        )
        var nextRecords = dailyRecords
        nextRecords[record.dateKey] = record
        replaceDailyRecords(nextRecords)
        saveDailyRecords()
    }

    private func replaceDailyRecords(_ records: [String: DailyWageRecord]) {
        dailyRecords = records
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
        let day = calculateWageDay(at: date, settings: settings)
        guard isPaidWorkday(date, settings: settings) else {
            return DailyWageRecord(
                dateKey: Self.dateKey(for: date),
                earnedToday: 0,
                targetToday: 0,
                elapsedPaidSeconds: 0,
                workdayMinutes: day.workdayMinutes,
                hourlyRate: day.hourlyRate,
                monthlySalary: settings.monthlySalary,
                workdaysPerMonth: settings.workdaysPerMonth,
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
            monthlySalary: settings.monthlySalary,
            workdaysPerMonth: settings.workdaysPerMonth,
            capturedAt: capturedAt,
            source: source
        )
    }

    private func calculateWageDay(at date: Date, settings: WageCalculationSettingsSnapshot) -> WageDay {
        let currentTime = DateComponents.calendar.dateComponents([.hour, .minute, .second], from: date)
        return WageCalculator.compute(
            monthlySalary: settings.monthlySalary,
            workdaysPerMonth: settings.workdaysPerMonth,
            workStart: settings.workStart,
            workEnd: settings.workEnd,
            lunchStart: settings.lunchStart,
            lunchEnd: settings.lunchEnd,
            hasLunchBreak: settings.hasLunchBreak,
            includeOvertime: settings.includeOvertime,
            now: currentTime
        )
    }

    private func isPaidWorkday(_ date: Date, settings: WageCalculationSettingsSnapshot) -> Bool {
        settings.selectedWeekdaySet.contains(Self.weekdayIndex(for: date))
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
    var includeOvertime: Bool
    var selectedWeekdays: [Int]

    init(
        monthlySalary: Double,
        workdaysPerMonth: Int,
        workStartMinute: Int,
        workEndMinute: Int,
        lunchStartMinute: Int,
        lunchEndMinute: Int,
        hasLunchBreak: Bool,
        includeOvertime: Bool,
        selectedWeekdays: Set<Int>
    ) {
        self.monthlySalary = monthlySalary
        self.workdaysPerMonth = workdaysPerMonth
        self.workStartMinute = workStartMinute
        self.workEndMinute = workEndMinute
        self.lunchStartMinute = lunchStartMinute
        self.lunchEndMinute = lunchEndMinute
        self.hasLunchBreak = hasLunchBreak
        self.includeOvertime = includeOvertime
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
    let includeOvertime: Bool
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
