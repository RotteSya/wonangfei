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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var state: WageState
    @StateObject private var homeMascotVideoController = HomeMascotVideoController()
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
    @AppStorage("wnf.onboarding.completed") private var onboardingCompleted = false

    private var day: WageDay { state.calculation }

    var body: some View {
        ZStack {
            if onboardingCompleted || entryAnimating {
                appShell
                    .scaleEffect(entryAnimating && !entryExpanded ? 0.88 : 1)
                    .opacity(entryAnimating && !entryExpanded ? 0.18 : 1)
                    .blur(radius: entryAnimating && !entryExpanded ? 12 : 0)
                    .allowsHitTesting(onboardingCompleted && !entryAnimating)
                    .animation(.spring(response: 0.82, dampingFraction: 0.82), value: entryExpanded)
            }

            if !onboardingCompleted {
                OnboardingView {
                    startHomeEntrance()
                }
                .scaleEffect(entryAnimating ? 1.08 : 1)
                .opacity(entryAnimating ? 0 : 1)
                .blur(radius: entryAnimating ? 16 : 0)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.46), value: entryAnimating)
            }

            if entryAnimating {
                HomeEntranceOverlay(expanded: entryExpanded)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
    }

    private func startHomeEntrance() {
        guard !entryAnimating else { return }
        selectedTab = .home
        entryAnimating = true
        entryExpanded = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.74)) {
                entryExpanded = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.68) {
            onboardingCompleted = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.28) {
            withAnimation(.easeOut(duration: 0.22)) {
                entryAnimating = false
            }
            entryExpanded = false
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
                .opacity(homeSharePresented ? 0 : 1)
                .allowsHitTesting(!homeSharePresented)
                .animation(.easeInOut(duration: 0.18), value: homeSharePresented)
                .zIndex(1)

            ShareCardBackdrop(isPresented: homeSharePresented, onDismiss: dismissShareCard)
                .zIndex(2)

            if homeSharePresented {
                ShareCardOverlay(
                    day: day,
                    copy: shareCardCopy,
                    hidesSensitiveInfo: $shareCardHidesSensitiveInfo,
                    isPreparingShare: isPreparingShareActivity,
                    onShare: presentSystemShare,
                    onDismiss: dismissShareCard
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .all)
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .sheet(isPresented: $isActivityPresented) {
            ActivityView(activityItems: activityItems)
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
            HomeView(isShareCardPresented: $homeSharePresented, onShare: presentShareCard)
                .environmentObject(homeMascotVideoController)
        case .records:
            RecordsView()
        case .settings:
            SettingsView {
                onboardingCompleted = false
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
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if selectedTab == .home && (onboardingCompleted || entryAnimating) {
                homeMascotVideoController.start()
            }
        case .inactive:
            homeMascotVideoController.pause()
        case .background:
            homeMascotVideoController.releaseQueue()
        @unknown default:
            homeMascotVideoController.pause()
        }
    }

    private func presentShareCard() {
        guard selectedTab == .home else { return }
        shareCardCopy = ShareCardCopy.random(excluding: shareCardCopy)
        shareCardHidesSensitiveInfo = state.privacyMode
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            homeSharePresented = true
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
            await Task.yield()
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
            hidesSensitiveInfo: hidesSensitiveInfo,
            showsControls: false,
            onTogglePrivacy: {},
            onShare: {},
            onDismiss: {}
        )
        .frame(width: 360)

        let renderer = ImageRenderer(content: exportCard)
        renderer.scale = UIScreen.main.scale
        renderer.proposedSize = ProposedViewSize(width: 360, height: nil)

        if let image = renderer.uiImage {
            activityItems = [image]
        } else {
            activityItems = [shareFallbackText(day: day, hidesSensitiveInfo: hidesSensitiveInfo)]
        }
        isPreparingShareActivity = false
        isActivityPresented = true
    }

    private func shareFallbackText(day: WageDay, hidesSensitiveInfo: Bool) -> String {
        "今天挣了 \(WNFFormat.moneyDecimal(day.earnedToday, privacy: hidesSensitiveInfo))，上班上了 \(shareDurationText(day: day, hidesSensitiveInfo: hidesSensitiveInfo))。"
    }

    private func shareDurationText(day: WageDay, hidesSensitiveInfo: Bool) -> String {
        hidesSensitiveInfo ? "••h••min" : WNFFormat.duration(day.elapsedPaidMinutes)
    }
}

private struct ShareCardBackdrop: View {
    var isPresented: Bool
    var onDismiss: () -> Void

    var body: some View {
        Color(red: 0.27, green: 0.25, blue: 0.21)
            .opacity(isPresented ? 0.46 : 0)
            .ignoresSafeArea(.container, edges: .all)
            .contentShape(Rectangle())
            .allowsHitTesting(isPresented)
            .onTapGesture(perform: onDismiss)
            .animation(.easeInOut(duration: 0.18), value: isPresented)
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
}
