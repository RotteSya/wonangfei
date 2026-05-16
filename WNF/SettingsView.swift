import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: WageState

    var onShowOnboarding: () -> Void = {}

    private var day: WageDay { state.calculation }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar()
                    .padding(.top, 2)

                profileBanner

                SectionCard(title: "收入") {
                    SettingsRow(title: "月薪 · 税后") {
                        ValueStepper(
                            valueText: state.privacyMode ? "¥••,•••" : "¥\(Int(state.monthlySalary).formatted())",
                            editTitle: "设置月薪",
                            editPlaceholder: "输入月薪",
                            editInitialText: { "\(Int(state.monthlySalary))" },
                            width: 172,
                            decrementAccessibilityLabel: "减少月薪",
                            incrementAccessibilityLabel: "增加月薪",
                            valueAccessibilityLabel: "快速设置月薪",
                            canDecrement: state.monthlySalary > 0,
                            canIncrement: state.monthlySalary < 100_000,
                            onCommitText: { text in state.setMonthlySalary(from: text) },
                            onDecrement: { state.adjustMonthlySalary(by: -500) },
                            onIncrement: { state.adjustMonthlySalary(by: 500) }
                        )
                    }
                    SettingsRow(title: "每月工作日") {
                        ValueStepper(
                            valueText: "\(state.workdaysPerMonth) 天",
                            editTitle: "设置每月工作日",
                            editPlaceholder: "输入工作日",
                            editInitialText: { "\(state.workdaysPerMonth)" },
                            width: 136,
                            decrementAccessibilityLabel: "减少每月工作日",
                            incrementAccessibilityLabel: "增加每月工作日",
                            valueAccessibilityLabel: "快速设置每月工作日",
                            canDecrement: state.workdaysPerMonth > 1,
                            canIncrement: state.workdaysPerMonth < 31,
                            onCommitText: { text in state.setWorkdaysPerMonth(from: text) },
                            onDecrement: { state.adjustWorkdaysPerMonth(by: -1) },
                            onIncrement: { state.adjustWorkdaysPerMonth(by: 1) }
                        )
                    }
                    SettingsRow(title: "时薪 · 自动算", isLast: true) {
                        Text(state.privacyMode ? "¥••.•/h" : String(format: "¥%.1f/h", day.hourlyRate))
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(WNFTheme.yellow, in: Capsule())
                    }
                }

                weekdaysCard

                SectionCard(title: "时间") {
                    TimePickerRow(title: "上班", components: $state.workStart)
                    TimePickerRow(title: "下班", components: $state.workEnd)
                    SettingsRow(title: "午休") {
                        WNFToggle(isOn: $state.hasLunchBreak)
                    }
                    if state.hasLunchBreak {
                        TimePickerRow(title: "午休开始", components: $state.lunchStart)
                        TimePickerRow(title: "午休结束", components: $state.lunchEnd, isLast: true)
                    }
                }

                SectionCard(title: "其它") {
                    SettingsRow(title: "计入加班") {
                        WNFToggle(isOn: $state.includeOvertime)
                    }
                    SettingsRow(title: "截图隐藏工资", isLast: true) {
                        WNFToggle(isOn: $state.privacyMode)
                    }
                }

                SectionCard(title: "引导") {
                    SettingsRow(title: "重新设置工资/时间", isLast: true) {
                        Button {
                            onShowOnboarding()
                        } label: {
                            HStack(spacing: 6) {
                                Text("再走一遍")
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(WNFTheme.ink, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                footer
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 105)
        }
        .background(WNFTheme.bg)
    }

    private var profileBanner: some View {
        HStack(spacing: 14) {
            Image("HeroMascot")
                .resizable()
                .scaledToFill()
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.16), lineWidth: 1))

            VStack(alignment: .leading, spacing: 5) {
                Text("窝囊费打工人")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                HStack(spacing: 6) {
                    YenBadge(size: 13)
                    Text("时薪 \(state.privacyMode ? "¥••" : "¥\(Int(day.hourlyRate))") · \(state.hasLunchBreak ? "已忍 \(Int(Double(day.workdayMinutes) / 60 * 9.4)) 小时" : "不午休")")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WNFTheme.ink, in: RoundedRectangle(cornerRadius: 28))
        .overlay(alignment: .topTrailing) {
            Text("¥")
                .font(.system(size: 210, weight: .black, design: .rounded))
                .foregroundStyle(WNFTheme.yellow.opacity(0.12))
                .offset(x: 20, y: -56)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var weekdaysCard: some View {
        SectionCard(title: "工作日") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { index, label in
                        Button {
                            state.toggleWeekday(index)
                        } label: {
                            Text(label)
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(state.selectedWeekdays.contains(index) ? WNFTheme.yellow : WNFTheme.muted)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(state.selectedWeekdays.contains(index) ? WNFTheme.ink : WNFTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("周\(label)")
                        .accessibilityValue(state.selectedWeekdays.contains(index) ? "已选择" : "未选择")
                    }
                }
                Text("已选 \(state.selectedWeekdays.count) 天 · 每周窝囊 \(state.selectedWeekdays.count) 次")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
            }
            .padding(14)
        }
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Text("算 了 算 了")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(WNFTheme.muted)
            Text("数据仅本地存储 · 我们不知道你赚多少\n也别让老板知道你装了这个 app")
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(WNFTheme.muted)
                .lineSpacing(4)
        }
        .padding(.top, 8)
    }
}

private struct ValueStepper: View {
    var valueText: String
    var editTitle: String
    var editPlaceholder: String
    var editInitialText: () -> String
    var width: CGFloat
    var decrementAccessibilityLabel: String
    var incrementAccessibilityLabel: String
    var valueAccessibilityLabel: String
    var canDecrement: Bool
    var canIncrement: Bool
    var onCommitText: (String) -> Void
    var onDecrement: () -> Void
    var onIncrement: () -> Void

    @State private var draftText = ""
    @State private var isQuickEditorPresented = false

    var body: some View {
        HStack(spacing: 0) {
            controlButton(
                systemName: "minus",
                accessibilityLabel: decrementAccessibilityLabel,
                isEnabled: canDecrement,
                action: onDecrement
            )

            Button {
                draftText = editInitialText()
                isQuickEditorPresented = true
            } label: {
                Text(valueText)
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundStyle(WNFTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(valueAccessibilityLabel)
            .accessibilityValue(valueText)

            controlButton(
                systemName: "plus",
                accessibilityLabel: incrementAccessibilityLabel,
                isEnabled: canIncrement,
                action: onIncrement
            )
        }
        .frame(width: width, height: 38)
        .background(Color.black.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .contain)
        .alert(editTitle, isPresented: $isQuickEditorPresented) {
            TextField(editPlaceholder, text: $draftText)
                .keyboardType(.numberPad)
            Button("取消", role: .cancel) {}
            Button("确定") {
                onCommitText(draftText)
            }
        } message: {
            Text("直接输入数字即可")
        }
    }

    private func controlButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                action()
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WNFTheme.ink)
                .frame(width: 42, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.32)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct TimePickerRow: View {
    var title: String
    @Binding var components: DateComponents
    var isLast = false

    private var date: Binding<Date> {
        Binding {
            DateComponents.calendar.date(from: components) ?? .now
        } set: { value in
            components = DateComponents.calendar.dateComponents([.hour, .minute], from: value)
        }
    }

    var body: some View {
        SettingsRow(title: title, isLast: isLast) {
            DatePicker("", selection: date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(WNFTheme.yellow)
                .environment(\.locale, Locale(identifier: "zh_Hans"))
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(WageState())
}
