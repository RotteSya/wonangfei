import Foundation

struct WageSummaryRow: Identifiable, Equatable {
    var id: String
    var title: String
    var value: String
}

struct WageDisplayModel {
    var statusLabel: String
    var headline: String
    var mainAmount: Double
    var showsPlus: Bool
    var detailText: String
    var quote: String
    var mascotAsset: String
    var usesAnimatedSprite: Bool
    var summaryRows: [WageSummaryRow]

    init(day: WageDay, settings: WageSettings, now: Date = Date(), calendar: Calendar = .current) {
        let privacy = settings.privacyMode
        let workedDuration = WNFFormat.duration(day.paidWorkMinutes)
        let nextStartHint = WNFFormat.startHint(for: day.nextWorkStartDate, from: now, calendar: calendar)

        switch day.status {
        case .before:
            statusLabel = "尚未开工"
            headline = "今 日 窝 囊 费"
            mainAmount = day.regularEarnedToday
            showsPlus = false
            detailText = "已忍 0min · 离上班 \(nextStartHint)"
            quote = "别急，钱还没开始挣。"
            mascotAsset = "CowFrontSad"
            usesAnimatedSprite = true
        case .morning:
            statusLabel = "上午搬砖中"
            headline = "今 日 窝 囊 费"
            mainAmount = day.regularEarnedToday
            showsPlus = false
            detailText = "已忍 \(workedDuration) · 离下班 \(WNFFormat.duration(day.wallToEndMinutes))"
            quote = "早上的两小时最值钱。"
            mascotAsset = "CowThreeQ"
            usesAnimatedSprite = true
        case .lunch:
            statusLabel = "午休回血"
            headline = "今 日 窝 囊 费"
            mainAmount = day.regularEarnedToday
            showsPlus = false
            detailText = "已忍 \(workedDuration) · 午休回血中"
            quote = "吃饭的时候不发工资。"
            mascotAsset = "CowFrontSad"
            usesAnimatedSprite = true
        case .afternoon:
            statusLabel = "下午挺挺"
            headline = "今 日 窝 囊 费"
            mainAmount = day.regularEarnedToday
            showsPlus = false
            detailText = "已忍 \(workedDuration) · 离下班 \(WNFFormat.duration(day.wallToEndMinutes))"
            quote = "再忍忍，钱在涨。"
            mascotAsset = "CowFrontSad"
            usesAnimatedSprite = true
        case .afterWork:
            statusLabel = "今日通关"
            headline = "今 日 结 算"
            mainAmount = day.regularEarnedToday
            showsPlus = false
            detailText = "今天窝囊了 \(workedDuration) · 今日通关"
            quote = "今天的窝囊费已到账，钱到位，人下线。"
            mascotAsset = "CowThreeQ"
            usesAnimatedSprite = false
        case .overtime:
            statusLabel = "加班回血中"
            headline = "加 班 多 挣"
            mainAmount = day.overtimeEarnedToday
            showsPlus = true
            detailText = "今日总计 \(WNFFormat.moneyDecimal(day.totalEarnedToday, privacy: privacy)) · 已加班 \(WNFFormat.duration(day.overtimeMinutes))"
            quote = "下班后的每一分钟，都是额外回血。"
            mascotAsset = "CowThreeQ"
            usesAnimatedSprite = false
        case .lateNight:
            statusLabel = "夜深收工"
            headline = "今 日 结 算"
            mainAmount = day.regularEarnedToday
            showsPlus = false
            detailText = "今天窝囊了 \(workedDuration) · \(nextStartHint)"
            quote = "今天终于熬完了，先下线。"
            mascotAsset = "CowThreeQ"
            usesAnimatedSprite = false
        case .dayOff:
            statusLabel = "今天不窝囊"
            headline = "今 日 休 息"
            mainAmount = 0
            showsPlus = false
            detailText = "非工作日 · \(nextStartHint)"
            quote = "今天不算窝囊费，认真休息。"
            mascotAsset = "HeroMascot"
            usesAnimatedSprite = false
        }

        summaryRows = [
            WageSummaryRow(id: "regular", title: "今日窝囊费", value: WNFFormat.moneyDecimal(day.regularEarnedToday, privacy: privacy)),
            WageSummaryRow(id: "duration", title: "已窝囊时长", value: workedDuration),
            WageSummaryRow(id: "hourly", title: "时薪", value: privacy ? "¥••.•/h" : String(format: "¥%.1f/h", day.hourlyRate)),
            WageSummaryRow(id: "next", title: "明日提示", value: nextStartHint)
        ]

        if day.status == .overtime {
            summaryRows.insert(
                WageSummaryRow(id: "overtime", title: "加班多挣", value: WNFFormat.signedMoneyDecimal(day.overtimeEarnedToday, privacy: privacy)),
                at: 1
            )
        }
    }
}
