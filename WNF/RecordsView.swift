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
    var multiplier: Double
    var isFuture = false
    var isToday = false
}

struct RecordsView: View {
    @EnvironmentObject private var state: WageState
    @State private var period: RecordPeriod = .month
    @State private var selectedBarID: RecordBar.ID?

    private var day: WageDay { state.calculation }
    private var bars: [RecordBar] {
        switch period {
        case .week:
            [
                RecordBar(key: "一", title: "周一", multiplier: 1.00),
                RecordBar(key: "二", title: "周二", multiplier: 1.08),
                RecordBar(key: "三", title: "周三", multiplier: 0.93),
                RecordBar(key: "四", title: "今日", multiplier: 0.62, isToday: true),
                RecordBar(key: "五", title: "周五", multiplier: 0, isFuture: true),
                RecordBar(key: "六", title: "周六", multiplier: 0, isFuture: true),
                RecordBar(key: "日", title: "周日", multiplier: 0, isFuture: true)
            ]
        case .month:
            [
                RecordBar(key: "W1", title: "第 1 周", multiplier: 4.8),
                RecordBar(key: "W2", title: "第 2 周", multiplier: 5.0),
                RecordBar(key: "W3", title: "第 3 周", multiplier: 4.2),
                RecordBar(key: "W4", title: "本周", multiplier: 3.4, isToday: true),
                RecordBar(key: "W5", title: "第 5 周", multiplier: 0, isFuture: true)
            ]
        case .year:
            (1...12).map { month in
                RecordBar(key: "\(month)", title: month == 5 ? "本月" : "\(month) 月", multiplier: month <= 5 ? Double([22, 18, 23, 22, 21][month - 1]) : 0, isFuture: month > 5, isToday: month == 5)
            }
        }
    }

    private var total: Double {
        bars.reduce(0) { $0 + $1.multiplier * day.targetToday }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TopBar()
                    .padding(.top, 2)

                VStack(spacing: 14) {
                    heroCard

                    HStack(spacing: 10) {
                        MetricTile(label: period == .week ? "本周日均" : period == .month ? "月日均" : "年日均", value: WNFFormat.money(day.targetToday, privacy: state.privacyMode), subtitle: "每天的窝囊费", big: true)
                        MetricTile(label: "加班挣到", value: WNFFormat.money(day.targetToday * 1.7, privacy: state.privacyMode), subtitle: "丧但还顶得住", accent: WNFTheme.coral, big: true)
                    }

                    HStack(spacing: 10) {
                        MetricTile(label: "时薪", value: state.privacyMode ? "¥••/h" : "¥\(Int(day.hourlyRate))/h", subtitle: "基于税后月薪", accent: WNFTheme.cyan)
                        MetricTile(label: "已窝囊", value: "\(Int(Double(day.workdayMinutes) / 60 * 9.4))h", subtitle: "9.4 个工作日")
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
                Label(period == .year ? "+14%" : period == .month ? "+9.2%" : "+4.1%", systemImage: "arrow.up")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(WNFTheme.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(WNFTheme.ink, in: Capsule())
                Text(period == .year ? "比去年" : period == .month ? "比上月" : "比上周")
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
                Text("本月已窝囊 \(Int(Double(day.workdayMinutes) / 60 * 9.4)) 小时")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("相当于看完 \(Int(Double(day.workdayMinutes) / 60 * 9.4 / 2)) 集剧")
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
                Text(period == .year ? "1 月 - 12 月" : period == .month ? "第 1 - 第 5 周" : "周一 - 周日")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
            }

            BarChart(bars: bars, dailyAverage: day.targetToday, selectedBarID: $selectedBarID, privacy: state.privacyMode)
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
                Text("3 / 8 解锁")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
            }

            HStack(spacing: 10) {
                Badge(symbol: "sun.max", label: "早八勇士", unlocked: true)
                Badge(symbol: "fork.knife", label: "午休大师", unlocked: true)
                Badge(symbol: "clock", label: "加班 +1", unlocked: true)
                Badge(symbol: "yensign.circle", label: "忍 100h", unlocked: false)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }
}

private struct BarChart: View {
    var bars: [RecordBar]
    var dailyAverage: Double
    @Binding var selectedBarID: RecordBar.ID?
    var privacy: Bool

    private var maxMultiplier: Double {
        max(bars.map(\.multiplier).max() ?? 1, 1)
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
                        .accessibilityLabel("\(bar.title) \(WNFFormat.money(bar.multiplier * dailyAverage, privacy: privacy))")
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
                    Text("\(bar.title) \(WNFFormat.money(bar.multiplier * dailyAverage, privacy: privacy))")
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
                    .frame(width: bars.count > 8 ? 16 : 24, height: bar.isFuture ? 6 : max(8, 100 * bar.multiplier / maxMultiplier))
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
