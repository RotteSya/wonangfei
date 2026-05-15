import Foundation

enum WNFSharedStore {
    static let appGroupID = "group.com.wonangfei.app"
    static let appSettingsKey = "wnf.settings.v1"
    static let widgetSettingsKey = "wnf.widget.settings.v1"

    static var appDefaults: UserDefaults {
        .standard
    }

    static var widgetDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func loadSettings(from defaults: UserDefaults, key: String) -> WageSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WageSettings.self, from: data)
    }

    static func save(_ settings: WageSettings, to defaults: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

struct WageTime: Codable, Hashable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    init(_ components: DateComponents) {
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    var minutesInDay: Int {
        hour * 60 + minute
    }

    var clockText: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct WageSettings: Codable, Equatable {
    var monthlySalary: Double
    var workdaysPerMonth: Int
    var workStart: WageTime
    var workEnd: WageTime
    var lunchStart: WageTime
    var lunchEnd: WageTime
    var hasLunchBreak: Bool
    var includeOvertime: Bool
    var overtimeMultiplier: Double
    var privacyMode: Bool
    var selectedWeekdays: Set<Int>
    var endedWorkdayKey: String?

    static let `default` = WageSettings(
        monthlySalary: 18_000,
        workdaysPerMonth: 26,
        workStart: WageTime(hour: 9, minute: 30),
        workEnd: WageTime(hour: 18, minute: 30),
        lunchStart: WageTime(hour: 12, minute: 0),
        lunchEnd: WageTime(hour: 13, minute: 0),
        hasLunchBreak: true,
        includeOvertime: true,
        overtimeMultiplier: 1.0,
        privacyMode: false,
        selectedWeekdays: [0, 1, 2, 3, 4],
        endedWorkdayKey: nil
    )
}

struct WageDay {
    var startMinute: Int
    var endMinute: Int
    var lunchStartMinute: Int
    var lunchEndMinute: Int
    var regularWorkdayMinutes: Int
    var hourlyRate: Double
    var paidWorkMinutes: Int
    var paidWorkSeconds: Int
    var overtimeMinutes: Int
    var overtimeSeconds: Int
    var regularEarnedToday: Double
    var overtimeEarnedToday: Double
    var totalEarnedToday: Double
    var regularTargetToday: Double
    var status: WorkStatus
    var wallToEndMinutes: Int
    var nextWorkStartDate: Date?
    var isWorkday: Bool

    var progress: Double {
        let workdaySeconds = regularWorkdayMinutes * 60
        guard workdaySeconds > 0 else { return 0 }
        return min(1, max(0, Double(paidWorkSeconds) / Double(workdaySeconds)))
    }

    var workdayMinutes: Int { regularWorkdayMinutes }
    var elapsedPaidMinutes: Int { paidWorkMinutes }
    var elapsedPaidSeconds: Int { paidWorkSeconds }
    var earnedToday: Double { totalEarnedToday }
    var targetToday: Double { regularTargetToday }
}

enum WorkStatus: String, Codable, Equatable {
    case before
    case morning
    case lunch
    case afternoon
    case afterWork
    case overtime
    case lateNight
    case dayOff
}

enum WageCalendar {
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func weekdayIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func date(onSameDayAs date: Date, minuteOfDay: Int, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minuteOfDay, to: startOfDay) ?? date
    }

    static func nextWorkStartDate(after date: Date, settings: WageSettings, calendar: Calendar = .current) -> Date? {
        let startMinute = settings.workStart.minutesInDay
        for offset in 0..<14 {
            guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else {
                continue
            }
            let weekday = weekdayIndex(for: candidateDay, calendar: calendar)
            guard settings.selectedWeekdays.contains(weekday) else { continue }

            let candidateStart = self.date(onSameDayAs: candidateDay, minuteOfDay: startMinute, calendar: calendar)
            if candidateStart > date {
                return candidateStart
            }
        }
        return nil
    }
}

enum WageCalculator {
    static func compute(
        settings: WageSettings,
        now: Date,
        calendar: Calendar = .current
    ) -> WageDay {
        let startMinute = settings.workStart.minutesInDay
        let endMinute = settings.workEnd.minutesInDay
        let rawLunchStart = settings.hasLunchBreak ? settings.lunchStart.minutesInDay : endMinute
        let rawLunchEnd = settings.hasLunchBreak ? settings.lunchEnd.minutesInDay : endMinute
        let lunchStartMinute = min(rawLunchStart, rawLunchEnd)
        let lunchEndMinute = max(rawLunchStart, rawLunchEnd)
        let lunchLength = max(0, min(endMinute, lunchEndMinute) - max(startMinute, lunchStartMinute))
        let regularWorkdayMinutes = max(1, endMinute - startMinute - lunchLength)
        let hourlyRate = settings.monthlySalary / (Double(max(1, settings.workdaysPerMonth)) * (Double(regularWorkdayMinutes) / 60))

        let nowComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
        let nowSecond = ((nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)) * 60 + (nowComponents.second ?? 0)
        let nowMinute = nowSecond / 60
        let startSecond = startMinute * 60
        let endSecond = endMinute * 60
        let lunchStartSecond = lunchStartMinute * 60
        let lunchEndSecond = lunchEndMinute * 60
        let isWorkday = settings.selectedWeekdays.contains(WageCalendar.weekdayIndex(for: now, calendar: calendar))
        let todayKey = WageCalendar.dayKey(for: now, calendar: calendar)
        let endedToday = settings.endedWorkdayKey == todayKey
        let nextStart = WageCalendar.nextWorkStartDate(after: now, settings: settings, calendar: calendar)

        guard isWorkday else {
            return WageDay(
                startMinute: startMinute,
                endMinute: endMinute,
                lunchStartMinute: lunchStartMinute,
                lunchEndMinute: lunchEndMinute,
                regularWorkdayMinutes: regularWorkdayMinutes,
                hourlyRate: hourlyRate,
                paidWorkMinutes: 0,
                paidWorkSeconds: 0,
                overtimeMinutes: 0,
                overtimeSeconds: 0,
                regularEarnedToday: 0,
                overtimeEarnedToday: 0,
                totalEarnedToday: 0,
                regularTargetToday: hourlyRate / 60 * Double(regularWorkdayMinutes),
                status: .dayOff,
                wallToEndMinutes: 0,
                nextWorkStartDate: nextStart,
                isWorkday: false
            )
        }

        var paidSeconds = 0
        if nowSecond > startSecond {
            paidSeconds = min(nowSecond, endSecond) - startSecond
            let lunchOverlap = max(0, min(nowSecond, lunchEndSecond) - lunchStartSecond)
            paidSeconds = max(0, paidSeconds - lunchOverlap)
        }

        let overtimeSeconds: Int
        if settings.includeOvertime && !endedToday && nowSecond > endSecond {
            overtimeSeconds = nowSecond - endSecond
        } else {
            overtimeSeconds = 0
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
        } else if overtimeSeconds > 0 {
            status = .overtime
        } else if nowMinute >= 23 * 60 {
            status = .lateNight
        } else {
            status = .afterWork
        }

        let regularEarnedToday = hourlyRate / 3600 * Double(paidSeconds)
        let overtimeEarnedToday = hourlyRate / 3600 * Double(overtimeSeconds) * max(0, settings.overtimeMultiplier)
        let totalEarnedToday = regularEarnedToday + overtimeEarnedToday
        let regularTargetToday = hourlyRate / 60 * Double(regularWorkdayMinutes)

        return WageDay(
            startMinute: startMinute,
            endMinute: endMinute,
            lunchStartMinute: lunchStartMinute,
            lunchEndMinute: lunchEndMinute,
            regularWorkdayMinutes: regularWorkdayMinutes,
            hourlyRate: hourlyRate,
            paidWorkMinutes: paidSeconds / 60,
            paidWorkSeconds: paidSeconds,
            overtimeMinutes: overtimeSeconds / 60,
            overtimeSeconds: overtimeSeconds,
            regularEarnedToday: regularEarnedToday,
            overtimeEarnedToday: overtimeEarnedToday,
            totalEarnedToday: totalEarnedToday,
            regularTargetToday: regularTargetToday,
            status: status,
            wallToEndMinutes: max(0, Int(ceil(Double(endSecond - nowSecond) / 60))),
            nextWorkStartDate: nextStart,
            isWorkday: true
        )
    }
}

extension DateComponents {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

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

    static func signedMoneyDecimal(_ value: Double, privacy: Bool) -> String {
        privacy ? "+¥•••.••" : String(format: "+¥%.2f", value)
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours <= 0 { return "\(mins)min" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h\(mins)min"
    }

    static func startHint(for date: Date?, from now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "明日开工待定" }
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if calendar.isDateInToday(date) {
            return "今日 \(clockText(for: date, calendar: calendar)) 开工"
        }
        if minutes < 48 * 60 {
            return "明日 \(clockText(for: date, calendar: calendar)) 开工"
        }
        let weekday = calendar.component(.weekday, from: date)
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        return "周\(labels[max(0, min(6, weekday - 1))]) \(clockText(for: date, calendar: calendar)) 开工"
    }

    private static func clockText(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
