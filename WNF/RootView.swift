import SwiftUI
import UIKit

/// Measures the total floor space the bottom tab bar reserves at the bottom of
/// the app shell (the capsule's own height + its `.padding(.bottom, ...)`).
/// HomeView reads it via `EnvironmentValues.tabBarFloorHeight` to plant the
/// mascot's feet on the tab bar without hardcoding device-specific offsets.
/// Scoped `private` because only the tab-bar reporter and the `RootView`
/// listener inside this file produce or consume the preference; the value is
/// fanned out to the rest of the app through the environment, not the key.
private struct TabBarFloorHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // `max` is order-independent so multiple reporters (or a future split
        // tab bar) can contribute without the result depending on traversal.
        value = max(value, nextValue())
    }
}

private struct TabBarFloorHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var tabBarFloorHeight: CGFloat {
        get { self[TabBarFloorHeightEnvironmentKey.self] }
        set { self[TabBarFloorHeightEnvironmentKey.self] = newValue }
    }
}

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var state: WageState
    @StateObject private var homeMascotVideoSession = HomeMascotVideoSessionCoordinator()
    @StateObject private var gestureArbiter = HorizontalGestureArbiter()
    @State private var selectedTab: AppTab = .home
    @State private var pagerDragOffset: CGFloat = 0
    @State private var pagerAxisLock: Axis?
    @State private var jellyStretch: CGFloat = 0
    @State private var pageWidth: CGFloat = 390
    /// True while a pager touch is down. `@GestureState` resets on BOTH end
    /// and cancellation, so watching it flip false catches the cancels where
    /// `onEnded` never runs (system gesture steal, incoming banner, app
    /// switcher) — otherwise the strip would stay frozen mid-drag.
    @GestureState private var pagerTouchActive = false
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
    @State private var tabBarFloorHeight: CGFloat = 0
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

    private var day: WageDay { state.liveDay }
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
        .environment(\.tabBarFloorHeight, tabBarFloorHeight)
        .onPreferenceChange(TabBarFloorHeightKey.self) { value in
            tabBarFloorHeight = value
        }
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
            // A gesture interrupted by app switching never delivers onEnded;
            // make sure the strip and the jelly land somewhere sane.
            if newPhase != .active {
                pagerAxisLock = nil
                gestureArbiter.release(.pager)
                withAnimation(.easeOut(duration: 0.2)) {
                    pagerDragOffset = 0
                    jellyStretch = 0
                }
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

    /// Continuous pager position in pages (0 = home … 2 = settings). Drives
    /// the tab bar pill and per-page depth treatment so everything tracks the
    /// finger 1:1 during a swipe.
    private var pagerProgress: CGFloat {
        CGFloat(selectedTab.order) - pagerDragOffset / max(pageWidth, 1)
    }

    private var pagerGesturesEnabled: Bool {
        onboardingCompleted && !entryAnimating && !homeSharePresented && !settlementPresented
    }

    private var appShell: some View {
        ZStack(alignment: .bottom) {
            WNFTheme.bg.ignoresSafeArea()

            tabPager

            AppTabBar(progress: pagerProgress, onSelect: selectTab)
                .padding(.bottom, 10)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: TabBarFloorHeightKey.self,
                                value: proxy.size.height
                            )
                    }
                )
                .opacity(homeSharePresented || settlementPresented ? 0 : 1)
                .allowsHitTesting(!homeSharePresented && !settlementPresented)
                .animation(.easeInOut(duration: 0.18), value: homeSharePresented)
                .animation(.easeInOut(duration: 0.18), value: settlementPresented)
                .zIndex(1)

            ShareCardBackdrop(isPresented: homeSharePresented, onDismiss: dismissShareCard)
                .zIndex(2)

            ShareCardOverlay(
                isPresented: homeSharePresented,
                day: day,
                copy: shareCardCopy,
                hidesSensitiveInfo: $shareCardHidesSensitiveInfo,
                isPreparingShare: isPreparingShareActivity,
                onShare: presentSystemShare,
                onDismiss: dismissShareCard
            )
            .zIndex(3)

            ShareActionPanel(
                isPresented: homeSharePresented,
                isPreparingShare: isPreparingShareActivity,
                onSaveAlbum: saveShareCardToAlbum,
                onCopy: copyShareCardImage,
                onMore: presentSystemShare,
                onCancel: dismissShareCard
            )
            .zIndex(4)

            if settlementPresented, let snapshot = settlementSnapshot {
                DailySettlementOverlay(
                    settlement: snapshot,
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

    // MARK: Interactive jelly pager
    //
    // All three pages stay mounted side by side; the shell slides them as one
    // strip. A horizontal drag anywhere steers it 1:1 (with directional lock
    // so vertical scrolling inside pages wins diagonal fights), the release
    // spring inherits the fling velocity, and the whole strip shears like
    // soft pudding while it moves — `jellyStretch` follows drag velocity and
    // wobbles back to zero through a low-damping spring on settle.
    private var tabPager: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            HStack(spacing: 0) {
                HomeView(
                    isShareCardPresented: $homeSharePresented,
                    isActive: abs(pagerProgress) < 0.999,
                    onShare: presentShareCard,
                    onClockOut: presentSettlement
                )
                .environmentObject(homeMascotVideoSession.controller)
                .environment(\.pagerJellyStretch, jellyStretch)
                .jellyStretch(jellyStretch)
                .frame(width: width, height: proxy.size.height)
                .modifier(PageDepthFX(rel: pagerProgress - 0))

                RecordsView()
                    .jellyStretch(jellyStretch)
                    .frame(width: width, height: proxy.size.height)
                    .modifier(PageDepthFX(rel: pagerProgress - 1))

                SettingsView {
                    onboardingCompleted = false
                    syncHomeMascotVideoSession()
                }
                .jellyStretch(jellyStretch)
                .frame(width: width, height: proxy.size.height)
                .modifier(PageDepthFX(rel: pagerProgress - 2))
            }
            .frame(width: width * 3, alignment: .leading)
            .offset(x: -CGFloat(selectedTab.order) * width + pagerDragOffset)
            .onAppear { pageWidth = width }
            .onChange(of: width) { _, newWidth in pageWidth = newWidth }
        }
        .clipped()
        .environmentObject(gestureArbiter)
        .simultaneousGesture(pagerDragGesture)
        .onChange(of: pagerTouchActive) { _, touchDown in
            // Touch lifted. If onEnded already ran it cleared the axis lock;
            // a still-set horizontal lock means the gesture was CANCELLED
            // mid-drag — settle the strip to the nearest page so nothing is
            // left hanging askew.
            guard !touchDown, pagerAxisLock == .horizontal else { return }
            pagerAxisLock = nil
            gestureArbiter.release(.pager)
            let nearestOrder = Int(pagerProgress.rounded())
            let target = AppTab.allCases.first { $0.order == min(max(nearestOrder, 0), 2) } ?? selectedTab
            commitPager(to: target, velocityX: 0)
        }
    }

    private var pagerDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($pagerTouchActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                guard pagerGesturesEnabled else { return }

                if pagerAxisLock == nil {
                    let t = value.translation
                    if abs(t.width) > abs(t.height) * 1.15 {
                        guard gestureArbiter.claim(.pager) else {
                            pagerAxisLock = .vertical
                            return
                        }
                        pagerAxisLock = .horizontal
                    } else {
                        pagerAxisLock = .vertical
                    }
                }
                guard pagerAxisLock == .horizontal else { return }

                pagerDragOffset = rubberBandedOffset(for: value.translation.width)

                if !reduceMotion {
                    let target = max(-JellyStretch.maxStretch, min(JellyStretch.maxStretch, value.velocity.width * 0.02))
                    withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.86)) {
                        jellyStretch = target
                    }
                }
            }
            .onEnded { value in
                defer {
                    pagerAxisLock = nil
                    gestureArbiter.release(.pager)
                }
                guard pagerAxisLock == .horizontal else { return }

                let width = max(pageWidth, 1)
                let order = CGFloat(selectedTab.order)
                let predictedProgress = order - value.predictedEndTranslation.width / width
                var targetOrder = Int(predictedProgress.rounded())

                // A confident flick always moves at least one page, even if
                // the predicted offset rounds back to where we started.
                if targetOrder == selectedTab.order, abs(value.velocity.width) > 260 {
                    targetOrder += value.velocity.width < 0 ? 1 : -1
                }

                let target = AppTab.allCases.first { $0.order == min(max(targetOrder, 0), 2) } ?? selectedTab
                commitPager(to: target, velocityX: value.velocity.width)
            }
    }

    /// Full strip travel inside [home…settings] is 1:1; beyond the ends the
    /// offset compresses like a scroll view hitting its bounds.
    private func rubberBandedOffset(for translation: CGFloat) -> CGFloat {
        let width = max(pageWidth, 1)
        let order = CGFloat(selectedTab.order)
        let minOffset = -(2 - order) * width   // dragging toward settings
        let maxOffset = order * width          // dragging toward home

        if translation > maxOffset {
            let over = translation - maxOffset
            return maxOffset + over / (1 + over / (width * 0.45)) * 0.5
        }
        if translation < minOffset {
            let over = minOffset - translation
            return minOffset - over / (1 + over / (width * 0.45)) * 0.5
        }
        return translation
    }

    private func commitPager(to tab: AppTab, velocityX: CGFloat) {
        let width = max(pageWidth, 1)
        let currentOffset = -CGFloat(selectedTab.order) * width + pagerDragOffset
        let targetOffset = -CGFloat(tab.order) * width
        let delta = targetOffset - currentOffset
        // interpolatingSpring's initialVelocity is normalized to the travel
        // distance, so the settle picks up exactly where the finger left off.
        let normalizedVelocity = abs(delta) > 1 ? velocityX / delta : 0

        let landed = tab != selectedTab
        withAnimation(
            reduceMotion
                ? .easeInOut(duration: 0.3)
                : .interpolatingSpring(stiffness: 270, damping: 30, initialVelocity: normalizedVelocity)
        ) {
            selectedTab = tab
            pagerDragOffset = 0
        }
        releaseJellyWobble()

        if landed {
            WNFHaptics.rigid(intensity: 0.65)
            homeMascotVideoSession.handleTabChange(to: tab, isHomeSessionVisible: isHomeMascotSessionVisible)
        }
    }

    /// Lets the current shear spring back through a deliberately under-damped
    /// curve — that residual oscillation IS the jelly wobble.
    private func releaseJellyWobble() {
        guard jellyStretch != 0 else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.34)) {
            jellyStretch = 0
        }
    }

    private func selectTab(_ tab: AppTab) {
        guard tab != selectedTab else { return }
        guard pagerGesturesEnabled else { return }

        // Tab-bar taps get the same physicality as swipes: kick the jelly in
        // the travel direction, then let it wobble out on arrival.
        if !reduceMotion {
            jellyStretch = tab.order > selectedTab.order ? -11 : 11
        }
        withAnimation(
            reduceMotion
                ? .easeInOut(duration: 0.3)
                : .interpolatingSpring(stiffness: 240, damping: 27)
        ) {
            selectedTab = tab
            pagerDragOffset = 0
        }
        releaseJellyWobble()

        WNFHaptics.rigid(intensity: 0.65)
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
        // The unfurl is choreographed inside ShareCardOverlay (driven by its own
        // `reveal` state); the backdrop, home blur, and tab bar each animate off
        // this flag through their own `.animation` modifiers.
        homeSharePresented = true
    }

    private func presentSettlement() {
        guard selectedTab == .home else { return }
        let now = Date()
        let day = state.liveDay(at: now)
        settlementSnapshot = DailySettlement.derive(
            from: day,
            dailyRecords: state.dailyRecords,
            monthlyRecordSummaries: state.monthlyRecordSummaries,
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

    private func dismissShareCard() {
        isPreparingShareActivity = false
        // ShareCardOverlay furls the card back into the island on this change.
        homeSharePresented = false
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

    // Render the current share card to an image for the custom panel's fast
    // actions (no UIActivityViewController spin-up).
    @MainActor
    private func renderedShareCardImage() -> UIImage? {
        let card = WonangfeiShareCard(
            day: day,
            copy: shareCardCopy,
            hidesSensitiveInfo: shareCardHidesSensitiveInfo,
            showsControls: false,
            onTogglePrivacy: {},
            onShare: {},
            onDismiss: {}
        )
        .frame(width: Self.shareExportWidth)
        return renderedShareImage(card, scale: shareRenderScale)
    }

    @MainActor
    private func saveShareCardToAlbum() {
        guard let image = renderedShareCardImage() else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismissShareCard()
    }

    @MainActor
    private func copyShareCardImage() {
        guard let image = renderedShareCardImage() else { return }
        UIPasteboard.general.image = image
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismissShareCard()
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
        return "今天挣了 \(amount)，已忍 \(duration)\(streakSuffix)。——窝囊费"
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
