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

    /// Position in the segmented control; drives direction-aware transitions.
    var order: Int {
        RecordPeriod.allCases.firstIndex(of: self) ?? 0
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
    @State private var periodDirection = 1

    /// Routes segment changes through one place so the slide direction is fixed
    /// before the animated state change renders, and every period-driven
    /// transition (chart slide, numeric rolls, hero sheen) shares one spring.
    private var periodSelection: Binding<RecordPeriod> {
        Binding(
            get: { period },
            set: { newValue in
                guard newValue != period else { return }
                periodDirection = newValue.order > period.order ? 1 : -1
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    period = newValue
                    selectedBarID = nil
                }
            }
        )
    }

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
        ScrollView {
            VStack(spacing: 14) {
                TopBar()
                    .padding(.top, 2)

                VStack(spacing: 14) {
                    heroCard

                    HStack(spacing: 10) {
                        MetricTile(label: period == .week ? "本周日均" : period == .month ? "月日均" : "年日均", value: WNFFormat.money(periodAverage, privacy: state.privacyMode), subtitle: "来自已记录日期", big: true)
                        MetricTile(label: "本期最高", value: WNFFormat.money(periodPeak, privacy: state.privacyMode), subtitle: "单柱最高金额", accent: WNFTheme.coral, big: true)
                    }

                    HStack(spacing: 10) {
                        MetricTile(label: "时薪", value: state.privacyMode ? "¥••/h" : "¥\(Int(day.hourlyRate))/h", subtitle: "基于税后月薪", accent: WNFTheme.cyan)
                        MetricTile(label: "已记录", value: "\(recordedDayCount) 天", subtitle: "含今日")
                    }

                    achievementCard

                    chartCard

                    badgeCard
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 105)
        }
        .background {
            ZStack {
                WNFTheme.bg
                AuroraBackdrop(intensity: 0.65)
            }
            .ignoresSafeArea()
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ElasticSegmentedControl(
                items: RecordPeriod.allCases,
                selection: periodSelection,
                label: { $0.label },
                containerFill: Color.white.opacity(0.4),
                pillFill: WNFTheme.ink,
                selectedLabelColor: WNFTheme.yellow,
                idleLabelColor: WNFTheme.ink.opacity(0.55)
            )

            Text(period.heroLabel)
                .font(.system(size: 11, weight: .heavy))
                .tracking(2)
                .foregroundStyle(WNFTheme.ink.opacity(0.65))
                .contentTransition(.opacity)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(WNFFormat.money(total, privacy: state.privacyMode))
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText(value: total))
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Label("已记录 \(recordedDayCount) 天", systemImage: "calendar")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(WNFTheme.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(WNFTheme.ink, in: Capsule())
                    .contentTransition(.numericText())
                Text("今日金额计入本期")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WNFTheme.ink.opacity(0.6))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WNFTheme.yellow, in: RoundedRectangle(cornerRadius: 28))
        .overlay(alignment: .topTrailing) {
            Text("¥")
                .font(.system(size: 190, weight: .black, design: .rounded))
                .foregroundStyle(WNFTheme.ink.opacity(0.06))
                .offset(x: 26, y: -42)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .sheenSweep(on: period, duration: 0.9, bandWidth: 0.22, strength: 0.35)
        .shadow(color: WNFTheme.yellow.opacity(0.24), radius: 20, y: 10)
    }

    private var achievementCard: some View {
        HStack(spacing: 14) {
            Image("HeroMascot")
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 4) {
                Text("本 月 成 就")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(WNFTheme.yellow)
                Text("本月已记录 \(currentMonthSummary.recordedDays) 天")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("累计到账 \(WNFFormat.money(currentMonthSummary.amount, privacy: state.privacyMode))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(16)
        .background(WNFTheme.ink, in: RoundedRectangle(cornerRadius: 22))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(period == .week ? "本周每日窝囊费" : period == .month ? "本月每周窝囊费" : "本年每月窝囊费")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .contentTransition(.opacity)
                Spacer()
                Text(chartRangeLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
                    .contentTransition(.opacity)
            }

            // `.id(period)` swaps the chart wholesale so bars re-run their
            // staggered entrance; the slide direction follows the segment order.
            ZStack {
                BarChart(bars: bars, selectedBarID: $selectedBarID, privacy: state.privacyMode)
                    .id(period)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: periodDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: periodDirection >= 0 ? .leading : .trailing).combined(with: .opacity)
                        )
                    )
            }
            .clipped()
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }

    private var daysInCurrentMonth: Int {
        aggregation.daysInCurrentMonth
    }
}

/// Scrubbable bar chart: drag a finger across to sweep the selection (with a
/// selection tick per bar), tap a bar to pin it, tap the pinned bar to clear.
/// Bars grow in with a per-bar staggered spring whenever the chart instance is
/// swapped (the parent re-keys it with `.id(period)`), and the floating
/// tooltip glides between bars instead of popping per column.
private struct BarChart: View {
    var bars: [RecordBar]
    @Binding var selectedBarID: RecordBar.ID?
    var privacy: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var isScrubbing = false
    @State private var scrubMoved = false
    @State private var scrubStartSelection: RecordBar.ID?

    private var maxAmount: Double {
        max(bars.map(\.amount).max() ?? 1, 1)
    }

    private var compact: Bool {
        bars.count > 8
    }

    private var selectedIndex: Int? {
        guard let selectedBarID else { return nil }
        return bars.firstIndex { $0.id == selectedBarID }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let count = max(bars.count, 1)
            let slot = width / CGFloat(count)

            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                        column(bar: bar, index: index)
                            .frame(width: slot, height: 130, alignment: .bottom)
                    }
                }
                .frame(width: width, height: 130, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(scrubGesture(slot: slot))
                .overlay(alignment: .topLeading) {
                    tooltipOverlay(slot: slot, width: width)
                }

                HStack(spacing: 0) {
                    ForEach(bars) { bar in
                        let highlighted = bar.isToday || bar.id == selectedBarID
                        Text(bar.key)
                            .font(.system(size: compact ? 9 : 11, weight: highlighted ? .heavy : .bold))
                            .foregroundStyle(highlighted ? WNFTheme.ink : WNFTheme.muted)
                            .frame(width: slot)
                    }
                }
            }
        }
        .frame(height: 152)
        .sensoryFeedback(.selection, trigger: selectedBarID)
        .onAppear {
            appeared = true
        }
    }

    private func column(bar: RecordBar, index: Int) -> some View {
        let selected = bar.id == selectedBarID
        return RoundedRectangle(cornerRadius: compact ? 4 : 8)
            .fill(barColor(bar: bar, selected: selected))
            .frame(width: compact ? 16 : 24, height: barHeight(for: bar))
            .scaleEffect(y: appeared ? 1 : 0.05, anchor: .bottom)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.55, dampingFraction: 0.7).delay(Double(index) * 0.04),
                value: appeared
            )
            .offset(y: selected ? -3 : 0)
            .shadow(color: selected ? .black.opacity(0.22) : .clear, radius: 9, y: 5)
            .modifier(TodayBarGlow(isActive: bar.isToday && !selected && !reduceMotion))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(bar.title) \(WNFFormat.money(bar.amount, privacy: privacy))")
            .accessibilityValue(selected ? "已选中" : "未选中")
            .accessibilityAddTraits(bar.isFuture ? [] : .isButton)
            .accessibilityAction {
                guard !bar.isFuture else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    selectedBarID = selected ? nil : bar.id
                }
            }
    }

    private func barHeight(for bar: RecordBar) -> CGFloat {
        bar.isFuture ? 6 : max(8, 100 * bar.amount / maxAmount)
    }

    @ViewBuilder
    private func tooltipOverlay(slot: CGFloat, width: CGFloat) -> some View {
        if let index = selectedIndex {
            let bar = bars[index]
            let x = min(max(slot * (CGFloat(index) + 0.5), 52), max(width - 52, 52))
            let y = max(130 - barHeight(for: bar) - 20, 14)
            Text("\(bar.title) \(WNFFormat.money(bar.amount, privacy: privacy))")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(WNFTheme.ink, in: Capsule())
                .fixedSize()
                .position(x: x, y: y)
                .animation(.spring(response: 0.32, dampingFraction: 0.74), value: index)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private func scrubGesture(slot: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isScrubbing {
                    isScrubbing = true
                    scrubStartSelection = selectedBarID
                    scrubMoved = false
                }
                if abs(value.translation.width) > 6 || abs(value.translation.height) > 6 {
                    scrubMoved = true
                }
                // A clearly vertical drag is page-scroll intent, not a scrub —
                // leave the selection alone so scrolling over the chart is safe.
                if abs(value.translation.height) > 12,
                   abs(value.translation.height) > abs(value.translation.width) * 1.6 {
                    return
                }
                let index = min(max(Int(value.location.x / slot), 0), bars.count - 1)
                let bar = bars[index]
                guard !bar.isFuture else { return }
                if selectedBarID != bar.id {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedBarID = bar.id
                    }
                }
            }
            .onEnded { _ in
                // A stationary tap on the already-pinned bar unpins it; any
                // actual scrub keeps the last bar it touched.
                if !scrubMoved, let started = scrubStartSelection, started == selectedBarID {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedBarID = nil
                    }
                }
                isScrubbing = false
            }
    }

    private func barColor(bar: RecordBar, selected: Bool) -> Color {
        if selected { return WNFTheme.ink }
        if bar.isFuture { return Color(red: 0.95, green: 0.92, blue: 0.82) }
        return WNFTheme.yellow
    }
}

/// Gentle breathing gold halo on the "today" bar so the live column reads as
/// alive without stealing focus from a pinned selection.
private struct TodayBarGlow: ViewModifier {
    var isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.phaseAnimator([0.25, 0.7]) { view, glow in
                view.shadow(color: WNFTheme.gold.opacity(glow), radius: 7, y: 2)
            } animation: { _ in
                .easeInOut(duration: 1.5)
            }
        } else {
            content
        }
    }
}

private struct Badge: View {
    var symbol: String
    var label: String
    var unlocked: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(WNFTheme.ink)
                .frame(width: 50, height: 50)
                .background(unlocked ? WNFTheme.yellow : Color(red: 0.95, green: 0.92, blue: 0.82), in: RoundedRectangle(cornerRadius: 16))
                .saturation(unlocked ? 1 : 0)
                .opacity(unlocked ? 1 : 0.48)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(WNFTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    RecordsView()
        .environmentObject(WageState())
}
