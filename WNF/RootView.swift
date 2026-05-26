import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case records
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .records: "记录"
        case .settings: "我的"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .records: "chart.bar"
        case .settings: "person"
        }
    }

    var order: Int {
        switch self {
        case .home: 0
        case .records: 1
        case .settings: 2
        }
    }
}

struct RootView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var state: WageState
    @EnvironmentObject private var premium: PremiumEntitlementStore
    @EnvironmentObject private var premiumPreferences: PremiumPreferencesStore
    @EnvironmentObject private var paywallController: PremiumPaywallController
    @StateObject private var homeMascotVideoSession = HomeMascotVideoSessionCoordinator()
    @State private var selectedTab: AppTab = .home
    @State private var tabTransitionDirection = 1
    @State private var entryAnimating = false
    @State private var entryExpanded = false
    @State private var homeSharePresented = false
    @State private var shareCardCopy = ShareCardCopy.default
    @State private var shareCardHidesSensitiveInfo = false
    @State private var activityItems: [Any] = []
    @State private var isActivityPresented = false
    @State private var isPreparingShareActivity = false
    @State private var windowSceneScale: CGFloat?
    @State private var settlementPresented = false
    @State private var settlementSnapshot: DailySettlement?
    @State private var settlementHidesSensitiveInfo = false
    @AppStorage("wnf.onboarding.completed") private var onboardingCompleted = false

    private static let shareExportWidth: CGFloat = 360
    private static let shareLoadingRefreshDelayNanoseconds: UInt64 = 16_000_000

    private enum EntranceTiming {
        static let shellResponse: TimeInterval = 0.82
        static let shellDampingFraction: Double = 0.82
        static let onboardingExitDuration: TimeInterval = 0.46
        static let burstDelay: TimeInterval = 0.04
        static let burstResponse: TimeInterval = 0.9
        static let burstDampingFraction: Double = 0.74
        static let completionBufferAfterExit: TimeInterval = 0.22
        static let cleanupDuration: TimeInterval = 0.22
        static let holdAfterBurstResponse: TimeInterval = 0.34

        static let shellAnimation = Animation.spring(response: shellResponse, dampingFraction: shellDampingFraction)
        static let onboardingExitAnimation = Animation.easeInOut(duration: onboardingExitDuration)
        static let burstAnimation = Animation.spring(response: burstResponse, dampingFraction: burstDampingFraction)
        static let cleanupAnimation = Animation.easeOut(duration: cleanupDuration)

        private static let onboardingCommitOffset = onboardingExitDuration + completionBufferAfterExit
        private static let cleanupOffset = burstDelay + burstResponse + holdAfterBurstResponse
        static let onboardingCommitDelayAfterBurst = max(0, onboardingCommitOffset - burstDelay)
        static let cleanupDelayAfterCommit = max(0, cleanupOffset - onboardingCommitOffset)

        static func sleep(_ seconds: TimeInterval) async throws {
            let nanoseconds = UInt64((max(0, seconds) * 1_000_000_000).rounded())
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    private var day: WageDay { state.calculation }
    private var isHomeMascotSessionVisible: Bool { onboardingCompleted || entryAnimating }
    private var shareRenderScale: CGFloat {
        let scale = windowSceneScale ?? displayScale
        return scale > 0 ? scale : 1
    }

    var body: some View {
        ZStack {
            if onboardingCompleted || entryAnimating {
                appShell
                    .scaleEffect(entryAnimating && !entryExpanded ? 0.88 : 1)
                    .opacity(entryAnimating && !entryExpanded ? 0.18 : 1)
                    .blur(radius: entryAnimating && !entryExpanded ? 12 : 0)
                    .allowsHitTesting(onboardingCompleted && !entryAnimating)
                    .animation(EntranceTiming.shellAnimation, value: entryExpanded)
            }

            if !onboardingCompleted {
                OnboardingView {
                    startHomeEntrance()
                }
                .scaleEffect(entryAnimating ? 1.08 : 1)
                .opacity(entryAnimating ? 0 : 1)
                .blur(radius: entryAnimating ? 16 : 0)
                .transition(.opacity)
                .animation(EntranceTiming.onboardingExitAnimation, value: entryAnimating)
            }

            if entryAnimating {
                HomeEntranceOverlay(expanded: entryExpanded)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
        .background {
            WindowSceneScaleReader { scale in
                windowSceneScale = scale
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            syncHomeMascotVideoSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            homeMascotVideoSession.handleScenePhase(
                newPhase,
                selectedTab: selectedTab,
                isHomeSessionVisible: isHomeMascotSessionVisible
            )
        }
        .sheet(isPresented: $paywallController.isPresented) {
            PremiumPaywallView()
                .environmentObject(premium)
                .environmentObject(paywallController)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(item: $premium.activeNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("知道了"))
            )
        }
        .onOpenURL { url in
            if PremiumDeepLink.isPremiumRoute(url) {
                selectedTab = .settings
                paywallController.present(.deepLink)
            }
        }
    }

    private func startHomeEntrance() {
        guard !entryAnimating else { return }
        selectedTab = .home
        entryAnimating = true
        entryExpanded = false
        syncHomeMascotVideoSession()

        Task { @MainActor in
            do {
                try await EntranceTiming.sleep(EntranceTiming.burstDelay)
                withAnimation(EntranceTiming.burstAnimation) {
                    entryExpanded = true
                }

                try await EntranceTiming.sleep(EntranceTiming.onboardingCommitDelayAfterBurst)
                onboardingCompleted = true
                syncHomeMascotVideoSession()

                try await EntranceTiming.sleep(EntranceTiming.cleanupDelayAfterCommit)
                withAnimation(EntranceTiming.cleanupAnimation) {
                    entryAnimating = false
                }
                entryExpanded = false
            } catch {
                entryAnimating = false
                entryExpanded = false
            }
        }
    }

    private var appShell: some View {
        ZStack(alignment: .bottom) {
            WNFTheme.bg.ignoresSafeArea()

            currentTabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(selectedTab)
            .transition(tabContentTransition)
            .clipped()

            AppTabBar(selectedTab: tabSelection)
                .padding(.bottom, 10)
                .opacity(homeSharePresented || settlementPresented ? 0 : 1)
                .allowsHitTesting(!homeSharePresented && !settlementPresented)
                .animation(.easeInOut(duration: 0.18), value: homeSharePresented)
                .animation(.easeInOut(duration: 0.18), value: settlementPresented)
                .zIndex(1)

            ShareCardBackdrop(isPresented: homeSharePresented, onDismiss: dismissShareCard)
                .zIndex(2)

            if homeSharePresented {
                ShareCardOverlay(
                    day: day,
                    copy: shareCardCopy,
                    selectedTemplate: premiumPreferences.selectedShareTemplate,
                    canUsePremiumTemplates: premium.isPremiumUnlocked,
                    hidesSensitiveInfo: $shareCardHidesSensitiveInfo,
                    isPreparingShare: isPreparingShareActivity,
                    onSelectTemplate: selectShareTemplate,
                    onLockedTemplate: { template in
                        paywallController.present(.shareTemplate(template))
                    },
                    onShare: presentSystemShare,
                    onDismiss: dismissShareCard
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .all)
                .transition(.opacity)
                .zIndex(3)
            }

            if settlementPresented, let snapshot = settlementSnapshot {
                DailySettlementOverlay(
                    settlement: snapshot,
                    template: premiumPreferences.selectedShareTemplate,
                    hidesSensitiveInfo: $settlementHidesSensitiveInfo,
                    isPreparingShare: isPreparingShareActivity,
                    onShare: presentSettlementSystemShare,
                    onSaveAsAsset: saveSettlementAsAsset,
                    onDismiss: dismissSettlement
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .all)
                .transition(.opacity)
                .zIndex(4)
            }
        }
        .background {
            ActivityView(activityItems: activityItems, isPresented: $isActivityPresented)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { selectTab($0) }
        )
    }

    @ViewBuilder
    private var currentTabContent: some View {
        switch selectedTab {
        case .home:
            HomeView(
                isShareCardPresented: $homeSharePresented,
                onShare: presentShareCard,
                onClockOut: presentSettlement
            )
            .environmentObject(homeMascotVideoSession.controller)
        case .records:
            RecordsView()
        case .settings:
            SettingsView {
                onboardingCompleted = false
                syncHomeMascotVideoSession()
            }
        }
    }

    private var tabContentTransition: AnyTransition {
        let insertionEdge: Edge = tabTransitionDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = tabTransitionDirection >= 0 ? .leading : .trailing

        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private func selectTab(_ tab: AppTab) {
        guard tab != selectedTab else { return }
        tabTransitionDirection = tab.order > selectedTab.order ? 1 : -1

        withAnimation(.snappy(duration: 0.32, extraBounce: 0.02)) {
            selectedTab = tab
        }
        homeMascotVideoSession.handleTabChange(to: tab, isHomeSessionVisible: isHomeMascotSessionVisible)
    }

    private func syncHomeMascotVideoSession() {
        homeMascotVideoSession.handleTabChange(
            to: selectedTab,
            isHomeSessionVisible: isHomeMascotSessionVisible
        )
    }

    private func presentShareCard() {
        guard selectedTab == .home else { return }
        shareCardCopy = ShareCardCopy.random(excluding: shareCardCopy)
        shareCardHidesSensitiveInfo = state.privacyMode
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            homeSharePresented = true
        }
    }

    private func presentSettlement() {
        guard selectedTab == .home else { return }
        let now = Date()
        let day = state.calculation(at: now)
        settlementSnapshot = DailySettlement.derive(
            from: day,
            dailyRecords: state.dailyRecords,
            at: now
        )
        settlementHidesSensitiveInfo = state.privacyMode
        withAnimation(.easeInOut(duration: 0.22)) {
            settlementPresented = true
        }
    }

    private func dismissSettlement() {
        isPreparingShareActivity = false
        withAnimation(.easeOut(duration: 0.22)) {
            settlementPresented = false
        }
    }

    private func saveSettlementAsAsset() {
        state.persistCurrentDaySnapshot()
        state.markTodaySettled()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        dismissSettlement()
    }

    private func selectShareTemplate(_ template: PremiumShareTemplateID) {
        if !premiumPreferences.selectShareTemplate(template, isPremiumUnlocked: premium.isPremiumUnlocked) {
            paywallController.present(.shareTemplate(template))
        }
    }

    private func dismissShareCard() {
        isPreparingShareActivity = false
        withAnimation(.easeOut(duration: 0.2)) {
            homeSharePresented = false
        }
    }

    @MainActor
    private func presentSystemShare() {
        guard !isPreparingShareActivity else { return }

        isPreparingShareActivity = true
        let exportDay = day
        let exportCopy = shareCardCopy
        let exportHidesSensitiveInfo = shareCardHidesSensitiveInfo

        Task { @MainActor in
            // ImageRenderer is MainActor-bound; give the loading state one frame before rasterizing.
            try? await Task.sleep(nanoseconds: Self.shareLoadingRefreshDelayNanoseconds)
            guard homeSharePresented else {
                isPreparingShareActivity = false
                return
            }

            renderAndPresentSystemShare(
                day: exportDay,
                copy: exportCopy,
                hidesSensitiveInfo: exportHidesSensitiveInfo
            )
        }
    }

    @MainActor
    private func renderAndPresentSystemShare(day: WageDay, copy: ShareCardCopy, hidesSensitiveInfo: Bool) {
        let exportCard = WonangfeiShareCard(
            day: day,
            copy: copy,
            template: premiumPreferences.selectedShareTemplate,
            hidesSensitiveInfo: hidesSensitiveInfo,
            showsControls: false,
            onTogglePrivacy: {},
            onShare: {},
            onDismiss: {}
        )
        .frame(width: Self.shareExportWidth)

        if let image = renderedShareImage(exportCard, scale: shareRenderScale) {
            activityItems = [image]
        } else {
            activityItems = [shareFallbackText(day: day, hidesSensitiveInfo: hidesSensitiveInfo)]
        }
        isPreparingShareActivity = false
        isActivityPresented = true
    }

    @MainActor
    private func presentSettlementSystemShare() {
        guard !isPreparingShareActivity, let snapshot = settlementSnapshot else { return }

        isPreparingShareActivity = true
        let exportSnapshot = snapshot
        let exportHidesSensitiveInfo = settlementHidesSensitiveInfo

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.shareLoadingRefreshDelayNanoseconds)
            guard settlementPresented else {
                isPreparingShareActivity = false
                return
            }

            renderAndPresentSettlementShare(
                settlement: exportSnapshot,
                hidesSensitiveInfo: exportHidesSensitiveInfo
            )
        }
    }

    @MainActor
    private func renderAndPresentSettlementShare(settlement: DailySettlement, hidesSensitiveInfo: Bool) {
        let exportCard = DailySettlementShareCard(
            settlement: settlement,
            template: premiumPreferences.selectedShareTemplate,
            displayedAmount: settlement.earnedToday,
            hidesSensitiveInfo: hidesSensitiveInfo,
            showsControls: false
        )
        .frame(width: Self.shareExportWidth)

        if let image = renderedShareImage(exportCard, scale: shareRenderScale) {
            activityItems = [image]
        } else {
            activityItems = [settlementFallbackText(settlement: settlement, hidesSensitiveInfo: hidesSensitiveInfo)]
        }
        isPreparingShareActivity = false
        isActivityPresented = true
    }

    private func settlementFallbackText(settlement: DailySettlement, hidesSensitiveInfo: Bool) -> String {
        let amount = WNFFormat.moneyDecimal(settlement.earnedToday, privacy: hidesSensitiveInfo)
        let duration = hidesSensitiveInfo ? "••h••min" : WNFFormat.duration(settlement.elapsedPaidMinutes)
        let streakSuffix = settlement.streakDays > 1 ? "，连续 \(settlement.streakDays) 天到账" : ""
        return "今日下班结算：\(amount)，已忍 \(duration)\(streakSuffix)。——窝囊费"
    }

    // Main-thread bound: the loading pre-flight gives perceptual feedback, not actual concurrency.
    @MainActor
    private func renderedShareImage<Content: View>(_ content: Content, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: Self.shareExportWidth, height: nil)
        renderer.isOpaque = false

        var renderedImage: UIImage?
        renderer.render(rasterizationScale: scale) { size, draw in
            guard size.width > 0, size.height > 0 else { return }

            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false

            renderedImage = UIGraphicsImageRenderer(size: size, format: format).image { context in
                draw(context.cgContext)
            }
        }
        return renderedImage
    }

    private func shareFallbackText(day: WageDay, hidesSensitiveInfo: Bool) -> String {
        "今天挣了 \(WNFFormat.moneyDecimal(day.earnedToday, privacy: hidesSensitiveInfo))，上班上了 \(shareDurationText(day: day, hidesSensitiveInfo: hidesSensitiveInfo))。"
    }

    private func shareDurationText(day: WageDay, hidesSensitiveInfo: Bool) -> String {
        hidesSensitiveInfo ? "••h••min" : WNFFormat.duration(day.elapsedPaidMinutes)
    }
}

private struct WindowSceneScaleReader: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> SceneScaleProbeView {
        let view = SceneScaleProbeView()
        view.onScaleChange = onChange
        return view
    }

    func updateUIView(_ uiView: SceneScaleProbeView, context: Context) {
        uiView.onScaleChange = onChange
    }

    final class SceneScaleProbeView: UIView {
        var onScaleChange: ((CGFloat) -> Void)?
        private var lastReportedScale: CGFloat?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportWindowSceneScale()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportWindowSceneScale()
        }

        private func reportWindowSceneScale() {
            guard let scale = window?.windowScene?.screen.scale, scale > 0 else { return }
            guard lastReportedScale != scale else { return }

            lastReportedScale = scale
            onScaleChange?(scale)
        }
    }
}

struct AppTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 15, weight: .bold))
                        if selectedTab == tab {
                            Text(tab.title)
                                .font(.system(size: 13, weight: .heavy))
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? Color.white : WNFTheme.inkSoft)
                    .padding(.horizontal, selectedTab == tab ? 17 : 13)
                    .frame(height: 44)
                    .background {
                        if selectedTab == tab {
                            Capsule().fill(WNFTheme.ink)
                        }
                    }
                    .overlay {
                        if selectedTab == tab {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(WNFTheme.yellow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 17)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }
}

private struct HomeEntranceOverlay: View {
    var expanded: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(expanded ? 0.0 : 0.96),
                                WNFTheme.yellow.opacity(expanded ? 0.0 : 0.72),
                                WNFTheme.gold.opacity(0)
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: size * 0.62
                        )
                    )
                    .frame(width: expanded ? size * 2.6 : 42, height: expanded ? size * 2.6 : 42)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .opacity(expanded ? 0 : 1)

                ForEach(0..<18, id: \.self) { index in
                    EntranceCoin(index: index, expanded: expanded)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }

                Text("¥")
                    .font(.system(size: expanded ? 86 : 34, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.yellow)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                    .scaleEffect(expanded ? 1.25 : 0.4)
                    .opacity(expanded ? 0 : 1)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WNFTheme.bg.opacity(expanded ? 0 : 0.22))
        }
    }
}

private struct EntranceCoin: View {
    var index: Int
    var expanded: Bool

    private var angle: Double {
        Double(index) / 18 * .pi * 2
    }

    private var distance: CGFloat {
        expanded ? CGFloat(132 + (index % 5) * 28) : 0
    }

    private var fontSize: CGFloat {
        CGFloat(15 + (index % 4) * 3)
    }

    private var coinSize: CGFloat {
        CGFloat(28 + (index % 3) * 5)
    }

    private var xOffset: CGFloat {
        CGFloat(cos(angle)) * distance
    }

    private var yOffset: CGFloat {
        CGFloat(sin(angle)) * distance
    }

    private var confettiColor: Color {
        index % 2 == 0 ? WNFTheme.coral : Color(red: 0.49, green: 0.78, blue: 0.38)
    }

    private var isCoin: Bool {
        index % 3 != 0
    }

    var body: some View {
        content
        .offset(x: xOffset, y: yOffset)
        .scaleEffect(expanded ? 1 : 0.22)
        .rotationEffect(.degrees(expanded ? Double(index * 31 + 90) : 0))
        .opacity(expanded ? 0 : 1)
        .animation(.spring(response: 0.72, dampingFraction: 0.78).delay(Double(index % 5) * 0.018), value: expanded)
    }

    @ViewBuilder
    private var content: some View {
        if isCoin {
            Text("¥")
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: coinSize, height: coinSize)
                .background(WNFTheme.yellow, in: Circle())
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(confettiColor)
                .frame(width: 16, height: 11)
                .rotationEffect(.degrees(Double(index * 17)))
        }
    }
}

#Preview {
    RootView()
        .environmentObject(WageState())
        .environmentObject(PremiumEntitlementStore())
        .environmentObject(PremiumPreferencesStore())
        .environmentObject(PremiumPaywallController())
}
