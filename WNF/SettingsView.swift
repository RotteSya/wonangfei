import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var state: WageState
    @StateObject private var aggregationStore = RecordAggregationStore()

    var onShowOnboarding: () -> Void = {}

    @State private var legalDocument: LegalDocument?
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    private var day: WageDay { state.calculation }
    private var currentMonthSummary: RecordSummary {
        aggregationStore.snapshot(for: RecordAggregationInput(state: state)).currentMonthSummary
    }
    private var workStartBinding: Binding<DateComponents> {
        Binding {
            state.workStart
        } set: { value in
            state.setWorkStart(value)
        }
    }

    private var workEndBinding: Binding<DateComponents> {
        Binding {
            state.workEnd
        } set: { value in
            state.setWorkEnd(value)
        }
    }

    var body: some View {
        // Fixed TopBar outside the ScrollView — same fix as RecordsView: a
        // scroll-embedded TopBar's buttons lost taps under the pager's
        // simultaneousGesture drag.
        VStack(spacing: 0) {
            TopBar()
                .padding(.top, 2)

            ScrollView {
                VStack(spacing: 14) {
                    profileBanner

                    SectionCard(title: "收入") {
                        SettingsRow(title: "月薪 · 税后") {
                            ValueStepper(
                                valueText: state.privacyMode ? "¥••,•••" : "¥\(Int(state.monthlySalary).formatted())",
                                editTitle: "设置月薪",
                                editUnit: "元 / 月",
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
                                editUnit: "天",
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
                                .font(WNFTheme.mono(13))
                                .foregroundStyle(WNFTheme.inkFixed)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(WNFTheme.yellow, in: Capsule())
                        }
                    }

                    weekdaysCard

                    SectionCard(title: "时间") {
                        TimePickerRow(title: "上班", components: workStartBinding)
                        TimePickerRow(title: "下班", components: workEndBinding)
                        SettingsRow(title: "午休") {
                            WNFToggle(isOn: $state.hasLunchBreak)
                        }
                        if state.hasLunchBreak {
                            TimePickerRow(title: "午休开始", components: $state.lunchStart)
                            TimePickerRow(title: "午休结束", components: $state.lunchEnd, isLast: true)
                        }
                    }

                    clockOutReminderCard

                    SectionCard(title: "其它") {
                        SettingsRow(title: "计入加班", isLast: true) {
                            WNFToggle(isOn: $state.includeOvertime)
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
                                .background(WNFTheme.inkSurface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    legalFooter
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 105)
            }
        }
        .background(WNFTheme.bg)
        .sheet(item: $legalDocument) { document in
            LegalDocumentView(document: document)
        }
        .task {
            await refreshNotificationAuthStatus()
        }
    }

    @MainActor
    private func refreshNotificationAuthStatus() async {
        notificationAuthStatus = await ClockOutReminderService.shared.currentAuthorizationStatus()
    }

    private var clockOutReminderBinding: Binding<Bool> {
        Binding(
            get: { state.clockOutReminderEnabled },
            set: { newValue in
                state.clockOutReminderEnabled = newValue
                if newValue {
                    Task { @MainActor in
                        _ = await ClockOutReminderService.shared.requestAuthorizationIfNeeded()
                        await refreshNotificationAuthStatus()
                        state.reconcileClockOutReminder()
                    }
                } else {
                    Task { @MainActor in
                        await refreshNotificationAuthStatus()
                    }
                }
            }
        )
    }

    private var clockOutReminderShouldShowSystemHint: Bool {
        state.clockOutReminderEnabled && notificationAuthStatus == .denied
    }

    private var clockOutReminderCard: some View {
        SectionCard(title: "提醒") {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("下班提醒")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WNFTheme.ink)
                        Text("默认关闭。开启后每天 \(state.workEnd.clockText) 提醒你下班。")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WNFTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    WNFToggle(isOn: clockOutReminderBinding)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Rectangle()
                    .fill(WNFTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.leading, 16)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("灵动岛实时窝囊费")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WNFTheme.ink)
                        Text("上班时把今日窝囊费和离下班倒计时挂在灵动岛和锁屏上。")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WNFTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    WNFToggle(isOn: $state.liveActivityEnabled)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if clockOutReminderShouldShowSystemHint {
                    Rectangle()
                        .fill(WNFTheme.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, 16)

                    Button {
                        openSystemNotificationSettings()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(WNFTheme.coral)
                            Text("iOS 通知权限被关闭，到系统设置开启后才会真的弹通知。")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(WNFTheme.inkSoft)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(WNFTheme.inkSoft)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开系统通知设置")
                }
            }
        }
    }

    private func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func dailyHoursText(paidMinutes: Int) -> String {
        let hours = Double(paidMinutes) / 60
        return hours.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(hours))"
            : String(format: "%.1f", hours)
    }

    private var profileBanner: some View {
        HStack(spacing: 15) {
            Image("HeroMascot")
                .resizable()
                .scaledToFill()
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(0.16), lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text("窝囊费打工人")
                    .font(WNFTheme.display(25))
                    .foregroundStyle(Color.white)
                HStack(spacing: 6) {
                    YenBadge(size: 13)
                    Text("时薪 \(state.privacyMode ? "¥••" : String(format: "¥%.2f", day.hourlyRate)) · 本月已忍 \(state.privacyMode ? "••h••min" : WNFFormat.duration(currentMonthSummary.elapsedPaidSeconds / 60))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WNFTheme.inkSurface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(alignment: .topTrailing) {
            Text("¥")
                .font(.system(size: 185, weight: .black, design: .rounded))
                .foregroundStyle(WNFTheme.yellow.opacity(0.12))
                .offset(x: 22, y: -50)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var weekdaysCard: some View {
        SectionCard(title: "工作日") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { index, label in
                        Button {
                            state.toggleWeekday(index)
                        } label: {
                            Text(label)
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(state.selectedWeekdays.contains(index) ? WNFTheme.yellow : WNFTheme.muted)
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .background(state.selectedWeekdays.contains(index) ? WNFTheme.inkSurface : WNFTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("周\(label)")
                        .accessibilityValue(state.selectedWeekdays.contains(index) ? "已选择" : "未选择")
                    }
                }
                Text("每周窝囊\(state.selectedWeekdays.count)天")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
            }
            .padding(13)
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button("Terms of Use") { legalDocument = .terms }
                    .accessibilityIdentifier("settings.legal.terms")
                Text("·").foregroundStyle(WNFTheme.muted)
                Button("Privacy Policy") { legalDocument = .privacy }
                    .accessibilityIdentifier("settings.legal.privacy")
            }
            Button("字体与开源许可") { legalDocument = .acknowledgements }
                .accessibilityIdentifier("settings.legal.acknowledgements")
        }
        .font(.system(size: 11, weight: .heavy))
        .foregroundStyle(WNFTheme.inkSoft)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
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
    var editUnit: String
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
                    .font(WNFTheme.mono(14))
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
        .frame(width: width, height: 40)
        .background(WNFTheme.surfaceSoft.opacity(0.75), in: Capsule())
        .overlay(Capsule().stroke(WNFTheme.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $isQuickEditorPresented) {
            WNFNumberPadSheet(
                title: editTitle,
                unit: editUnit,
                // Evaluated at presentation time — never a stale @State capture.
                initialText: editInitialText(),
                onCommit: onCommitText
            )
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

    @State private var isPickerPresented = false

    var body: some View {
        SettingsRow(title: title, isLast: isLast) {
            Button {
                isPickerPresented = true
            } label: {
                Text(components.clockText)
                    .font(WNFTheme.mono(14))
                    .foregroundStyle(WNFTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(WNFTheme.surfaceSoft.opacity(0.75), in: Capsule())
                    .overlay(Capsule().stroke(WNFTheme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.squish(0.95))
            .accessibilityLabel("\(title)时间")
            .accessibilityValue(components.clockText)
        }
        .sheet(isPresented: $isPickerPresented) {
            WNFTimePickerSheet(title: "设置\(title)时间", components: $components)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(WageState())
}
