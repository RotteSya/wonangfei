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
                    premiumSection
                    if let inlineMessage = premiumPresentation.inlineMessage {
                        premiumInlineMessage(inlineMessage)
                    }
                    appearanceSection

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

                    clockOutReminderCard

                    SectionCard(title: "其它") {
                        SettingsRow(title: "计入加班") {
                            WNFToggle(isOn: $state.includeOvertime)
                        }
                        exportHistoryRow
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

                    legalFooter
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

    private var premiumSection: some View {
        SectionCard(title: "王牌打工人") {
            VStack(spacing: 0) {
                premiumPrimaryRow
                if premiumPresentation.isUnlocked {
                    Rectangle()
                        .fill(WNFTheme.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                    premiumRefundRow
                }
            }
        }
    }

    private var premiumPrimaryRow: some View {
        Button {
            paywallController.present(.settings)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WNFTheme.ink)
                    .frame(width: 34, height: 34)
                    .background(WNFTheme.yellow, in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text(premiumRowTitle)
                        .font(.system(size: 14.5, weight: .heavy))
                        .foregroundStyle(WNFTheme.ink)
                    Text(premiumRowSubtitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(WNFTheme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                premiumRowPill
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(premiumRowTitle)
        .accessibilityHint(premiumRowSubtitle)
    }

    @ViewBuilder
    private var premiumRowPill: some View {
        if premiumPresentation.isUnlocked {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .black))
                Text("已买断")
            }
            .font(.system(size: 12, weight: .heavy, design: .monospaced))
            .foregroundStyle(WNFTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(WNFTheme.yellow, in: Capsule())
        } else if premiumPresentation.isPending {
            Text("等待批准")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(WNFTheme.coral, in: Capsule())
        } else {
            Text(premiumPriceLabel)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(WNFTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(WNFTheme.yellow, in: Capsule())
        }
    }

    private var premiumRefundRow: some View {
        Button {
            Task { await premium.requestRefund(in: UIApplication.shared.currentActiveWindowScene) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)
                    .frame(width: 34, height: 34)
                    .background(WNFTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("申请退款")
                        .font(.system(size: 14.5, weight: .heavy))
                        .foregroundStyle(WNFTheme.ink)
                    Text("走 Apple 官方退款流程")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(WNFTheme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(WNFTheme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("申请退款")
    }

    private var premiumRowTitle: String {
        if premiumPresentation.isUnlocked { return "王牌打工人 · 已买断" }
        if premiumPresentation.isPending { return "王牌打工人 · 等待批准" }
        return "当个王牌打工人"
    }

    private var premiumRowSubtitle: String {
        if premiumPresentation.isUnlocked { return "多谢支持 · 4 件小礼物归你了" }
        if premiumPresentation.isPending { return "等 Apple ID 一下 · 批准后自动解锁" }
        return "桌面 / 锁屏 Widget · 主题 · 分享模板 · 导出"
    }

    private var premiumPriceLabel: String {
        if !premium.canMakePayments { return "受限" }
        switch premium.productState {
        case .loading, .idle: return "加载中"
        case .unavailable: return "即将开放"
        case .failed: return "重试"
        case .loaded: return "\(premium.displayPrice) · 买断"
        }
    }

    private var appearanceSection: some View {
        SectionCard(title: "外观与小组件") {
            VStack(alignment: .leading, spacing: 14) {
                themePickerBlock
                Rectangle().fill(WNFTheme.hairline).frame(height: 0.5)
                shareTemplateBlock
                Rectangle().fill(WNFTheme.hairline).frame(height: 0.5)
                widgetPrivacyBlock
            }
            .padding(14)
        }
    }

    private var themePickerBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("主题皮肤")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WNFTheme.ink)
                if !premiumPresentation.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WNFTheme.muted)
                }
            }
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
                        .background(option.isSelected ? WNFTheme.ink : WNFTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityLabel)
                }
            }
        }
    }

    private var shareTemplateBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("默认分享模板")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WNFTheme.ink)
                if !premiumPresentation.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WNFTheme.muted)
                }
            }
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

    private var widgetPrivacyBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("锁屏小组件显示金额")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WNFTheme.ink)
                Text("关掉就只显示状态和图标，别让人偷瞄。")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WNFTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            WNFToggle(isOn: $premiumPreferences.lockScreenWidgetShowsAmount)
        }
    }

    private var exportHistoryRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WNFTheme.ink)
                .frame(width: 34, height: 34)
                .background(WNFTheme.yellow, in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text("导出历史记录 CSV / JSON")
                    .font(.system(size: 14.5, weight: .heavy))
                    .foregroundStyle(WNFTheme.ink)
                Text("含完整金额和工时 · 给会计或自己留一份")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WNFTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            exportActionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var exportActionButton: some View {
        Button {
            if premiumPresentation.isUnlocked {
                isExportWarningPresented = true
            } else {
                paywallController.present(.historyExport)
            }
        } label: {
            HStack(spacing: 6) {
                if premiumPresentation.isUnlocked {
                    Text("导出")
                    Image(systemName: "arrow.right")
                } else {
                    Image(systemName: "lock.fill")
                    Text("解锁")
                }
            }
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(WNFTheme.ink, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(premiumPresentation.isUnlocked ? "导出历史记录" : "解锁导出功能")
    }

    private var legalFooter: some View {
        HStack(spacing: 14) {
            Button("Terms of Use") { legalDocument = .terms }
            Text("·").foregroundStyle(WNFTheme.muted)
            Button("Privacy Policy") { legalDocument = .privacy }
        }
        .font(.system(size: 11, weight: .heavy))
        .foregroundStyle(WNFTheme.inkSoft)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func premiumInlineMessage(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WNFTheme.coral)
            Text(message)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(WNFTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WNFTheme.coralSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
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
