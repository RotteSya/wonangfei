import Foundation

// MARK: - Data Model

enum SettlementSentiment: Int, CaseIterable, Equatable {
    case wisp = 1
    case mild = 2
    case standard = 3
    case heavy = 4

    var stars: Int { rawValue }
    var maxStars: Int { 4 }

    var label: String {
        switch self {
        case .wisp: "今日溜走"
        case .mild: "轻度搬砖"
        case .standard: "稳定窝囊"
        case .heavy: "高强度忍耐"
        }
    }

    var emoji: String {
        switch self {
        case .wisp: "🫥"
        case .mild: "😐"
        case .standard: "😮‍💨"
        case .heavy: "🥲"
        }
    }
}

struct DailySettlement: Equatable {
    var dateKey: String
    var earnedToday: Double
    var elapsedPaidMinutes: Int
    var workdayMinutes: Int
    var progress: Double
    var sentiment: SettlementSentiment
    var streakDays: Int
    var headline: String
    var subCopy: String
    var bestMoment: String
    var cumulativeEarned: Double
    var status: WorkStatus
    var capturedAt: Date

    static func derive(
        from day: WageDay,
        dailyRecords: [String: DailyWageRecord],
        at date: Date = Date()
    ) -> DailySettlement {
        let progress = day.progress
        let sentiment = deriveSentiment(progress: progress, status: day.status)
        let streakDays = deriveStreakDays(
            dailyRecords: dailyRecords,
            includingTodayEarned: day.earnedToday,
            today: date
        )
        let cumulativeEarned = deriveCumulativeEarned(
            dailyRecords: dailyRecords,
            includingTodayEarned: day.earnedToday,
            todayDateKey: WageState.dateKey(for: date)
        )
        let copy = pickCopy(sentiment: sentiment, status: day.status, streakDays: streakDays)
        return DailySettlement(
            dateKey: WageState.dateKey(for: date),
            earnedToday: day.earnedToday,
            elapsedPaidMinutes: day.elapsedPaidMinutes,
            workdayMinutes: day.workdayMinutes,
            progress: progress,
            sentiment: sentiment,
            streakDays: streakDays,
            headline: copy.headline,
            subCopy: copy.subCopy,
            bestMoment: copy.bestMoment,
            cumulativeEarned: cumulativeEarned,
            status: day.status,
            capturedAt: date
        )
    }

    /// Pick a different best-moment line than the current one. Used by the tear gesture
    /// on the settlement card so consecutive long-presses always swap content.
    static func alternateBestMoment(excluding current: String) -> String {
        let pool = bestMomentPool.filter { $0 != current }
        return pool.randomElement() ?? bestMomentPool[0]
    }

    private static func deriveSentiment(progress: Double, status: WorkStatus) -> SettlementSentiment {
        // `.done` always implies the user finished a full workday's worth of
        // elapsed time (WageCalculator caps elapsed at workdayMinutes).
        if status == .done {
            return .heavy
        }
        switch progress {
        case ..<0.05: return .wisp
        case ..<0.35: return .mild
        case ..<0.65: return .standard
        default: return .heavy
        }
    }

    static let bestMomentPool: [String] = [
        "把哈欠忍成了沉默",
        "在工位坐到走不动",
        "看完一封不想回的邮件",
        "听完一场无关的会",
        "对显示器叹了三次气",
        "把咖啡喝凉了第二轮",
        "假装在写代码其实在发呆",
        "把不耐烦藏进了「好的」",
        "刷新邮箱十七次",
        "回了一句「收到，马上处理」"
    ]

    private static func deriveCumulativeEarned(
        dailyRecords: [String: DailyWageRecord],
        includingTodayEarned: Double,
        todayDateKey: String
    ) -> Double {
        // Sum every closed daily record plus today's live amount. The dictionary may also
        // contain a record for today (when it was persisted on scene change), so we replace
        // that with the live amount to avoid double counting.
        let historicalSum = dailyRecords
            .filter { $0.key != todayDateKey }
            .values
            .map(\.earnedToday)
            .reduce(0, +)
        return historicalSum + max(includingTodayEarned, dailyRecords[todayDateKey]?.earnedToday ?? 0)
    }

    private static func deriveStreakDays(
        dailyRecords: [String: DailyWageRecord],
        includingTodayEarned: Double,
        today: Date
    ) -> Int {
        let calendar = DateComponents.calendar
        let todayEarned: Double = includingTodayEarned > 0
            ? includingTodayEarned
            : (dailyRecords[WageState.dateKey(for: today)]?.earnedToday ?? 0)

        // A streak that "ends today" must include today. If today is zero,
        // the streak is zero — don't silently pick up yesterday's history.
        guard todayEarned > 0 else { return 0 }

        let maxStreak = 60
        var streak = 1
        var cursor = today
        while streak < maxStreak {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
            let key = WageState.dateKey(for: previous)
            guard let record = dailyRecords[key], record.earnedToday > 0 else { break }
            streak += 1
        }
        return streak
    }

    private struct CopyPick {
        var headline: String
        var subCopy: String
        var bestMoment: String
    }

    private static func pickCopy(
        sentiment: SettlementSentiment,
        status: WorkStatus,
        streakDays: Int
    ) -> CopyPick {
        let bestMoment = bestMomentPool.randomElement() ?? bestMomentPool[0]

        switch sentiment {
        case .wisp:
            return CopyPick(
                headline: "今天还没真正开张",
                subCopy: streakDays > 1
                    ? "连续 \(streakDays) 天打工的你，偶尔溜走也算合理。"
                    : "今天的窝囊费比较薄，明天再战。",
                bestMoment: bestMoment
            )
        case .mild:
            return CopyPick(
                headline: "轻量忍耐入账",
                subCopy: streakDays > 1
                    ? "连续 \(streakDays) 天，今天的窝囊费小到可以请杯咖啡。"
                    : "今天的窝囊费小，但已经收下了。",
                bestMoment: bestMoment
            )
        case .standard:
            return CopyPick(
                headline: "今天稳定窝囊",
                subCopy: streakDays > 1
                    ? "连续 \(streakDays) 天稳定到账，工位虽冷板凳但票稳。"
                    : "稳定挣进口袋，没赢也没输。",
                bestMoment: bestMoment
            )
        case .heavy:
            return CopyPick(
                headline: "今天全程忍住",
                subCopy: streakDays > 1
                    ? "连续 \(streakDays) 天全勤，今日窝囊费已收下。"
                    : "完整熬完一天，窝囊费已收下。",
                bestMoment: bestMoment
            )
        }
    }
}
