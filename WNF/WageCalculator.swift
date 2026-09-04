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
    var overtimeSeconds: Int = 0
    var overtimeEarned: Double = 0

    var progress: Double {
        let workdaySeconds = workdayMinutes * 60
        guard workdaySeconds > 0 else { return 0 }
        return min(1, max(0, Double(elapsedPaidSeconds) / Double(workdaySeconds)))
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
        let nowSecond = now.preciseSecondsInDay

        guard endMinute > startMinute else {
            return WageDay(
                startMinute: startMinute,
                endMinute: endMinute,
                lunchStartMinute: lunchStartMinute,
                lunchEndMinute: lunchEndMinute,
                workdayMinutes: 0,
                hourlyRate: 0,
                elapsedPaidMinutes: 0,
                elapsedPaidSeconds: 0,
                earnedToday: 0,
                targetToday: 0,
                status: nowSecond < Double(startMinute * 60) ? .before : .done,
                wallToEndMinutes: 0
            )
        }

        let effectiveLunchStartMinute = max(startMinute, lunchStartMinute)
        let effectiveLunchEndMinute = min(endMinute, lunchEndMinute)
        let lunchLength = max(0, effectiveLunchEndMinute - effectiveLunchStartMinute)
        let workdayMinutes = max(1, endMinute - startMinute - lunchLength)
        let hourlyRate = monthlySalary / (Double(max(1, workdaysPerMonth)) * (Double(workdayMinutes) / 60))
        let startSecond = startMinute * 60
        let endSecond = endMinute * 60
        let lunchStartSecond = effectiveLunchStartMinute * 60
        let lunchEndSecond = effectiveLunchEndMinute * 60
        let hasEffectiveLunch = lunchEndSecond > lunchStartSecond

        // The configured work window is the source of truth. `now` is sampled
        // directly instead of accumulated from timer ticks, then clamped to the
        // closed interval [start, end]. This makes background suspension, device
        // sleep, delayed callbacks, and clock jumps incapable of adding time
        // beyond the exact off-duty boundary.
        let paidThroughSecond = min(max(nowSecond, Double(startSecond)), Double(endSecond))
        let lunchOverlap = hasEffectiveLunch
            ? max(0, min(paidThroughSecond, Double(lunchEndSecond)) - Double(lunchStartSecond))
            : 0
        let elapsedPaidDuration = max(0, paidThroughSecond - Double(startSecond) - lunchOverlap)
        let elapsedSeconds = Int(elapsedPaidDuration.rounded(.down))

        let status: WorkStatus
        if nowSecond < Double(startSecond) {
            status = .before
        } else if hasEffectiveLunch == false, nowSecond < Double(endSecond) {
            status = .morning
        } else if nowSecond < Double(lunchStartSecond) {
            status = .morning
        } else if nowSecond < Double(lunchEndSecond) {
            status = .lunch
        } else if nowSecond < Double(endSecond) {
            status = .afternoon
        } else {
            status = .done
        }

        let earnedToday = hourlyRate / 3600 * elapsedPaidDuration
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
            wallToEndMinutes: max(0, Int(ceil((Double(endSecond) - nowSecond) / 60))),
            overtimeSeconds: 0,
            overtimeEarned: 0
        )
    }

    /// Stacks overtime on a normal-day result without changing the base hourly
    /// rate, `targetToday`, or `workdayMinutes`. Progress stays capped at 1.0.
    static func applyingOvertime(
        to baseDay: WageDay,
        normalEnd: Date,
        overtimeEnd: Date?,
        now: Date
    ) -> WageDay {
        var day = baseDay
        day.overtimeSeconds = 0
        day.overtimeEarned = 0

        guard let overtimeEnd, overtimeEnd > normalEnd, now > normalEnd else {
            return day
        }

        let effectiveEnd = min(now, overtimeEnd)
        let overtimeSeconds = max(0, Int(effectiveEnd.timeIntervalSince(normalEnd).rounded(.down)))
        let overtimeEarned = baseDay.hourlyRate / 3600 * Double(overtimeSeconds)

        day.overtimeSeconds = overtimeSeconds
        day.overtimeEarned = overtimeEarned
        day.elapsedPaidSeconds = baseDay.elapsedPaidSeconds + overtimeSeconds
        day.elapsedPaidMinutes = day.elapsedPaidSeconds / 60
        day.earnedToday = baseDay.earnedToday + overtimeEarned
        day.wallToEndMinutes = now < overtimeEnd
            ? max(0, Int(ceil(overtimeEnd.timeIntervalSince(now) / 60)))
            : 0
        return day
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

    /// Wall-clock position with sub-second precision. Work times are civil-time
    /// settings, so the caller first resolves `Date` in the autoupdating local
    /// calendar; the UTC offset never leaks into the salary boundary math.
    var preciseSecondsInDay: TimeInterval {
        let wholeSeconds = TimeInterval(secondsInDay)
        let fractionalSecond = TimeInterval(nanosecond ?? 0) / 1_000_000_000
        return wholeSeconds + fractionalSecond
    }

    var clockText: String {
        String(format: "%02d:%02d", hour ?? 0, minute ?? 0)
    }
}
