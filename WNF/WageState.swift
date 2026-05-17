import Foundation
import OSLog

private let wageStateLogger = Logger(subsystem: "com.wonangfei.app", category: "WageState")

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
            userDefaults.set(workStart.minutesInDay, forKey: StorageKey.workStartMinute)
        }
    }

    @Published var workEnd: DateComponents {
        didSet {
            userDefaults.set(workEnd.minutesInDay, forKey: StorageKey.workEndMinute)
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
        }
    }

    @Published private(set) var currentDateKey: String
    @Published private(set) var dailyRecords: [String: DailyWageRecord]

    private let userDefaults: UserDefaults
    private var dailyRecordStorageMode: DailyRecordStorageMode
    private var dayBoundaryTimer: Timer?

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

        var cursor = calendar.date(byAdding: .day, value: 1, to: lastObservedStart)
        while let date = cursor, date < todayStart {
            let dateKey = Self.dateKey(for: date)
            if nextRecords[dateKey] == nil {
                let record = makeBackfilledDailyRecord(for: date, capturedAt: capturedAt)
                nextRecords[record.dateKey] = record
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: date)
        }

        dailyRecords = nextRecords
        saveDailyRecords()
    }

    private func persistDailySnapshot(for date: Date, capturedAt: Date) {
        let record = makeDailyRecord(for: date, capturedAt: capturedAt, source: .observed)
        var nextRecords = dailyRecords
        nextRecords[record.dateKey] = record
        dailyRecords = nextRecords
        saveDailyRecords()
    }

    private func makeBackfilledDailyRecord(for date: Date, capturedAt: Date) -> DailyWageRecord {
        let snapshotDate = Self.endOfDay(for: date)
        let day = calculation(at: snapshotDate)
        guard selectedWeekdays.contains(Self.weekdayIndex(for: date)) else {
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
                source: .backfilled
            )
        }

        return makeDailyRecord(for: snapshotDate, capturedAt: capturedAt, source: .backfilled)
    }

    private func makeDailyRecord(for date: Date, capturedAt: Date, source: DailyRecordSource) -> DailyWageRecord {
        let day = calculation(at: date)
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

    private func saveDailyRecords() {
        let storageKey: String
        switch dailyRecordStorageMode {
        case .primaryWritable:
            storageKey = StorageKey.dailyRecords
            userDefaults.removeObject(forKey: StorageKey.dailyRecordsActiveRecoveryKey)
        case .recoveryWritesOnly(let recoveryKey):
            storageKey = recoveryKey
            userDefaults.set(recoveryKey, forKey: StorageKey.dailyRecordsActiveRecoveryKey)
            wageStateLogger.error(
                "Primary daily record storage is write-protected after a decode or schema failure; saving current records to \(recoveryKey, privacy: .public)"
            )
        }

        do {
            let store = DailyRecordStorageEnvelope(records: dailyRecords)
            let data = try JSONEncoder().encode(store)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            let message = String(describing: error)
            wageStateLogger.error("Failed to encode daily records: \(message, privacy: .public)")
        }
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
    }

    private func rememberObservedDate(_ date: Date) {
        userDefaults.set(Self.dateKey(for: date), forKey: StorageKey.lastObservedDateKey)
    }

    private static func loadDailyRecords(from userDefaults: UserDefaults) -> DailyRecordLoadResult {
        guard let data = userDefaults.data(forKey: StorageKey.dailyRecords) else {
            if let recoveryResult = loadRecoveryDailyRecords(
                from: userDefaults,
                preferredKey: StorageKey.dailyRecordsDecodeFailedRecovery
            ) {
                return recoveryResult
            }
            userDefaults.removeObject(forKey: StorageKey.dailyRecordsActiveRecoveryKey)
            return DailyRecordLoadResult(records: [:], storageMode: .primaryWritable)
        }

        do {
            let store = try JSONDecoder().decode(DailyRecordStorageEnvelope.self, from: data)
            if store.schemaVersion > DailyRecordStorageEnvelope.currentSchemaVersion {
                preserveRawDailyRecords(
                    data,
                    to: StorageKey.dailyRecordsUnsupportedRawBackup,
                    reason: "unsupported schema version \(store.schemaVersion)",
                    userDefaults: userDefaults
                )
                wageStateLogger.warning(
                    "Loaded daily records from unsupported schema version \(store.schemaVersion, privacy: .public); current schema version is \(DailyRecordStorageEnvelope.currentSchemaVersion, privacy: .public)"
                )
                if let recoveryResult = loadRecoveryDailyRecords(
                    from: userDefaults,
                    preferredKey: StorageKey.dailyRecordsUnsupportedRecovery
                ) {
                    return recoveryResult
                }
                userDefaults.set(
                    StorageKey.dailyRecordsUnsupportedRecovery,
                    forKey: StorageKey.dailyRecordsActiveRecoveryKey
                )
                return DailyRecordLoadResult(
                    records: store.records,
                    storageMode: .recoveryWritesOnly(StorageKey.dailyRecordsUnsupportedRecovery)
                )
            }
            userDefaults.removeObject(forKey: StorageKey.dailyRecordsActiveRecoveryKey)
            return DailyRecordLoadResult(records: store.records, storageMode: .primaryWritable)
        } catch let envelopeError {
            do {
                let records = try JSONDecoder().decode([String: DailyWageRecord].self, from: data)
                migrateLegacyDailyRecords(records, originalData: data, userDefaults: userDefaults)
                userDefaults.removeObject(forKey: StorageKey.dailyRecordsActiveRecoveryKey)
                return DailyRecordLoadResult(records: records, storageMode: .primaryWritable)
            } catch let legacyError {
                preserveRawDailyRecords(
                    data,
                    to: StorageKey.dailyRecordsDecodeFailedRawBackup,
                    reason: "decode failed",
                    userDefaults: userDefaults
                )
                let envelopeMessage = String(describing: envelopeError)
                let legacyMessage = String(describing: legacyError)
                wageStateLogger.error(
                    "Failed to decode daily records. envelope: \(envelopeMessage, privacy: .public); legacy: \(legacyMessage, privacy: .public)"
                )
                if let recoveryResult = loadRecoveryDailyRecords(
                    from: userDefaults,
                    preferredKey: StorageKey.dailyRecordsDecodeFailedRecovery
                ) {
                    return recoveryResult
                }
                userDefaults.set(
                    StorageKey.dailyRecordsDecodeFailedRecovery,
                    forKey: StorageKey.dailyRecordsActiveRecoveryKey
                )
                return DailyRecordLoadResult(
                    records: [:],
                    storageMode: .recoveryWritesOnly(StorageKey.dailyRecordsDecodeFailedRecovery)
                )
            }
        }
    }

    private static func loadRecoveryDailyRecords(
        from userDefaults: UserDefaults,
        preferredKey: String
    ) -> DailyRecordLoadResult? {
        for recoveryKey in recoveryKeys(preferredKey: preferredKey, userDefaults: userDefaults) {
            guard let data = userDefaults.data(forKey: recoveryKey) else { continue }

            do {
                let store = try JSONDecoder().decode(DailyRecordStorageEnvelope.self, from: data)
                guard store.schemaVersion <= DailyRecordStorageEnvelope.currentSchemaVersion else {
                    wageStateLogger.warning(
                        "Skipped daily records recovery key \(recoveryKey, privacy: .public) with unsupported schema version \(store.schemaVersion, privacy: .public)"
                    )
                    continue
                }

                userDefaults.set(recoveryKey, forKey: StorageKey.dailyRecordsActiveRecoveryKey)
                wageStateLogger.warning("Loaded daily records from recovery key \(recoveryKey, privacy: .public)")
                return DailyRecordLoadResult(
                    records: store.records,
                    storageMode: .recoveryWritesOnly(recoveryKey)
                )
            } catch {
                let message = String(describing: error)
                wageStateLogger.error(
                    "Failed to decode daily records recovery key \(recoveryKey, privacy: .public): \(message, privacy: .public)"
                )
            }
        }

        return nil
    }

    private static func recoveryKeys(preferredKey: String, userDefaults: UserDefaults) -> [String] {
        let knownKeys = [
            StorageKey.dailyRecordsDecodeFailedRecovery,
            StorageKey.dailyRecordsUnsupportedRecovery
        ]
        var keys: [String] = []
        if let activeKey = userDefaults.string(forKey: StorageKey.dailyRecordsActiveRecoveryKey),
           knownKeys.contains(activeKey) {
            keys.append(activeKey)
        }
        keys.append(preferredKey)
        keys.append(contentsOf: knownKeys)

        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private static func migrateLegacyDailyRecords(
        _ records: [String: DailyWageRecord],
        originalData: Data,
        userDefaults: UserDefaults
    ) {
        preserveRawDailyRecords(
            originalData,
            to: StorageKey.dailyRecordsLegacyRawBackup,
            reason: "legacy schema migration",
            userDefaults: userDefaults
        )

        do {
            let store = DailyRecordStorageEnvelope(records: records)
            let data = try JSONEncoder().encode(store)
            userDefaults.set(data, forKey: StorageKey.dailyRecords)
            wageStateLogger.info(
                "Migrated \(records.count, privacy: .public) daily records to schema version \(DailyRecordStorageEnvelope.currentSchemaVersion, privacy: .public)"
            )
        } catch {
            let message = String(describing: error)
            wageStateLogger.error("Failed to migrate legacy daily records: \(message, privacy: .public)")
        }
    }

    private static func preserveRawDailyRecords(
        _ data: Data,
        to backupKey: String,
        reason: String,
        userDefaults: UserDefaults
    ) {
        userDefaults.set(data, forKey: backupKey)
        userDefaults.set(Date(), forKey: "\(backupKey).createdAt")
        userDefaults.set(reason, forKey: "\(backupKey).reason")
        wageStateLogger.info("Preserved raw daily records for \(reason, privacy: .public) at \(backupKey, privacy: .public)")
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

private enum StorageKey {
    static let monthlySalary = "wnf.settings.monthlySalary"
    static let workdaysPerMonth = "wnf.settings.workdaysPerMonth"
    static let workStartMinute = "wnf.settings.workStartMinute"
    static let workEndMinute = "wnf.settings.workEndMinute"
    static let lunchStartMinute = "wnf.settings.lunchStartMinute"
    static let lunchEndMinute = "wnf.settings.lunchEndMinute"
    static let hasLunchBreak = "wnf.settings.hasLunchBreak"
    static let includeOvertime = "wnf.settings.includeOvertime"
    static let privacyMode = "wnf.settings.privacyMode"
    static let selectedWeekdays = "wnf.settings.selectedWeekdays"
    static let dailyRecords = "wnf.records.daily"
    static let dailyRecordsLegacyRawBackup = "wnf.records.daily.rawBackup.legacy"
    static let dailyRecordsUnsupportedRawBackup = "wnf.records.daily.rawBackup.unsupported"
    static let dailyRecordsDecodeFailedRawBackup = "wnf.records.daily.rawBackup.decodeFailed"
    static let dailyRecordsUnsupportedRecovery = "wnf.records.daily.recovery.unsupported"
    static let dailyRecordsDecodeFailedRecovery = "wnf.records.daily.recovery.decodeFailed"
    static let dailyRecordsActiveRecoveryKey = "wnf.records.daily.recovery.activeKey"
    static let lastObservedDateKey = "wnf.records.lastObservedDateKey"
}

private struct DailyRecordLoadResult {
    var records: [String: DailyWageRecord]
    var storageMode: DailyRecordStorageMode
}

private enum DailyRecordStorageMode {
    case primaryWritable
    case recoveryWritesOnly(String)
}

private struct DailyRecordStorageEnvelope: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var records: [String: DailyWageRecord]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        records: [String: DailyWageRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
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

enum DailyRecordSource: String, Codable, Equatable {
    case observed
    case backfilled
}

struct DailyWageRecord: Codable, Equatable, Identifiable {
    var id: String { dateKey }

    var dateKey: String
    var earnedToday: Double
    var targetToday: Double
    var elapsedPaidSeconds: Int
    var workdayMinutes: Int
    var hourlyRate: Double
    var monthlySalary: Double
    var workdaysPerMonth: Int
    var capturedAt: Date
    var source: DailyRecordSource

    var elapsedPaidMinutes: Int {
        elapsedPaidSeconds / 60
    }

    init(
        dateKey: String,
        earnedToday: Double,
        targetToday: Double,
        elapsedPaidSeconds: Int,
        workdayMinutes: Int,
        hourlyRate: Double,
        monthlySalary: Double,
        workdaysPerMonth: Int,
        capturedAt: Date,
        source: DailyRecordSource = .observed
    ) {
        self.dateKey = dateKey
        self.earnedToday = earnedToday
        self.targetToday = targetToday
        self.elapsedPaidSeconds = elapsedPaidSeconds
        self.workdayMinutes = workdayMinutes
        self.hourlyRate = hourlyRate
        self.monthlySalary = monthlySalary
        self.workdaysPerMonth = workdaysPerMonth
        self.capturedAt = capturedAt
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case dateKey
        case earnedToday
        case targetToday
        case elapsedPaidSeconds
        case workdayMinutes
        case hourlyRate
        case monthlySalary
        case workdaysPerMonth
        case capturedAt
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateKey = try container.decode(String.self, forKey: .dateKey)
        earnedToday = try container.decode(Double.self, forKey: .earnedToday)
        targetToday = try container.decode(Double.self, forKey: .targetToday)
        elapsedPaidSeconds = try container.decode(Int.self, forKey: .elapsedPaidSeconds)
        workdayMinutes = try container.decode(Int.self, forKey: .workdayMinutes)
        hourlyRate = try container.decode(Double.self, forKey: .hourlyRate)
        monthlySalary = try container.decode(Double.self, forKey: .monthlySalary)
        workdaysPerMonth = try container.decode(Int.self, forKey: .workdaysPerMonth)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        source = try container.decodeIfPresent(DailyRecordSource.self, forKey: .source) ?? .observed
    }
}

struct WageDay {
    var startMinute: Int
    var endMinute: Int
    var lunchStartMinute: Int
    var lunchEndMinute: Int
    var workdayMinutes: Int
    var hourlyRate: Double
    var elapsedPaidMinutes: Int
    var elapsedPaidSeconds: Int
    var earnedToday: Double
    var targetToday: Double
    var status: WorkStatus
    var wallToEndMinutes: Int

    var progress: Double {
        let workdaySeconds = workdayMinutes * 60
        guard workdaySeconds > 0 else { return 0 }
        return min(1, max(0, Double(elapsedPaidSeconds) / Double(workdaySeconds)))
    }
}

enum WorkStatus {
    case before
    case morning
    case lunch
    case afternoon
    case done

    var label: String {
        switch self {
        case .before: "尚未开工"
        case .morning: "上午搬砖中"
        case .lunch: "午休回血"
        case .afternoon: "下午挺挺"
        case .done: "今日通关"
        }
    }

    var quote: String {
        switch self {
        case .before: "别急，钱还没开始挣。"
        case .morning: "早上的两小时最值钱。"
        case .lunch: "吃饭的时候不发工资。"
        case .afternoon: "再忍忍，钱在涨。"
        case .done: "今天又把房租挣回来了。"
        }
    }

    var mascotAsset: String {
        switch self {
        case .before: "CowFrontSad"
        case .morning: "CowThreeQ"
        case .lunch: "CowFrontSad"
        case .afternoon: "CowFrontSad"
        case .done: "CowThreeQ"
        }
    }
}

enum WageCalculator {
    static func compute(
        monthlySalary: Double,
        workdaysPerMonth: Int,
        workStart: DateComponents,
        workEnd: DateComponents,
        lunchStart: DateComponents,
        lunchEnd: DateComponents,
        hasLunchBreak: Bool,
        now: DateComponents
    ) -> WageDay {
        let startMinute = workStart.minutesInDay
        let endMinute = workEnd.minutesInDay
        let rawLunchStart = hasLunchBreak ? lunchStart.minutesInDay : endMinute
        let rawLunchEnd = hasLunchBreak ? lunchEnd.minutesInDay : endMinute
        let lunchStartMinute = min(rawLunchStart, rawLunchEnd)
        let lunchEndMinute = max(rawLunchStart, rawLunchEnd)
        let lunchLength = max(0, lunchEndMinute - lunchStartMinute)
        let workdayMinutes = max(1, endMinute - startMinute - lunchLength)
        let hourlyRate = monthlySalary / (Double(max(1, workdaysPerMonth)) * (Double(workdayMinutes) / 60))
        let startSecond = startMinute * 60
        let endSecond = endMinute * 60
        let lunchStartSecond = lunchStartMinute * 60
        let lunchEndSecond = lunchEndMinute * 60
        let nowSecond = now.secondsInDay
        let nowMinute = nowSecond / 60

        var elapsedSeconds = 0
        if nowSecond > startSecond {
            elapsedSeconds = min(nowSecond, endSecond) - startSecond
            let lunchOverlap = max(0, min(nowSecond, lunchEndSecond) - lunchStartSecond)
            elapsedSeconds = max(0, elapsedSeconds - lunchOverlap)
        }

        let status: WorkStatus
        if nowMinute < startMinute {
            status = .before
        } else if nowMinute < lunchStartMinute {
            status = .morning
        } else if nowMinute < lunchEndMinute {
            status = .lunch
        } else if nowMinute < endMinute {
            status = .afternoon
        } else {
            status = .done
        }

        let earnedToday = hourlyRate / 3600 * Double(elapsedSeconds)
        let targetToday = hourlyRate / 60 * Double(workdayMinutes)
        return WageDay(
            startMinute: startMinute,
            endMinute: endMinute,
            lunchStartMinute: lunchStartMinute,
            lunchEndMinute: lunchEndMinute,
            workdayMinutes: workdayMinutes,
            hourlyRate: hourlyRate,
            elapsedPaidMinutes: elapsedSeconds / 60,
            elapsedPaidSeconds: elapsedSeconds,
            earnedToday: earnedToday,
            targetToday: targetToday,
            status: status,
            wallToEndMinutes: max(0, Int(ceil(Double(endSecond - nowSecond) / 60)))
        )
    }
}

extension DateComponents {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    static func minuteInDay(_ value: Int) -> DateComponents {
        let minuteInDay = min(max(value, 0), 23 * 60 + 59)
        return DateComponents(hour: minuteInDay / 60, minute: minuteInDay % 60)
    }

    var minutesInDay: Int {
        (hour ?? 0) * 60 + (minute ?? 0)
    }

    var secondsInDay: Int {
        minutesInDay * 60 + (second ?? 0)
    }

    var clockText: String {
        String(format: "%02d:%02d", hour ?? 0, minute ?? 0)
    }
}

enum WNFFormat {
    static func money(_ value: Double, privacy: Bool) -> String {
        privacy ? "¥••••" : "¥\(Int(value.rounded()).formatted(.number.grouping(.automatic)))"
    }

    static func moneyDecimal(_ value: Double, privacy: Bool) -> String {
        privacy ? "¥•••.••" : String(format: "¥%.2f", value)
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours <= 0 { return "\(mins)min" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h\(mins)min"
    }
}
