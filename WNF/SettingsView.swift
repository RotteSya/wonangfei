import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var state: WageState
    @EnvironmentObject private var premium: PremiumEntitlementStore
    @EnvironmentObject private var premiumPreferences: PremiumPreferencesStore
    @EnvironmentObject private var paywallController: PremiumPaywallController

    var onShowOnboarding: () -> Void = {}

    @State private var exportActivityItems: [Any] = []
    @State private var isExportActivityPresented = false
    @State private var isExportWarningPresented = false
    @State private var exportError: String?
    @State private var legalDocument: LegalDocument?
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    private var day: WageDay { state.calculation }
    private var premiumPresentation: PremiumSettingsCardPresentation {
        PremiumSettingsCardPresentation(
            accessState: premium.accessState,
            displayPrice: premium.displayPrice,
            statusMessage: premium.statusMessage,
            refundRequestedAt: premium.refundRequestedAt,
            canMakePayments: premium.canMakePayments
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar()
                    .padding(.top, 2)

                VStack(spacing: 16) {
                    profileBanner
                    premiumCard

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
                        SettingsRow(title: "计入加班", isLast: true) {
                            WNFToggle(isOn: $state.includeOvertime)
                        }
                    }

                    clockOutReminderCard

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
            }
            .padding(.bottom, 105)
        }
        .background(WNFTheme.bg)
        .background {
            ActivityView(activityItems: exportActivityItems, isPresented: $isExportActivityPresented)
                .allowsHitTesting(false)
        }
        .alert("导出完整金额数据", isPresented: $isExportWarningPresented) {
            Button("取消", role: .cancel) {}
            Button("导出") {
                exportHistory()
            }
        } message: {
            Text("导出文件包含完整金额和工时数据，请确认分享对象和保存位置。")
        }
        .alert("导出失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .sheet(item: $legalDocument) { document in
            LegalDocumentView(document: document)
        }
        .onDisappear {
            premiumPreferences.clearPreview()
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
                        Text("下班结算提醒")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WNFTheme.ink)
                        Text("默认关闭。开启后每天 \(state.workEnd.clockText) 通知一次。")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WNFTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    WNFToggle(isOn: clockOutReminderBinding)
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
                Text("每周窝囊\(state.selectedWeekdays.count)天")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
            }
            .padding(14)
        }
    }

    private var premiumCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(WNFTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(WNFTheme.yellow, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Premium")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundStyle(WNFTheme.ink)
                    Text(premiumPresentation.subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WNFTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                PremiumStatusPill(
                    isUnlocked: premiumPresentation.isUnlocked,
                    isPending: premiumPresentation.isPending
                )
            }

            HStack(spacing: 8) {
                PremiumFeatureLockButton(
                    title: premiumPresentation.primaryActionTitle,
                    isUnlocked: premiumPresentation.primaryActionIsUnlocked
                ) {
                    if !premiumPresentation.isUnlocked {
                        paywallController.present(.settings)
                    }
                }
                PremiumFeatureLockButton(title: "Restore", isUnlocked: true) {
                    Task { await premium.restorePurchases() }
                }
                PremiumFeatureLockButton(title: "退款", isUnlocked: premiumPresentation.refundActionIsUnlocked) {
                    Task { await premium.requestRefund(in: UIApplication.shared.currentActiveWindowScene) }
                }
            }

            if let inlineMessage = premiumPresentation.inlineMessage {
                premiumInlineMessage(inlineMessage)
            }

            Divider().overlay(WNFTheme.hairline)

            premiumFeatureRows
            themePicker
            shareTemplatePicker
            widgetPrivacyRow
            exportRow
            legalRow
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(WNFTheme.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }

    private var premiumFeatureRows: some View {
        VStack(spacing: 8) {
            ForEach(premiumPresentation.featureRows()) { row in
                let feature = row.feature
                HStack(spacing: 10) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WNFTheme.ink)
                        .frame(width: 28, height: 28)
                        .background(WNFTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.system(size: 13, weight: .black))
                        Text(feature.subtitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WNFTheme.muted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if row.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WNFTheme.muted)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if row.isLocked {
                        paywallController.present(.feature(feature))
                    }
                }
            }
        }
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("主题皮肤")
                .font(.system(size: 13, weight: .black))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(premiumPresentation.themeOptions(activeTheme: premiumPreferences.activeTheme)) { option in
                    let theme = option.theme
                    Button {
                        let saved = premiumPreferences.selectTheme(theme, isPremiumUnlocked: premium.isPremiumUnlocked)
                        if !saved && theme.isPremium {
                            paywallController.present(.feature(.themeSkins))
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(theme.palette.yellow)
                                .frame(width: 14, height: 14)
                            Text(theme.title)
                                .font(.system(size: 12, weight: .black))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if option.isLocked {
                                Image(systemName: "lock.fill")
                            } else if option.isSelected {
                                Image(systemName: "checkmark")
                            }
                        }
                        .foregroundStyle(option.isSelected ? Color.white : WNFTheme.ink)
                        .padding(10)
                        .background(option.isSelected ? WNFTheme.ink : WNFTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityLabel)
                }
            }
        }
    }

    private var shareTemplatePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("默认分享模板")
                .font(.system(size: 13, weight: .black))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(premiumPresentation.shareTemplateOptions(selectedTemplate: premiumPreferences.selectedShareTemplate)) { option in
                        let template = option.template
                        Button {
                            let saved = premiumPreferences.selectShareTemplate(template, isPremiumUnlocked: premium.isPremiumUnlocked)
                            if !saved {
                                paywallController.present(.shareTemplate(template))
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if option.isLocked {
                                    Image(systemName: "lock.fill")
                                }
                                Text(option.title)
                            }
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(option.isSelected ? Color.white : WNFTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(option.isSelected ? WNFTheme.ink : WNFTheme.surfaceSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var widgetPrivacyRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("锁屏小组件显示金额")
                    .font(.system(size: 13, weight: .black))
                Text("关闭后，锁屏只显示状态和图标。")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WNFTheme.muted)
            }
            Spacer()
            WNFToggle(isOn: $premiumPreferences.lockScreenWidgetShowsAmount)
        }
        .padding(12)
        .background(WNFTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 15))
    }

    private var exportRow: some View {
        Button {
            if premiumPresentation.isUnlocked {
                isExportWarningPresented = true
            } else {
                paywallController.present(.historyExport)
            }
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("导出历史记录 CSV / JSON")
                Spacer()
                Image(systemName: premiumPresentation.exportTrailingSymbol)
            }
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(WNFTheme.ink)
            .padding(12)
            .background(WNFTheme.yellow.opacity(0.88), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    private var legalRow: some View {
        HStack {
            Button("Terms") {
                legalDocument = .terms
            }
            Spacer()
            Button("Privacy") {
                legalDocument = .privacy
            }
        }
        .font(.system(size: 12, weight: .black))
        .foregroundStyle(WNFTheme.ink)
        .padding(.horizontal, 4)
    }

    private func premiumInlineMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WNFTheme.inkSoft)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WNFTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 13))
    }

    private func exportHistory() {
        do {
            exportActivityItems = try HistoryExportService.makeExportItems(state: state)
            isExportActivityPresented = true
        } catch {
            exportError = String(describing: error)
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
        .environmentObject(PremiumEntitlementStore())
        .environmentObject(PremiumPreferencesStore())
        .environmentObject(PremiumPaywallController())
}
