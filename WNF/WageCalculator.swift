import Foundation

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
        includeOvertime: Bool,
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
            let paidThroughSecond = includeOvertime ? nowSecond : min(nowSecond, endSecond)
            elapsedSeconds = paidThroughSecond - startSecond
            let lunchOverlap = max(0, min(paidThroughSecond, lunchEndSecond) - lunchStartSecond)
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
    /// Gregorian calendar whose time zone tracks the system's autoupdating
    /// current time zone — so day boundaries and `dateKey(for:)` follow the
    /// user across time-zone changes (travel, manual override) instead of
    /// being frozen to whatever zone the process launched in.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
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
