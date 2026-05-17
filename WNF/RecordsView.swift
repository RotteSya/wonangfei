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

private struct RecordSummary {
    var amount: Double = 0
    var recordedDays: Int = 0
    var elapsedPaidSeconds: Int = 0
}

struct RecordsView: View {
    @EnvironmentObject private var state: WageState
    @State private var period: RecordPeriod = .month
    @State private var selectedBarID: RecordBar.ID?

    private var day: WageDay { state.calculation }
    private var bars: [RecordBar] {
        switch period {
        case .week:
            weekBars()
        case .month:
            monthBars()
        case .year:
            yearBars()
        }
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
        summarizeRecords(from: monthStart(for: state.currentDate), through: monthEnd(for: state.currentDate))
    }

    private var unlockedBadgeCount: Int {
        [
            state.dailyRecord(for: state.currentDate, includingLiveToday: true)?.earnedToday ?? 0 > 0,
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
                        MetricTile(label: "已记录", value: "\(recordedDayCount) 天", subtitle: "含今日实时")
                    }

                    achievementCard

                    chartCard

                    badgeCard
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 105)
        }
        .background(WNFTheme.bg)
        .onChange(of: period) { _, _ in
            selectedBarID = nil
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("周期", selection: $period) {
                ForEach(RecordPeriod.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .tint(WNFTheme.yellow)

            Text(period.heroLabel)
                .font(.system(size: 11, weight: .heavy))
                .tracking(2)
                .foregroundStyle(WNFTheme.ink.opacity(0.65))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(WNFFormat.money(total, privacy: state.privacyMode))
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Label("已记录 \(recordedDayCount) 天", systemImage: "calendar")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(WNFTheme.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(WNFTheme.ink, in: Capsule())
                Text("今日金额实时计入")
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
                Spacer()
                Text(chartRangeLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
            }

            BarChart(bars: bars, selectedBarID: $selectedBarID, privacy: state.privacyMode)
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
                Badge(symbol: "sun.max", label: "今日开张", unlocked: (state.dailyRecord(for: state.currentDate, includingLiveToday: true)?.earnedToday ?? 0) > 0)
                Badge(symbol: "fork.knife", label: "午休大师", unlocked: state.hasLunchBreak)
                Badge(symbol: "clock", label: "加班 +1", unlocked: state.includeOvertime)
                Badge(symbol: "yensign.circle", label: "忍 100h", unlocked: currentMonthSummary.elapsedPaidSeconds >= 100 * 60 * 60)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }

    private var calendar: Calendar {
        DateComponents.calendar
    }

    private var todayStart: Date {
        calendar.startOfDay(for: state.currentDate)
    }

    private var daysInCurrentMonth: Int {
        calendar.range(of: .day, in: .month, for: state.currentDate)?.count ?? 31
    }

    private func weekBars() -> [RecordBar] {
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        let titles = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let startOfWeek = weekStart(containing: state.currentDate)

        return labels.indices.map { index in
            let date = calendar.date(byAdding: .day, value: index, to: startOfWeek) ?? startOfWeek
            let summary = summarizeRecords(from: date, through: date)
            let isToday = calendar.isDate(date, inSameDayAs: state.currentDate)
            return RecordBar(
                key: labels[index],
                title: isToday ? "今日" : titles[index],
                amount: summary.amount,
                recordedDays: summary.recordedDays,
                elapsedPaidSeconds: summary.elapsedPaidSeconds,
                isFuture: calendar.startOfDay(for: date) > todayStart,
                isToday: isToday
            )
        }
    }

    private func monthBars() -> [RecordBar] {
        let startOfMonth = monthStart(for: state.currentDate)
        let bucketCount = Int(ceil(Double(daysInCurrentMonth) / 7.0))

        return (0..<bucketCount).map { index in
            let startDay = index * 7 + 1
            let endDay = min(startDay + 6, daysInCurrentMonth)
            let startDate = calendar.date(byAdding: .day, value: startDay - 1, to: startOfMonth) ?? startOfMonth
            let endDate = calendar.date(byAdding: .day, value: endDay - 1, to: startOfMonth) ?? startDate
            let summary = summarizeRecords(from: startDate, through: endDate)
            let isToday = startDate <= todayStart && todayStart <= endDate

            return RecordBar(
                key: "W\(index + 1)",
                title: isToday ? "本周" : "第 \(index + 1) 周",
                amount: summary.amount,
                recordedDays: summary.recordedDays,
                elapsedPaidSeconds: summary.elapsedPaidSeconds,
                isFuture: startDate > todayStart,
                isToday: isToday
            )
        }
    }

    private func yearBars() -> [RecordBar] {
        let year = calendar.component(.year, from: state.currentDate)

        return (1...12).map { month in
            let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? state.currentDate
            let endDate = monthEnd(for: startDate)
            let summary = summarizeRecords(from: startDate, through: endDate)
            let isToday = calendar.isDate(startDate, equalTo: state.currentDate, toGranularity: .month)

            return RecordBar(
                key: "\(month)",
                title: isToday ? "本月" : "\(month) 月",
                amount: summary.amount,
                recordedDays: summary.recordedDays,
                elapsedPaidSeconds: summary.elapsedPaidSeconds,
                isFuture: startDate > todayStart,
                isToday: isToday
            )
        }
    }

    private func summarizeRecords(from startDate: Date, through endDate: Date) -> RecordSummary {
        let startDate = calendar.startOfDay(for: startDate)
        let endDate = min(calendar.startOfDay(for: endDate), todayStart)
        guard startDate <= endDate else { return RecordSummary() }

        return days(from: startDate, through: endDate).reduce(into: RecordSummary()) { summary, date in
            guard let record = state.dailyRecord(for: date, includingLiveToday: true) else { return }
            summary.amount += record.earnedToday
            summary.recordedDays += 1
            summary.elapsedPaidSeconds += record.elapsedPaidSeconds
        }
    }

    private func days(from startDate: Date, through endDate: Date) -> [Date] {
        guard startDate <= endDate else { return [] }

        var dates: [Date] = []
        var date = startDate
        while date <= endDate {
            dates.append(date)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }
        return dates
    }

    private func weekStart(containing date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let mondayOffset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayOffset, to: startOfDay) ?? startOfDay
    }

    private func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func monthEnd(for date: Date) -> Date {
        let startOfMonth = monthStart(for: date)
        return calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? startOfMonth
    }
}

private struct BarChart: View {
    var bars: [RecordBar]
    @Binding var selectedBarID: RecordBar.ID?
    var privacy: Bool

    private var maxAmount: Double {
        max(bars.map(\.amount).max() ?? 1, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: bars.count > 8 ? 4 : 10) {
            ForEach(bars) { bar in
                let selected = selectedBarID == bar.id
                Group {
                    if bar.isFuture {
                        barColumn(bar: bar, selected: selected)
                    } else {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                selectedBarID = selected ? nil : bar.id
                            }
                        } label: {
                            barColumn(bar: bar, selected: selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(bar.title) \(WNFFormat.money(bar.amount, privacy: privacy))")
                        .accessibilityValue(selected ? "已选中" : "未选中")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func barColumn(bar: RecordBar, selected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                if selected {
                    Text("\(bar.title) \(WNFFormat.money(bar.amount, privacy: privacy))")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(WNFTheme.ink, in: Capsule())
                        .offset(y: -104)
                        .fixedSize()
                }

                RoundedRectangle(cornerRadius: bars.count > 8 ? 4 : 8)
                    .fill(barColor(bar: bar, selected: selected))
                    .frame(width: bars.count > 8 ? 16 : 24, height: bar.isFuture ? 6 : max(8, 100 * bar.amount / maxAmount))
                    .offset(y: selected ? -2 : 0)
                    .shadow(color: selected ? .black.opacity(0.24) : .clear, radius: 9, y: 5)
            }
            .frame(height: 130, alignment: .bottom)

            Text(bar.key)
                .font(.system(size: bars.count > 8 ? 9 : 11, weight: bar.isToday || selected ? .heavy : .bold))
                .foregroundStyle(bar.isToday || selected ? WNFTheme.ink : WNFTheme.muted)
        }
    }

    private func barColor(bar: RecordBar, selected: Bool) -> Color {
        if selected { return WNFTheme.ink }
        if bar.isFuture { return Color(red: 0.95, green: 0.92, blue: 0.82) }
        return WNFTheme.yellow
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
