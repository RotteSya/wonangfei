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

    @Published private(set) var currentDate: Date
    @Published private(set) var dailyRecords: [String: DailyWageRecord]

    private let userDefaults: UserDefaults
    private var clockTimer: Timer?

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
        currentDate = Date()
        dailyRecords = Self.loadDailyRecords(from: userDefaults)

        closeLastObservedDayIfNeeded(now: currentDate)
        rememberObservedDate(currentDate)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.advanceClock(to: Date())
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    deinit {
        clockTimer?.invalidate()
    }

    var calculation: WageDay {
        calculation(at: currentDate)
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
        if includingLiveToday, DateComponents.calendar.isDate(date, inSameDayAs: currentDate) {
            return makeDailyRecord(for: currentDate, capturedAt: currentDate)
        }

        return dailyRecords[Self.dateKey(for: date)]
    }

    func persistCurrentDaySnapshot() {
        persistDailySnapshot(for: currentDate, capturedAt: Date())
        rememberObservedDate(currentDate)
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

    private func advanceClock(to newDate: Date) {
        if !DateComponents.calendar.isDate(currentDate, inSameDayAs: newDate) {
            persistDailySnapshot(for: Self.endOfDay(for: currentDate), capturedAt: newDate)
        }

        currentDate = newDate
        rememberObservedDate(newDate)
    }

    private func closeLastObservedDayIfNeeded(now: Date) {
        guard let lastObservedDateKey = userDefaults.string(forKey: StorageKey.lastObservedDateKey),
              lastObservedDateKey != Self.dateKey(for: now),
              let lastObservedDate = Self.date(fromDateKey: lastObservedDateKey)
        else {
            return
        }

        persistDailySnapshot(for: Self.endOfDay(for: lastObservedDate), capturedAt: now)
    }

    private func persistDailySnapshot(for date: Date, capturedAt: Date) {
        let record = makeDailyRecord(for: date, capturedAt: capturedAt)
        var nextRecords = dailyRecords
        nextRecords[record.dateKey] = record
        dailyRecords = nextRecords
        saveDailyRecords()
    }

    private func makeDailyRecord(for date: Date, capturedAt: Date) -> DailyWageRecord {
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
            capturedAt: capturedAt
        )
    }

    private func saveDailyRecords() {
        guard let data = try? JSONEncoder().encode(dailyRecords) else { return }
        userDefaults.set(data, forKey: StorageKey.dailyRecords)
    }

    private func rememberObservedDate(_ date: Date) {
        userDefaults.set(Self.dateKey(for: date), forKey: StorageKey.lastObservedDateKey)
    }

    private static func loadDailyRecords(from userDefaults: UserDefaults) -> [String: DailyWageRecord] {
        guard let data = userDefaults.data(forKey: StorageKey.dailyRecords),
              let records = try? JSONDecoder().decode([String: DailyWageRecord].self, from: data)
        else {
            return [:]
        }
        return records
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

    private static func date(fromDateKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func endOfDay(for date: Date) -> Date {
        let startOfDay = DateComponents.calendar.startOfDay(for: date)
        return DateComponents.calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? date
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
    static let lastObservedDateKey = "wnf.records.lastObservedDateKey"
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

    var elapsedPaidMinutes: Int {
        elapsedPaidSeconds / 60
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
