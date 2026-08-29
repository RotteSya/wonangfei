import SwiftUI

enum RecordPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "周"
        case .month: "月"
        case .year: "年"
        }
    }

    var heroLabel: String {
        switch self {
        case .week: "本 周 窝 囊 费"
        case .month: "本 月 窝 囊 费"
        case .year: "本 年 窝 囊 费"
        }
    }
}

struct RecordBar: Identifiable {
    var id: String { key }
    var key: String
    var title: String
    var amount: Double
    var recordedDays: Int
    var elapsedPaidSeconds: Int
    var isFuture = false
    var isToday = false
}

struct RecordSummary {
    var amount: Double = 0
    var recordedDays: Int = 0
    var elapsedPaidSeconds: Int = 0
}

struct RecordAggregationInput: Equatable {
    var currentDateKey: String
    var recordsRevision: Int
    var dailyRecords: [String: DailyWageRecord]
    var monthlyRecordSummaries: [String: MonthlyRecordSummary]
    var monthlySalary: Double
    var workdaysPerMonth: Int
    var workStartMinute: Int
    var workEndMinute: Int
    var lunchStartMinute: Int
    var lunchEndMinute: Int
    var hasLunchBreak: Bool
    var includeOvertime: Bool
    var selectedWeekdays: Set<Int>

    init(
        currentDateKey: String,
        recordsRevision: Int,
        dailyRecords: [String: DailyWageRecord],
        monthlyRecordSummaries: [String: MonthlyRecordSummary] = [:],
        monthlySalary: Double,
        workdaysPerMonth: Int,
        workStartMinute: Int,
        workEndMinute: Int,
        lunchStartMinute: Int,
        lunchEndMinute: Int,
        hasLunchBreak: Bool,
        includeOvertime: Bool,
        selectedWeekdays: Set<Int>
    ) {
        self.currentDateKey = currentDateKey
        self.recordsRevision = recordsRevision
        self.dailyRecords = dailyRecords
        self.monthlyRecordSummaries = monthlyRecordSummaries
        self.monthlySalary = monthlySalary
        self.workdaysPerMonth = workdaysPerMonth
        self.workStartMinute = workStartMinute
        self.workEndMinute = workEndMinute
        self.lunchStartMinute = lunchStartMinute
        self.lunchEndMinute = lunchEndMinute
        self.hasLunchBreak = hasLunchBreak
        self.includeOvertime = includeOvertime
        self.selectedWeekdays = selectedWeekdays
    }

    @MainActor
    init(state: WageState) {
        currentDateKey = state.currentDateKey
        recordsRevision = state.recordsRevision
        dailyRecords = state.dailyRecords
        monthlyRecordSummaries = state.monthlyRecordSummaries
        monthlySalary = state.monthlySalary
        workdaysPerMonth = state.workdaysPerMonth
        workStartMinute = state.workStart.minutesInDay
        workEndMinute = state.workEnd.minutesInDay
        lunchStartMinute = state.lunchStart.minutesInDay
        lunchEndMinute = state.lunchEnd.minutesInDay
        hasLunchBreak = state.hasLunchBreak
        includeOvertime = state.includeOvertime
        selectedWeekdays = state.selectedWeekdays
    }

    static func == (lhs: RecordAggregationInput, rhs: RecordAggregationInput) -> Bool {
        lhs.currentDateKey == rhs.currentDateKey
            && lhs.recordsRevision == rhs.recordsRevision
            && lhs.monthlySalary == rhs.monthlySalary
            && lhs.workdaysPerMonth == rhs.workdaysPerMonth
            && lhs.workStartMinute == rhs.workStartMinute
            && lhs.workEndMinute == rhs.workEndMinute
            && lhs.lunchStartMinute == rhs.lunchStartMinute
            && lhs.lunchEndMinute == rhs.lunchEndMinute
            && lhs.hasLunchBreak == rhs.hasLunchBreak
            && lhs.includeOvertime == rhs.includeOvertime
            && lhs.selectedWeekdays == rhs.selectedWeekdays
    }
}

enum RecordAggregator {
    static func make(input: RecordAggregationInput, now: Date = Date()) -> RecordAggregationSnapshot {
        RecordAggregationSnapshot.make(input: input, now: now)
    }

    static func liveTodayRecord(input: RecordAggregationInput, now: Date) -> DailyWageRecord {
        RecordAggregationSnapshot.liveTodayRecord(input: input, now: now)
    }
}

struct RecordAggregationSnapshot {
    static let empty = RecordAggregationSnapshot(
        weekBars: [],
        monthBars: [],
        yearBars: [],
        currentMonthSummary: RecordSummary(),
        daysInCurrentMonth: 31,
        todayEarned: 0
    )

    var weekBars: [RecordBar]
    var monthBars: [RecordBar]
    var yearBars: [RecordBar]
    var currentMonthSummary: RecordSummary
    var daysInCurrentMonth: Int
    var todayEarned: Double

    func bars(for period: RecordPeriod) -> [RecordBar] {
        switch period {
        case .week:
            weekBars
        case .month:
            monthBars
        case .year:
            yearBars
        }
    }

    fileprivate static func make(input: RecordAggregationInput, now: Date) -> RecordAggregationSnapshot {
        let calendar = DateComponents.calendar
        let currentDayStart = WageState.date(fromDateKey: input.currentDateKey) ?? calendar.startOfDay(for: now)
        let liveToday = liveTodayRecord(input: input, now: now)
        let daysInCurrentMonth = calendar.range(of: .day, in: .month, for: currentDayStart)?.count ?? 31

        func record(for date: Date) -> DailyWageRecord? {
            let dateKey = WageState.dateKey(for: date)
            if dateKey == input.currentDateKey {
                return liveToday
            }
            return input.dailyRecords[dateKey]
        }

        func summarizeRecords(from startDate: Date, through endDate: Date) -> RecordSummary {
            let startDate = calendar.startOfDay(for: startDate)
            let endDate = min(calendar.startOfDay(for: endDate), currentDayStart)
            guard startDate <= endDate else { return RecordSummary() }

            var summary = RecordSummary()
            var date = startDate
            while date <= endDate {
                if let record = record(for: date) {
                    summary.amount += record.earnedToday
                    summary.recordedDays += 1
                    summary.elapsedPaidSeconds += record.elapsedPaidSeconds
                }
                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                date = nextDate
            }
            return summary
        }

        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        let titles = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let startOfWeek = weekStart(containing: currentDayStart, calendar: calendar)
        let weekBars = labels.indices.map { index in
            let date = calendar.date(byAdding: .day, value: index, to: startOfWeek) ?? startOfWeek
            let summary = summarizeRecords(from: date, through: date)
            let isToday = calendar.isDate(date, inSameDayAs: currentDayStart)
            return RecordBar(
                key: labels[index],
                title: isToday ? "今日" : titles[index],
                amount: summary.amount,
                recordedDays: summary.recordedDays,
                elapsedPaidSeconds: summary.elapsedPaidSeconds,
                isFuture: calendar.startOfDay(for: date) > currentDayStart,
                isToday: isToday
            )
        }

        let startOfMonth = monthStart(for: currentDayStart, calendar: calendar)
        let bucketCount = Int(ceil(Double(daysInCurrentMonth) / 7.0))
        let monthBars = (0..<bucketCount).map { index in
            let startDay = index * 7 + 1
            let endDay = min(startDay + 6, daysInCurrentMonth)
            let startDate = calendar.date(byAdding: .day, value: startDay - 1, to: startOfMonth) ?? startOfMonth
            let endDate = calendar.date(byAdding: .day, value: endDay - 1, to: startOfMonth) ?? startDate
            let summary = summarizeRecords(from: startDate, through: endDate)
            let isToday = startDate <= currentDayStart && currentDayStart <= endDate

            return RecordBar(
                key: "W\(index + 1)",
                title: isToday ? "本周" : "第 \(index + 1) 周",
                amount: summary.amount,
                recordedDays: summary.recordedDays,
                elapsedPaidSeconds: summary.elapsedPaidSeconds,
                isFuture: startDate > currentDayStart,
                isToday: isToday
            )
        }

        let year = calendar.component(.year, from: currentDayStart)
        let yearBars = (1...12).map { month in
            let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? currentDayStart
            let endDate = monthEnd(for: startDate, calendar: calendar)
            let monthKey = Self.monthKey(for: startDate, calendar: calendar)
            let dailySummary = summarizeRecords(from: startDate, through: endDate)
            let foldedSummary = input.monthlyRecordSummaries[monthKey]
            let summary = combine(dailySummary, foldedSummary)
            let isToday = calendar.isDate(startDate, equalTo: currentDayStart, toGranularity: .month)

            return RecordBar(
                key: "\(month)",
                title: isToday ? "本月" : "\(month) 月",
                amount: summary.amount,
                recordedDays: summary.recordedDays,
                elapsedPaidSeconds: summary.elapsedPaidSeconds,
                isFuture: startDate > currentDayStart,
                isToday: isToday
            )
        }

        return RecordAggregationSnapshot(
            weekBars: weekBars,
            monthBars: monthBars,
            yearBars: yearBars,
            currentMonthSummary: combine(
                summarizeRecords(from: startOfMonth, through: monthEnd(for: currentDayStart, calendar: calendar)),
                input.monthlyRecordSummaries[Self.monthKey(for: currentDayStart, calendar: calendar)]
            ),
            daysInCurrentMonth: daysInCurrentMonth,
            todayEarned: liveToday.earnedToday
        )
    }

    fileprivate static func liveTodayRecord(input: RecordAggregationInput, now: Date) -> DailyWageRecord {
        let currentTime = DateComponents.calendar.dateComponents([.hour, .minute, .second], from: now)
        let day = WageCalculator.compute(
            monthlySalary: input.monthlySalary,
            workdaysPerMonth: input.workdaysPerMonth,
            workStart: .minuteInDay(input.workStartMinute),
            workEnd: .minuteInDay(input.workEndMinute),
            lunchStart: .minuteInDay(input.lunchStartMinute),
            lunchEnd: .minuteInDay(input.lunchEndMinute),
            hasLunchBreak: input.hasLunchBreak,
            includeOvertime: input.includeOvertime,
            now: currentTime
        )
        let currentDayStart = WageState.date(fromDateKey: input.currentDateKey)
            ?? DateComponents.calendar.startOfDay(for: now)
        guard input.selectedWeekdays.contains(weekdayIndex(for: currentDayStart, calendar: DateComponents.calendar)) else {
            return DailyWageRecord(
                dateKey: input.currentDateKey,
                earnedToday: 0,
                targetToday: 0,
                elapsedPaidSeconds: 0,
                workdayMinutes: day.workdayMinutes,
                hourlyRate: day.hourlyRate,
                monthlySalary: input.monthlySalary,
                workdaysPerMonth: input.workdaysPerMonth,
                capturedAt: now,
                source: .observed
            )
        }
        return DailyWageRecord(
            dateKey: input.currentDateKey,
            earnedToday: day.earnedToday,
            targetToday: day.targetToday,
            elapsedPaidSeconds: day.elapsedPaidSeconds,
            workdayMinutes: day.workdayMinutes,
            hourlyRate: day.hourlyRate,
            monthlySalary: input.monthlySalary,
            workdaysPerMonth: input.workdaysPerMonth,
            capturedAt: now,
            source: .observed
        )
    }

    private static func weekdayIndex(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let mondayOffset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayOffset, to: startOfDay) ?? startOfDay
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private static func monthEnd(for date: Date, calendar: Calendar) -> Date {
        let startOfMonth = monthStart(for: date, calendar: calendar)
        return calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? startOfMonth
    }

    private static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func combine(_ dailySummary: RecordSummary, _ foldedSummary: MonthlyRecordSummary?) -> RecordSummary {
        guard let foldedSummary else { return dailySummary }
        return RecordSummary(
            amount: dailySummary.amount + foldedSummary.amount,
            recordedDays: dailySummary.recordedDays + foldedSummary.recordedDays,
            elapsedPaidSeconds: dailySummary.elapsedPaidSeconds + foldedSummary.elapsedPaidSeconds
        )
    }
}

private final class RecordAggregationStore: ObservableObject {
    private var cachedInput: RecordAggregationInput?
    private var cachedSnapshot = RecordAggregationSnapshot.empty

    func snapshot(for input: RecordAggregationInput) -> RecordAggregationSnapshot {
        if cachedInput == input {
            return cachedSnapshot
        }

        let snapshot = RecordAggregator.make(input: input)
        cachedInput = input
        cachedSnapshot = snapshot
        return snapshot
    }
}

struct RecordsView: View {
    @EnvironmentObject private var state: WageState
    @StateObject private var aggregationStore = RecordAggregationStore()
    @State private var period: RecordPeriod = .month
    @State private var selectedBarID: RecordBar.ID?

    private var day: WageDay { state.calculation }
    private var aggregation: RecordAggregationSnapshot {
        aggregationStore.snapshot(for: RecordAggregationInput(state: state))
    }

    private var bars: [RecordBar] {
        aggregation.bars(for: period)
    }

    private var total: Double {
        bars.reduce(0) { $0 + $1.amount }
    }

    private var recordedDayCount: Int {
        bars.reduce(0) { $0 + $1.recordedDays }
    }

    private var periodAverage: Double {
        total / Double(max(1, recordedDayCount))
    }

    private var periodPeak: Double {
        bars.map(\.amount).max() ?? 0
    }

    private var chartRangeLabel: String {
        switch period {
        case .week:
            "周一 - 周日"
        case .month:
            "1 日 - \(daysInCurrentMonth) 日"
        case .year:
            "1 月 - 12 月"
        }
    }

    private var currentMonthSummary: RecordSummary {
        aggregation.currentMonthSummary
    }

    private var todayEarned: Double {
        aggregation.todayEarned
    }

    private var unlockedBadgeCount: Int {
        [
            todayEarned > 0,
            state.hasLunchBreak,
            state.includeOvertime,
            currentMonthSummary.elapsedPaidSeconds >= 100 * 60 * 60
        ].filter(\.self).count
    }

    var body: some View {
        // TopBar lives OUTSIDE the ScrollView so it's a fixed header. Keeping it
        // inside the scroll content put its buttons in a UIScrollView whose
        // delayed-touch handling, combined with the pager's simultaneousGesture
        // drag, swallowed their taps (the privacy eye stopped responding). A
        // fixed header matches the home page and restores reliable hit-testing.
        VStack(spacing: 0) {
            TopBar()
                .padding(.top, 2)

            ScrollView {
                VStack(spacing: 14) {
                    heroCard
                        .cardEntrance(order: 0)

                    // Chart sits right under the headline number — it's the
                    // "show me my data" centerpiece and the home of the
                    // scrub-to-read gesture, so it earns the top of the fold.
                    chartCard
                        .cardEntrance(order: 1)

                    HStack(spacing: 10) {
                        MetricTile(label: period == .week ? "本周日均" : period == .month ? "月日均" : "年日均", value: WNFFormat.money(periodAverage, privacy: state.privacyMode), subtitle: "来自已记录日期", big: true)
                        MetricTile(label: "本期最高", value: WNFFormat.money(periodPeak, privacy: state.privacyMode), subtitle: "单柱最高金额", accent: WNFTheme.coral, big: true)
                    }
                    .cardEntrance(order: 2)

                    HStack(spacing: 10) {
                        MetricTile(label: "时薪", value: state.privacyMode ? "¥••/h" : "¥\(Int(day.hourlyRate))/h", subtitle: "基于税后月薪", accent: WNFTheme.cyan)
                        MetricTile(label: "已记录", value: "\(recordedDayCount) 天", subtitle: "含今日")
                    }
                    .cardEntrance(order: 3)

                    achievementCard
                        .cardEntrance(order: 4)

                    badgeCard
                        .cardEntrance(order: 5)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 105)
            }
        }
        .background(WNFTheme.bg.paperGrain(0.02))
        .onChange(of: period) { _, _ in
            selectedBarID = nil
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PeriodSwitcher(period: $period)

            Text(period.heroLabel)
                .font(WNFTheme.display(12))
                .tracking(2)
                .foregroundStyle(WNFTheme.inkFixed.opacity(0.65))
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: period)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(WNFFormat.money(total, privacy: state.privacyMode))
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.inkFixed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText(value: total))
                    .animation(.spring(response: 0.55, dampingFraction: 0.8), value: total)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Label("已记录 \(recordedDayCount) 天", systemImage: "calendar")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(WNFTheme.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(WNFTheme.inkFixed, in: Capsule())
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: recordedDayCount)
                Text("今日金额计入本期")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WNFTheme.inkFixed.opacity(0.6))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Gold-card surface: brand yellow with printed grain and a slow
            // glint sweeping the diagonal — the "membership card" feel.
            RoundedRectangle(cornerRadius: 28)
                .fill(WNFTheme.yellow)
                .paperGrain(0.034)
                .goldShimmer(period: 7.5, intensity: 0.2)
        }
        .overlay(alignment: .topTrailing) {
            BreathingWatermark()
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: WNFTheme.yellow.opacity(0.24), radius: 20, y: 10)
    }

    private var achievementCard: some View {
        HStack(spacing: 14) {
            MascotPortrait()

            VStack(alignment: .leading, spacing: 4) {
                Text("本 月 成 就")
                    .font(WNFTheme.display(12))
                    .tracking(1.5)
                    .foregroundStyle(WNFTheme.yellow)
                    .goldShimmer(period: 6.0, intensity: 0.6)
                Text("本月已记录 \(currentMonthSummary.recordedDays) 天")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: currentMonthSummary.recordedDays)
                Text("累计到账 \(WNFFormat.money(currentMonthSummary.amount, privacy: state.privacyMode))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(WNFTheme.inkSurface)
                .paperGrain(0.05)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(period == .week ? "本周每日窝囊费" : period == .month ? "本月每周窝囊费" : "本年每月窝囊费")
                    .font(WNFTheme.display(19))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: period)
                Spacer()
                Text(chartRangeLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
            }

            Text("按住图表左右滑动查数")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WNFTheme.muted.opacity(0.75))

            BarChart(bars: bars, selectedBarID: $selectedBarID, privacy: state.privacyMode)
                .id(period)
        }
        .padding(16)
        .background(WNFTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }

    private var badgeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("窝囊徽章")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                Spacer()
                Text("\(unlockedBadgeCount) / 4 解锁")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
            }

            HStack(spacing: 10) {
                Badge(symbol: "sun.max", label: "今日开张", unlocked: todayEarned > 0)
                Badge(symbol: "fork.knife", label: "午休大师", unlocked: state.hasLunchBreak)
                Badge(symbol: "clock", label: "加班 +1", unlocked: state.includeOvertime)
                Badge(symbol: "yensign.circle", label: "忍 100h", unlocked: currentMonthSummary.elapsedPaidSeconds >= 100 * 60 * 60)
            }
        }
        .padding(16)
        .background(WNFTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }

    private var daysInCurrentMonth: Int {
        aggregation.daysInCurrentMonth
    }
}

// MARK: - Entrance choreography

/// Cards rise into place one after another on the page's first appearance —
/// a single welcome, not a recurring effect (scroll back up never replays it).
private struct CardEntrance: ViewModifier {
    var order: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                    return
                }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(order) * 0.06)) {
                    shown = true
                }
            }
    }
}

private extension View {
    func cardEntrance(order: Int) -> some View {
        modifier(CardEntrance(order: order))
    }
}

// MARK: - Period switcher

/// Hand-rolled segmented control: an ink pill slides between the three
/// periods with a spring, riding on the hero card's yellow.
private struct PeriodSwitcher: View {
    @Binding var period: RecordPeriod
    @Namespace private var pillSpace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RecordPeriod.allCases) { item in
                let isOn = period == item
                Button {
                    guard !isOn else { return }
                    WNFHaptics.selection()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        period = item
                    }
                } label: {
                    Text(item.label)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(isOn ? Color.white : WNFTheme.inkFixed.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(WNFTheme.inkFixed)
                                    .matchedGeometryEffect(id: "period-pill", in: pillSpace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.squish(0.94))
                .accessibilityLabel("按\(item.label)查看")
                .accessibilityIdentifier("records.period.\(item.rawValue)")
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(WNFTheme.inkFixed.opacity(0.08), lineWidth: 1))
    }
}

/// The big ¥ watermark on the hero card, breathing almost imperceptibly so
/// the card feels alive even when the totals aren't changing.
private struct BreathingWatermark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swollen = false

    var body: some View {
        Text("¥")
            .font(.system(size: 190, weight: .black, design: .rounded))
            .foregroundStyle(WNFTheme.inkFixed.opacity(0.06))
            .scaleEffect(swollen ? 1.045 : 1, anchor: .topTrailing)
            .offset(x: 26, y: -42)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                    swollen = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// The achievement card's cow: tap for a indignant little wiggle.
private struct MascotPortrait: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggles = 0

    var body: some View {
        Image("HeroMascot")
            .resizable()
            .scaledToFill()
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .keyframeAnimator(initialValue: 0.0, trigger: wiggles) { view, angle in
                view.rotationEffect(.degrees(angle))
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0, duration: 0.0001)
                    CubicKeyframe(-7, duration: 0.07)
                    CubicKeyframe(6, duration: 0.11)
                    CubicKeyframe(-3.5, duration: 0.11)
                    CubicKeyframe(1.6, duration: 0.10)
                    CubicKeyframe(0, duration: 0.10)
                }
            }
            .onTapGesture {
                guard !reduceMotion else { return }
                wiggles += 1
                WNFHaptics.soft(intensity: 0.7)
            }
            .accessibilityLabel("窝囊牛")
    }
}

private struct BarChart: View {
    var bars: [RecordBar]
    @Binding var selectedBarID: RecordBar.ID?
    var privacy: Bool

    @EnvironmentObject private var gestureArbiter: HorizontalGestureArbiter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var scrubbing = false
    @State private var scrubMoved = false
    @State private var scrubStartID: RecordBar.ID?

    private var maxAmount: Double {
        max(bars.map(\.amount).max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: bars.count > 8 ? 4 : 10) {
                ForEach(bars) { bar in
                    barColumn(bar: bar, selected: selectedBarID == bar.id)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(bar.title) \(WNFFormat.money(bar.amount, privacy: privacy))")
                        .accessibilityValue(selectedBarID == bar.id ? "已选中" : "未选中")
                        .accessibilityAction {
                            selectedBarID = selectedBarID == bar.id ? nil : bar.id
                        }
                }
            }
            .contentShape(Rectangle())
            // Scrub to read: touch lands on a bar, dragging sweeps the
            // selection across with a haptic tick per boundary — like running
            // a finger along a row of piano keys. A no-move tap toggles.
            .gesture(scrubGesture(width: proxy.size.width))
            .accessibilityIdentifier("records.chart")
        }
        .frame(height: 152)
        .onAppear {
            guard !grown else { return }
            if reduceMotion {
                grown = true
            } else {
                withAnimation(nil) { grown = false }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) {
                    grown = true
                }
            }
        }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard gestureArbiter.claim(.chartScrub) else { return }
                let index = barIndex(at: value.location.x, width: width)
                guard bars.indices.contains(index) else { return }
                let bar = bars[index]

                if !scrubbing {
                    scrubbing = true
                    scrubMoved = false
                    scrubStartID = selectedBarID
                }
                if abs(value.translation.width) > 6 || abs(value.translation.height) > 6 {
                    scrubMoved = true
                }

                guard !bar.isFuture else { return }
                if selectedBarID != bar.id {
                    selectedBarID = bar.id
                    WNFHaptics.selection()
                }
            }
            .onEnded { value in
                defer {
                    scrubbing = false
                    gestureArbiter.release(.chartScrub)
                }
                guard scrubbing else { return }
                // A stationary tap on the already-selected bar deselects it.
                if !scrubMoved {
                    let index = barIndex(at: value.location.x, width: width)
                    if bars.indices.contains(index), bars[index].id == scrubStartID {
                        selectedBarID = nil
                    }
                }
            }
    }

    private func barIndex(at x: CGFloat, width: CGFloat) -> Int {
        guard width > 0, !bars.isEmpty else { return 0 }
        let slot = width / CGFloat(bars.count)
        return min(bars.count - 1, max(0, Int(x / slot)))
    }

    private func barColumn(bar: RecordBar, selected: Bool) -> some View {
        let index = bars.firstIndex { $0.id == bar.id } ?? 0
        let height = bar.isFuture ? 6 : max(8, 100 * bar.amount / maxAmount)

        return VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                if selected {
                    Text("\(bar.title) \(WNFFormat.money(bar.amount, privacy: privacy))")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(WNFTheme.inkSurface, in: Capsule())
                        .offset(y: -104)
                        .fixedSize()
                        .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: selectedBarID)
                }

                barBody(bar: bar, selected: selected, height: height)
                    // Grow from the floor with a per-bar stagger when the
                    // period changes (`.id(period)` upstream resets `grown`).
                    .scaleEffect(y: grown ? 1 : 0.04, anchor: .bottom)
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.2)
                            : .spring(response: 0.5, dampingFraction: 0.62).delay(Double(index) * 0.038),
                        value: grown
                    )
            }
            .frame(height: 130, alignment: .bottom)

            Text(bar.key)
                .font(.system(size: bars.count > 8 ? 9 : 11, weight: bar.isToday || selected ? .heavy : .bold))
                .foregroundStyle(bar.isToday || selected ? WNFTheme.ink : WNFTheme.muted)
        }
    }

    @ViewBuilder
    private func barBody(bar: RecordBar, selected: Bool, height: CGFloat) -> some View {
        let radius: CGFloat = bars.count > 8 ? 4 : 8
        let width: CGFloat = bars.count > 8 ? 16 : 24

        let base = RoundedRectangle(cornerRadius: radius)
            .fill(barFill(bar: bar, selected: selected))
            .frame(width: width, height: height)
            .offset(y: selected ? -2 : 0)
            .shadow(color: selected ? .black.opacity(0.24) : .clear, radius: 9, y: 5)

        if bar.isToday && !selected && !reduceMotion {
            // Today's bar breathes a soft gold halo — "this one is still
            // filling up" — without stealing the chart's calm.
            base.phaseAnimator([false, true]) { view, glowing in
                view.shadow(
                    color: WNFTheme.gold.opacity(glowing ? 0.65 : 0.15),
                    radius: glowing ? 10 : 4,
                    y: 2
                )
            } animation: { _ in
                .easeInOut(duration: 1.4)
            }
        } else {
            base
        }
    }

    private func barFill(bar: RecordBar, selected: Bool) -> AnyShapeStyle {
        if selected {
            return AnyShapeStyle(WNFTheme.ink)
        }
        if bar.isFuture {
            return AnyShapeStyle(Color(red: 0.95, green: 0.92, blue: 0.82))
        }
        if bar.isToday {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.88, blue: 0.45), WNFTheme.yellow],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(WNFTheme.yellow)
    }
}

private struct Badge: View {
    var symbol: String
    var label: String
    var unlocked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggles = 0

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(WNFTheme.ink)
                .frame(width: 50, height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(unlocked ? WNFTheme.yellow : WNFTheme.surfaceSoft)
                        // Earned badges glint like enamel pins; locked ones
                        // stay matte (the shimmer clock never runs for them).
                        .goldShimmer(period: 4.8, intensity: 0.5, isActive: unlocked)
                }
                .saturation(unlocked ? 1 : 0)
                .opacity(unlocked ? 1 : 0.48)
                .keyframeAnimator(initialValue: 0.0, trigger: wiggles) { view, angle in
                    view.rotationEffect(.degrees(angle))
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(0, duration: 0.0001)
                        CubicKeyframe(-9, duration: 0.07)
                        CubicKeyframe(7.5, duration: 0.11)
                        CubicKeyframe(-4, duration: 0.11)
                        CubicKeyframe(2, duration: 0.10)
                        CubicKeyframe(0, duration: 0.10)
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: unlocked)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(WNFTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !reduceMotion else { return }
            wiggles += 1
            WNFHaptics.soft(intensity: unlocked ? 0.8 : 0.4)
        }
        .accessibilityLabel("\(label)徽章")
        .accessibilityValue(unlocked ? "已解锁" : "未解锁")
    }
}

#Preview {
    RecordsView()
        .environmentObject(WageState())
        .environmentObject(HorizontalGestureArbiter())
}
