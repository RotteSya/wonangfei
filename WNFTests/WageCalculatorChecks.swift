import Foundation

@main
struct WageCalculatorChecks {
    static func main() {
        let calendar = makeCalendar()
        let friday = makeDate("2026-05-15 19:30:00", calendar: calendar)
        let saturday = makeDate("2026-05-16 20:00:00", calendar: calendar)

        var noOvertime = WageSettings.default
        noOvertime.includeOvertime = false
        let settled = WageCalculator.compute(settings: noOvertime, now: friday, calendar: calendar)
        check(settled.status == .afterWork, "workday after end without overtime settles")
        check(settled.regularEarnedToday == settled.regularTargetToday, "regular earnings settle at regular target")
        check(settled.overtimeEarnedToday == 0, "no overtime amount when overtime disabled")

        var overtime = WageSettings.default
        overtime.includeOvertime = true
        let overtimeDay = WageCalculator.compute(settings: overtime, now: friday, calendar: calendar)
        check(overtimeDay.status == .overtime, "workday after end enters overtime when enabled")
        check(overtimeDay.overtimeMinutes == 60, "overtime minutes count from work end")
        check(overtimeDay.totalEarnedToday > overtimeDay.regularEarnedToday, "total includes overtime amount")

        var ended = WageSettings.default
        ended.includeOvertime = true
        ended.endedWorkdayKey = "2026-05-15"
        let endedDay = WageCalculator.compute(settings: ended, now: friday, calendar: calendar)
        check(endedDay.status == .afterWork, "ending today suppresses overtime")
        check(endedDay.overtimeEarnedToday == 0, "ending today freezes overtime amount")

        var weekend = WageSettings.default
        weekend.includeOvertime = true
        let dayOff = WageCalculator.compute(settings: weekend, now: saturday, calendar: calendar)
        check(dayOff.status == .dayOff, "non-workday stays day off")
        check(dayOff.overtimeEarnedToday == 0, "non-workday never auto-enters overtime")
        check(dayOff.paidWorkMinutes == 0, "non-workday has no paid work minutes")

        let display = WageDisplayModel(day: overtimeDay, settings: overtime, now: friday, calendar: calendar)
        check(display.headline == "加 班 多 挣", "overtime headline is display-layer derived")
        print("WageCalculatorChecks passed")
    }

    private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func makeDate(_ text: String, calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Check failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
