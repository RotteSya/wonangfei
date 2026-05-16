import Foundation

final class WageState: ObservableObject {
    @Published var monthlySalary: Double = 18_000
    @Published var workdaysPerMonth: Int = 26
    @Published var workStart: DateComponents = DateComponents(hour: 9, minute: 30)
    @Published var workEnd: DateComponents = DateComponents(hour: 18, minute: 30)
    @Published var lunchStart: DateComponents = DateComponents(hour: 12, minute: 0)
    @Published var lunchEnd: DateComponents = DateComponents(hour: 13, minute: 0)
    @Published var hasLunchBreak = true
    @Published var includeOvertime = true
    @Published var privacyMode = false
    @Published var selectedWeekdays: Set<Int> = [0, 1, 2, 3, 4]
    @Published private(set) var currentDate = Date()

    private var clockTimer: Timer?

    init() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.currentDate = Date()
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    deinit {
        clockTimer?.invalidate()
    }

    var calculation: WageDay {
        let currentTime = DateComponents.calendar.dateComponents([.hour, .minute, .second], from: currentDate)
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

    func bindingForTime(_ keyPath: ReferenceWritableKeyPath<WageState, DateComponents>) -> Date {
        DateComponents.calendar.date(from: self[keyPath: keyPath]) ?? .now
    }

    func updateTime(_ keyPath: ReferenceWritableKeyPath<WageState, DateComponents>, date: Date) {
        self[keyPath: keyPath] = DateComponents.calendar.dateComponents([.hour, .minute], from: date)
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
