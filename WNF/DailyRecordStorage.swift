import Foundation
import OSLog

private let wageStateLogger = Logger(subsystem: "com.wonangfei.app", category: "WageState")

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
    static let dailyRecords = "wnf.records.daily"
    static let dailyRecordsLegacyRawBackup = "wnf.records.daily.rawBackup.legacy"
    static let dailyRecordsUnsupportedRawBackup = "wnf.records.daily.rawBackup.unsupported"
    static let dailyRecordsDecodeFailedRawBackup = "wnf.records.daily.rawBackup.decodeFailed"
    static let dailyRecordsUnsupportedRecovery = "wnf.records.daily.recovery.unsupported"
    static let dailyRecordsDecodeFailedRecovery = "wnf.records.daily.recovery.decodeFailed"
    static let dailyRecordsActiveRecoveryKey = "wnf.records.daily.recovery.activeKey"
    static let lastObservedDateKey = "wnf.records.lastObservedDateKey"
}

struct DailyRecordLoadResult {
    var records: [String: DailyWageRecord]
    var storageMode: DailyRecordStorageMode
}

enum DailyRecordStorageMode {
    case primaryWritable
    case recoveryWritesOnly(String)
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

extension WageState {
    private static let dailyRecordEncoder = JSONEncoder()
    private static let dailyRecordDecoder = JSONDecoder()
    private static let dailyRecordCoderLock = NSLock()

    func saveDailyRecords() {
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
            let data = try Self.encodeDailyRecords(store)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            let message = String(describing: error)
            wageStateLogger.error("Failed to encode daily records: \(message, privacy: .public)")
        }
    }

    static func loadDailyRecords(from userDefaults: UserDefaults) -> DailyRecordLoadResult {
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
            let store = try decodeDailyRecordsEnvelope(from: data)
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
                let records = try decodeLegacyDailyRecords(from: data)
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
                let store = try decodeDailyRecordsEnvelope(from: data)
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
            let data = try encodeDailyRecords(store)
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

    private static func encodeDailyRecords(_ store: DailyRecordStorageEnvelope) throws -> Data {
        dailyRecordCoderLock.lock()
        defer { dailyRecordCoderLock.unlock() }
        return try dailyRecordEncoder.encode(store)
    }

    private static func decodeDailyRecordsEnvelope(from data: Data) throws -> DailyRecordStorageEnvelope {
        dailyRecordCoderLock.lock()
        defer { dailyRecordCoderLock.unlock() }
        return try dailyRecordDecoder.decode(DailyRecordStorageEnvelope.self, from: data)
    }

    private static func decodeLegacyDailyRecords(from data: Data) throws -> [String: DailyWageRecord] {
        dailyRecordCoderLock.lock()
        defer { dailyRecordCoderLock.unlock() }
        return try dailyRecordDecoder.decode([String: DailyWageRecord].self, from: data)
    }
}
