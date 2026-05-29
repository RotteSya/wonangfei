import Foundation
import OSLog
import SQLite3

private let wageStateLogger = Logger(subsystem: "com.wonangfei.app", category: "WageState")
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum StorageKey {
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
    static let clockOutReminderEnabled = "wnf.settings.clockOutReminderEnabled"
    static let lastSettlementDateKey = "wnf.settlement.lastCompletedDateKey"
    static let dailyRecords = "wnf.records.daily"
    static let dailyRecordsLegacyRawBackup = "wnf.records.daily.rawBackup.legacy"
    static let dailyRecordsUnsupportedRawBackup = "wnf.records.daily.rawBackup.unsupported"
    static let dailyRecordsDecodeFailedRawBackup = "wnf.records.daily.rawBackup.decodeFailed"
    static let dailyRecordsUnsupportedRecovery = "wnf.records.daily.recovery.unsupported"
    static let dailyRecordsDecodeFailedRecovery = "wnf.records.daily.recovery.decodeFailed"
    static let dailyRecordsActiveRecoveryKey = "wnf.records.daily.recovery.activeKey"
    static let dailyRecordsSQLiteMigrationCompleted = "wnf.records.daily.sqliteMigrationCompleted"
    static let dailyRecordsSQLitePathOverride = "wnf.records.daily.sqlitePathOverride"
    static let lastObservedDateKey = "wnf.records.lastObservedDateKey"
    static let lastObservedSnapshot = "wnf.records.lastObservedSnapshot"
}

struct DailyRecordLoadResult {
    var records: [String: DailyWageRecord]
    var monthlySummaries: [String: MonthlyRecordSummary]

    static let empty = DailyRecordLoadResult(records: [:], monthlySummaries: [:])
}

struct MonthlyRecordSummary: Codable, Equatable, Identifiable {
    var id: String { monthKey }

    var monthKey: String
    var amount: Double
    var recordedDays: Int
    var elapsedPaidSeconds: Int
    var updatedAt: Date

    init(
        monthKey: String,
        amount: Double,
        recordedDays: Int,
        elapsedPaidSeconds: Int,
        updatedAt: Date
    ) {
        self.monthKey = monthKey
        self.amount = amount
        self.recordedDays = recordedDays
        self.elapsedPaidSeconds = elapsedPaidSeconds
        self.updatedAt = updatedAt
    }
}

struct DailyRecordStorageEnvelope: Codable {
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

final class DailyRecordSQLiteStore {
    static let retainedDailyRecordCount = 400

    private let userDefaults: UserDefaults
    let databaseURL: URL

    init(userDefaults: UserDefaults = .standard, databaseURL: URL? = nil) {
        self.userDefaults = userDefaults
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL(userDefaults: userDefaults)
    }

    func load(now: Date = Date()) -> DailyRecordLoadResult {
        do {
            try migrateLegacyUserDefaultsIfNeeded(now: now)
            return try withDatabase { db in
                try performTransaction(db) {
                    try compactOldRecords(db: db, now: now)
                }
                return DailyRecordLoadResult(
                    records: try fetchDailyRecords(db: db),
                    monthlySummaries: try fetchMonthlySummaries(db: db)
                )
            }
        } catch {
            wageStateLogger.error("Failed to load SQLite daily records: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }

    @discardableResult
    func upsert(_ record: DailyWageRecord, now: Date = Date()) -> DailyRecordLoadResult {
        upsert([record], now: now)
    }

    @discardableResult
    func upsert(_ records: [DailyWageRecord], now: Date = Date()) -> DailyRecordLoadResult {
        guard records.isEmpty == false else { return load(now: now) }

        do {
            try withDatabase { db in
                try performTransaction(db) {
                    try upsert(records: records, db: db)
                    try compactOldRecords(db: db, now: now)
                }
            }
        } catch {
            wageStateLogger.error("Failed to upsert SQLite daily records: \(String(describing: error), privacy: .public)")
        }

        return load(now: now)
    }

    private static func defaultDatabaseURL(userDefaults: UserDefaults) -> URL {
        if let overridePath = userDefaults.string(forKey: StorageKey.dailyRecordsSQLitePathOverride) {
            return URL(fileURLWithPath: overridePath)
        }

        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WNFShared.appGroupID) {
            return appGroupURL.appendingPathComponent("DailyRecords.sqlite")
        }

        let fallbackRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return fallbackRoot
            .appendingPathComponent("WNF", isDirectory: true)
            .appendingPathComponent("DailyRecords.sqlite")
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            defer { sqlite3_close(db) }
            throw SQLiteStoreError.open(message: db.map(Self.message(from:)) ?? "unknown open failure")
        }
        defer { sqlite3_close(db) }

        try initializeDatabase(db)
        return try body(db)
    }

    private func initializeDatabase(_ db: OpaquePointer) throws {
        try execute("PRAGMA journal_mode=WAL;", db: db)
        try execute("PRAGMA foreign_keys=ON;", db: db)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS daily_records (
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
            """,
            db: db
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS monthly_record_summaries (
                month_key TEXT PRIMARY KEY NOT NULL,
                amount REAL NOT NULL,
                recorded_days INTEGER NOT NULL,
                elapsed_paid_seconds INTEGER NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            db: db
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            """,
            db: db
        )
    }

    private func migrateLegacyUserDefaultsIfNeeded(now: Date) throws {
        guard userDefaults.bool(forKey: StorageKey.dailyRecordsSQLiteMigrationCompleted) == false else { return }
        let payloads = legacyPayloads()
        guard payloads.isEmpty == false else {
            userDefaults.set(true, forKey: StorageKey.dailyRecordsSQLiteMigrationCompleted)
            return
        }

        var firstDecodeError: Error?
        for payload in payloads {
            do {
                let records = try Self.decodeLegacyPayload(payload.data)
                try writeLegacyBackup(records: records, migratedFromKey: payload.key)
                try withDatabase { db in
                    try performTransaction(db) {
                        try upsert(records: Array(records.values), db: db)
                        try compactOldRecords(db: db, now: now)
                    }
                }
                removeLegacyDailyRecordPayloads()
                userDefaults.set(true, forKey: StorageKey.dailyRecordsSQLiteMigrationCompleted)
                wageStateLogger.info(
                    "Migrated \(records.count, privacy: .public) daily records from \(payload.key, privacy: .public) into SQLite"
                )
                return
            } catch {
                firstDecodeError = firstDecodeError ?? error
                wageStateLogger.error(
                    "Skipped legacy daily record payload \(payload.key, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }

        if let firstDecodeError {
            throw firstDecodeError
        }
    }

    private func legacyPayloads() -> [(key: String, data: Data)] {
        let knownKeys = [
            StorageKey.dailyRecords,
            userDefaults.string(forKey: StorageKey.dailyRecordsActiveRecoveryKey),
            StorageKey.dailyRecordsDecodeFailedRecovery,
            StorageKey.dailyRecordsUnsupportedRecovery,
            StorageKey.dailyRecordsLegacyRawBackup,
            StorageKey.dailyRecordsUnsupportedRawBackup,
            StorageKey.dailyRecordsDecodeFailedRawBackup
        ].compactMap(\.self)

        var seen = Set<String>()
        return knownKeys
            .filter { seen.insert($0).inserted }
            .compactMap { key in
                guard let data = userDefaults.data(forKey: key) else { return nil }
                return (key: key, data: data)
            }
    }

    private func writeLegacyBackup(records: [String: DailyWageRecord], migratedFromKey: String) throws {
        let backupDirectory = databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent("DailyRecordBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = backupDirectory.appendingPathComponent("userdefaults-migration-\(timestamp).json")
        let envelope = DailyRecordStorageEnvelope(records: records)
        let data = try Self.encodeDailyRecords(envelope)
        try data.write(to: backupURL, options: [.atomic])
        userDefaults.set(backupURL.path, forKey: "\(StorageKey.dailyRecordsSQLiteMigrationCompleted).backupPath")
        userDefaults.set(migratedFromKey, forKey: "\(StorageKey.dailyRecordsSQLiteMigrationCompleted).sourceKey")
    }

    private func removeLegacyDailyRecordPayloads() {
        let keys = [
            StorageKey.dailyRecords,
            StorageKey.dailyRecordsLegacyRawBackup,
            StorageKey.dailyRecordsUnsupportedRawBackup,
            StorageKey.dailyRecordsDecodeFailedRawBackup,
            StorageKey.dailyRecordsUnsupportedRecovery,
            StorageKey.dailyRecordsDecodeFailedRecovery,
            StorageKey.dailyRecordsActiveRecoveryKey
        ]
        for key in keys {
            userDefaults.removeObject(forKey: key)
            userDefaults.removeObject(forKey: "\(key).createdAt")
            userDefaults.removeObject(forKey: "\(key).reason")
        }
    }

    private func upsert(records: [DailyWageRecord], db: OpaquePointer) throws {
        let sql =
            """
            INSERT INTO daily_records (
                date_key,
                earned_today,
                target_today,
                elapsed_paid_seconds,
                workday_minutes,
                hourly_rate,
                monthly_salary,
                workdays_per_month,
                captured_at,
                source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(date_key) DO UPDATE SET
                earned_today = excluded.earned_today,
                target_today = excluded.target_today,
                elapsed_paid_seconds = excluded.elapsed_paid_seconds,
                workday_minutes = excluded.workday_minutes,
                hourly_rate = excluded.hourly_rate,
                monthly_salary = excluded.monthly_salary,
                workdays_per_month = excluded.workdays_per_month,
                captured_at = excluded.captured_at,
                source = excluded.source;
            """
        var statement: OpaquePointer?
        try prepare(sql, db: db, statement: &statement)
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(record.dateKey, at: 1, statement: statement, db: db)
            try bind(record.earnedToday, at: 2, statement: statement, db: db)
            try bind(record.targetToday, at: 3, statement: statement, db: db)
            try bind(record.elapsedPaidSeconds, at: 4, statement: statement, db: db)
            try bind(record.workdayMinutes, at: 5, statement: statement, db: db)
            try bind(record.hourlyRate, at: 6, statement: statement, db: db)
            try bind(record.monthlySalary, at: 7, statement: statement, db: db)
            try bind(record.workdaysPerMonth, at: 8, statement: statement, db: db)
            try bind(record.capturedAt.timeIntervalSinceReferenceDate, at: 9, statement: statement, db: db)
            try bind(record.source.rawValue, at: 10, statement: statement, db: db)
            try stepDone(statement, db: db)
        }
    }

    private func compactOldRecords(db: OpaquePointer, now: Date) throws {
        let cutoffDateKey = Self.retentionCutoffDateKey(now: now)
        let oldRecords = try fetchDailyRecords(db: db, before: cutoffDateKey)
        guard oldRecords.isEmpty == false else { return }

        var summaries: [String: MonthlyRecordSummary] = [:]
        for record in oldRecords.values {
            let monthKey = Self.monthKey(forDateKey: record.dateKey)
            var summary = summaries[monthKey] ?? MonthlyRecordSummary(
                monthKey: monthKey,
                amount: 0,
                recordedDays: 0,
                elapsedPaidSeconds: 0,
                updatedAt: now
            )
            summary.amount += record.earnedToday
            summary.recordedDays += 1
            summary.elapsedPaidSeconds += record.elapsedPaidSeconds
            summary.updatedAt = now
            summaries[monthKey] = summary
        }

        try upsert(monthlySummaries: Array(summaries.values), db: db)
        try deleteDailyRecords(before: cutoffDateKey, db: db)
    }

    private func upsert(monthlySummaries: [MonthlyRecordSummary], db: OpaquePointer) throws {
        let sql =
            """
            INSERT INTO monthly_record_summaries (
                month_key,
                amount,
                recorded_days,
                elapsed_paid_seconds,
                updated_at
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(month_key) DO UPDATE SET
                amount = amount + excluded.amount,
                recorded_days = recorded_days + excluded.recorded_days,
                elapsed_paid_seconds = elapsed_paid_seconds + excluded.elapsed_paid_seconds,
                updated_at = excluded.updated_at;
            """
        var statement: OpaquePointer?
        try prepare(sql, db: db, statement: &statement)
        defer { sqlite3_finalize(statement) }

        for summary in monthlySummaries {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(summary.monthKey, at: 1, statement: statement, db: db)
            try bind(summary.amount, at: 2, statement: statement, db: db)
            try bind(summary.recordedDays, at: 3, statement: statement, db: db)
            try bind(summary.elapsedPaidSeconds, at: 4, statement: statement, db: db)
            try bind(summary.updatedAt.timeIntervalSinceReferenceDate, at: 5, statement: statement, db: db)
            try stepDone(statement, db: db)
        }
    }

    private func fetchDailyRecords(db: OpaquePointer, before cutoffDateKey: String? = nil) throws -> [String: DailyWageRecord] {
        let sql: String
        if cutoffDateKey == nil {
            sql =
                """
                SELECT date_key, earned_today, target_today, elapsed_paid_seconds, workday_minutes,
                       hourly_rate, monthly_salary, workdays_per_month, captured_at, source
                FROM daily_records
                ORDER BY date_key;
                """
        } else {
            sql =
                """
                SELECT date_key, earned_today, target_today, elapsed_paid_seconds, workday_minutes,
                       hourly_rate, monthly_salary, workdays_per_month, captured_at, source
                FROM daily_records
                WHERE date_key < ?
                ORDER BY date_key;
                """
        }

        var statement: OpaquePointer?
        try prepare(sql, db: db, statement: &statement)
        defer { sqlite3_finalize(statement) }
        if let cutoffDateKey {
            try bind(cutoffDateKey, at: 1, statement: statement, db: db)
        }

        var records: [String: DailyWageRecord] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let dateKey = columnText(statement, 0)
            let source = DailyRecordSource(rawValue: columnText(statement, 9)) ?? .observed
            let record = DailyWageRecord(
                dateKey: dateKey,
                earnedToday: sqlite3_column_double(statement, 1),
                targetToday: sqlite3_column_double(statement, 2),
                elapsedPaidSeconds: Int(sqlite3_column_int64(statement, 3)),
                workdayMinutes: Int(sqlite3_column_int64(statement, 4)),
                hourlyRate: sqlite3_column_double(statement, 5),
                monthlySalary: sqlite3_column_double(statement, 6),
                workdaysPerMonth: Int(sqlite3_column_int64(statement, 7)),
                capturedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 8)),
                source: source
            )
            records[dateKey] = record
        }

        return records
    }

    private func fetchMonthlySummaries(db: OpaquePointer) throws -> [String: MonthlyRecordSummary] {
        let sql =
            """
            SELECT month_key, amount, recorded_days, elapsed_paid_seconds, updated_at
            FROM monthly_record_summaries
            ORDER BY month_key;
            """
        var statement: OpaquePointer?
        try prepare(sql, db: db, statement: &statement)
        defer { sqlite3_finalize(statement) }

        var summaries: [String: MonthlyRecordSummary] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let monthKey = columnText(statement, 0)
            summaries[monthKey] = MonthlyRecordSummary(
                monthKey: monthKey,
                amount: sqlite3_column_double(statement, 1),
                recordedDays: Int(sqlite3_column_int64(statement, 2)),
                elapsedPaidSeconds: Int(sqlite3_column_int64(statement, 3)),
                updatedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 4))
            )
        }
        return summaries
    }

    private func deleteDailyRecords(before cutoffDateKey: String, db: OpaquePointer) throws {
        var statement: OpaquePointer?
        try prepare("DELETE FROM daily_records WHERE date_key < ?;", db: db, statement: &statement)
        defer { sqlite3_finalize(statement) }
        try bind(cutoffDateKey, at: 1, statement: statement, db: db)
        try stepDone(statement, db: db)
    }

    private func performTransaction(_ db: OpaquePointer, _ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;", db: db)
        do {
            try body()
            try execute("COMMIT;", db: db)
        } catch {
            try? execute("ROLLBACK;", db: db)
            throw error
        }
    }

    private func execute(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? Self.message(from: db)
            sqlite3_free(errorMessage)
            throw SQLiteStoreError.execute(sql: sql, message: message)
        }
    }

    private func prepare(_ sql: String, db: OpaquePointer, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepare(sql: sql, message: Self.message(from: db))
        }
    }

    private func stepDone(_ statement: OpaquePointer?, db: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.step(message: Self.message(from: db))
        }
    }

    private func bind(_ value: String, at index: Int32, statement: OpaquePointer?, db: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw SQLiteStoreError.bind(message: Self.message(from: db))
        }
    }

    private func bind(_ value: Double, at index: Int32, statement: OpaquePointer?, db: OpaquePointer) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw SQLiteStoreError.bind(message: Self.message(from: db))
        }
    }

    private func bind(_ value: Int, at index: Int32, statement: OpaquePointer?, db: OpaquePointer) throws {
        guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
            throw SQLiteStoreError.bind(message: Self.message(from: db))
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private static func retentionCutoffDateKey(now: Date) -> String {
        let calendar = DateComponents.calendar
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(
            byAdding: .day,
            value: -(Self.retainedDailyRecordCount - 1),
            to: today
        ) ?? today
        return WageState.dateKey(for: cutoff)
    }

    private static func monthKey(forDateKey dateKey: String) -> String {
        String(dateKey.prefix(7))
    }

    private static func message(from db: OpaquePointer) -> String {
        sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown SQLite error"
    }

    private static let dailyRecordEncoder = JSONEncoder()
    private static let dailyRecordDecoder = JSONDecoder()
    private static let dailyRecordCoderLock = NSLock()

    private static func encodeDailyRecords(_ store: DailyRecordStorageEnvelope) throws -> Data {
        dailyRecordCoderLock.lock()
        defer { dailyRecordCoderLock.unlock() }
        return try dailyRecordEncoder.encode(store)
    }

    private static func decodeLegacyPayload(_ data: Data) throws -> [String: DailyWageRecord] {
        dailyRecordCoderLock.lock()
        defer { dailyRecordCoderLock.unlock() }

        do {
            let store = try dailyRecordDecoder.decode(DailyRecordStorageEnvelope.self, from: data)
            guard store.schemaVersion <= DailyRecordStorageEnvelope.currentSchemaVersion else {
                throw SQLiteStoreError.unsupportedSchema(version: store.schemaVersion)
            }
            return store.records
        } catch let envelopeError {
            do {
                return try dailyRecordDecoder.decode([String: DailyWageRecord].self, from: data)
            } catch {
                throw SQLiteStoreError.decode(envelope: envelopeError, legacy: error)
            }
        }
    }
}

private enum SQLiteStoreError: Error, CustomStringConvertible {
    case open(message: String)
    case execute(sql: String, message: String)
    case prepare(sql: String, message: String)
    case bind(message: String)
    case step(message: String)
    case unsupportedSchema(version: Int)
    case decode(envelope: Error, legacy: Error)

    var description: String {
        switch self {
        case .open(let message):
            return "SQLite open failed: \(message)"
        case .execute(let sql, let message):
            return "SQLite execute failed (\(sql)): \(message)"
        case .prepare(let sql, let message):
            return "SQLite prepare failed (\(sql)): \(message)"
        case .bind(let message):
            return "SQLite bind failed: \(message)"
        case .step(let message):
            return "SQLite step failed: \(message)"
        case .unsupportedSchema(let version):
            return "Unsupported daily record schema version \(version)"
        case .decode(let envelope, let legacy):
            return "Daily record decode failed. envelope: \(envelope); legacy: \(legacy)"
        }
    }
}
