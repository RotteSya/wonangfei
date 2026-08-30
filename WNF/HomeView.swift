import AVFoundation
import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var state: WageState
    @Binding private var isShareCardPresented: Bool
    private var isActive: Bool
    private var onShare: () -> Void
    private var onClockOut: () -> Void

    init(
        isShareCardPresented: Binding<Bool> = .constant(false),
        isActive: Bool = true,
        onShare: @escaping () -> Void = {},
        onClockOut: @escaping () -> Void = {}
    ) {
        self._isShareCardPresented = isShareCardPresented
        self.isActive = isActive
        self.onShare = onShare
        self.onClockOut = onClockOut
    }

    var body: some View {
        ZStack {
            WNFTheme.bg.ignoresSafeArea()

            HeroHomePage(
                initialStatus: state.liveDay.status,
                isActive: isActive,
                onShare: onShare,
                onClockOut: onClockOut
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .blur(radius: isShareCardPresented ? 18 : 0)
            .scaleEffect(isShareCardPresented ? 0.985 : 1)
            .allowsHitTesting(!isShareCardPresented)
            .animation(.easeInOut(duration: 0.2), value: isShareCardPresented)

        }
    }
}

private struct HeroHomePage: View {
    @EnvironmentObject private var state: WageState
    @Environment(\.tabBarFloorHeight) private var tabBarFloorHeight: CGFloat
    @Environment(\.pagerJellyStretch) private var jellyStretch: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var quoteEngine: BubbleQuoteEngine
    @State private var displayedStatus: WorkStatus
    @State private var fountainBursts: [CoinFountainBurst] = []
    var isActive: Bool
    var onShare: () -> Void
    var onClockOut: () -> Void

    init(initialStatus: WorkStatus, isActive: Bool, onShare: @escaping () -> Void, onClockOut: @escaping () -> Void) {
        self.isActive = isActive
        self.onShare = onShare
        self.onClockOut = onClockOut
        self._quoteEngine = StateObject(wrappedValue: BubbleQuoteEngine(initialStatus: initialStatus))
        self._displayedStatus = State(initialValue: initialStatus)
    }

    private var statusChipLabel: String {
        state.isTodaySettled
            ? "今日已下班 · 个人时间"
            : WorkStatusPresentation(status: displayedStatus).label
    }

    /// Height of the transparent margin baked into the bottom of the home
    /// mascot video asset (the cow art does not reach the frame's bottom edge).
    /// This is a property of the asset, not the device. Measured precisely by
    /// walking the alpha channel up from the bottom of a sampled 1080×1080
    /// frame: both `home-typing.mov` and `home-bored.mov` have a 77 px
    /// transparent bottom margin → 77 × (285 / 1080) ≈ 20pt when aspect-fit
    /// into the 285pt mascot stage. If the assets change, re-measure and update.
    private static let mascotAssetBottomInset: CGFloat = 20

    /// Padding that plants the cow's visible feet exactly on the tab bar's top
    /// edge, regardless of device. `tabBarFloorHeight` is measured at runtime
    /// through `TabBarFloorHeightKey`, so the math works on any iPhone where
    /// the tab bar geometry differs (older devices, accessibility text sizes,
    /// orientation changes, etc.). When the preference hasn't reported a value
    /// yet, fall back to zero padding so the mascot still appears.
    private var mascotBottomPadding: CGFloat {
        guard tabBarFloorHeight > 0 else { return 0 }
        return max(0, tabBarFloorHeight - Self.mascotAssetBottomInset)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                // The page itself takes the pager's jelly squash; the cow
                // additionally leans into the drag like it's standing on a
                // braking bus — readout stays upright, mascot reacts.
                VStack(alignment: .leading, spacing: 0) {
                    TopBar(onShare: onShare)
                        .padding(.top, 2)

                    // Only the wage readout actually has to refresh per second —
                    // money ticks up, "已忍" / "离下班" advance, and the progress
                    // bar fills. TopBar, ClockOutCTA, and the mascot live outside
                    // so they don't get diffed every tick. The CTA's visibility
                    // still flips at the workEnd boundary because `displayedStatus`
                    // is updated via `.onChange(of: day.status)` below, which
                    // triggers an outer body rebuild. While the page is parked
                    // off-screen in the pager, the per-second clock pauses and a
                    // static snapshot stands in.
                    Group {
                        if isActive {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                readout(at: context.date, contentWidth: proxy.size.width - 44)
                            }
                        } else {
                            readout(at: Date(), contentWidth: proxy.size.width - 44)
                        }
                    }
                    .padding(.horizontal, 22)

                    if state.isTodaySettled || displayedStatus == .done {
                        ClockOutCTA(
                            status: displayedStatus,
                            isSettled: state.isTodaySettled,
                            action: onClockOut
                        )
                        .padding(.top, 4)
                        .padding(.horizontal, 22)
                    }
                }

                Spacer(minLength: 16)

                HomeMascotStage(quote: quoteEngine.currentQuote, bubbleOffset: quoteEngine.bubbleOffset)
                    .rotationEffect(.degrees(jellyStretch * -0.4), anchor: .bottom)
                    .offset(x: jellyStretch * -0.55)
                    .padding(.bottom, mascotBottomPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            // Coins live BEHIND the page content (backgroundPreferenceValue, not
            // overlay): a falling coin must never cover the progress labels or
            // the mascot bubble text.
            .backgroundPreferenceValue(CoinSourceAnchorKey.self) { anchor in
                if let anchor, isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let day = state.liveDay(at: context.date)
                        HomeCoinDropLayer(
                            day: day,
                            isSettled: state.isTodaySettled,
                            sourceFrame: proxy[anchor],
                            pageSize: proxy.size,
                            collisionY: coinCollisionY(in: proxy.size)
                        )
                    }
                }
            }
            .overlayPreferenceValue(MoneyBlockAnchorKey.self) { anchor in
                if let anchor, !fountainBursts.isEmpty {
                    CoinFountainLayer(
                        bursts: fountainBursts,
                        origin: CGPoint(x: proxy[anchor].midX, y: proxy[anchor].midY),
                        pageSize: proxy.size
                    ) { finished in
                        fountainBursts.removeAll { $0.id == finished }
                    }
                }
            }
        }
        .onChange(of: isActive) { _, nowActive in
            guard nowActive else { return }
            // The page may have missed a status flip while parked off-screen.
            let current = state.liveDay(at: Date()).status
            if current != displayedStatus {
                displayedStatus = current
                quoteEngine.setStatus(current)
            }
        }
    }

    private func readout(at date: Date, contentWidth: CGFloat) -> some View {
        let day = state.liveDay(at: date)
        return LiveWageReadout(
            day: day,
            statusChipLabel: statusChipLabel,
            privacyMode: state.privacyMode,
            workStartText: state.workStart.clockText,
            workEndText: state.workEnd.clockText,
            isActive: isActive,
            contentWidth: contentWidth,
            onMoneyLongPress: launchFountain
        )
        .onChange(of: day.status) { _, newStatus in
            displayedStatus = newStatus
            quoteEngine.setStatus(newStatus)
        }
    }

    /// Easter egg: long-pressing the big number "shakes the tree" — a burst of
    /// coins erupts from the readout and rains off the page. Purely cosmetic,
    /// deliberately a little absurd.
    private func launchFountain() {
        guard !reduceMotion else { return }
        fountainBursts.append(CoinFountainBurst())
        if fountainBursts.count > 2 {
            fountainBursts.removeFirst(fountainBursts.count - 2)
        }
        WNFHaptics.medium(intensity: 1.0)
    }

    private func coinCollisionY(in size: CGSize) -> CGFloat {
        guard tabBarFloorHeight > 0 else {
            return size.height - 72
        }
        return max(0, size.height - tabBarFloorHeight)
    }
}

private struct LiveWageReadout: View {
    var day: WageDay
    var statusChipLabel: String
    var privacyMode: Bool
    var workStartText: String
    var workEndText: String
    var isActive: Bool
    var contentWidth: CGFloat
    var onMoneyLongPress: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var charging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            StatusChip(label: statusChipLabel)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(WNFTheme.yellow)
                        .frame(width: 10, height: 10)
                        .background(Circle().fill(WNFTheme.yellow.opacity(0.18)).frame(width: 20, height: 20))
                    Text("今日窝囊费")
                        .font(WNFTheme.display(18))
                        .foregroundStyle(WNFTheme.ink)
                }

                OdometerMoneyText(value: day.earnedToday, privacy: privacyMode, isActive: isActive, maxWidth: contentWidth)
                    // Charge-up squish: pressing compresses the number like a
                    // spring being loaded; release (the long-press firing)
                    // lets it pop back while the fountain erupts.
                    .scaleEffect(
                        x: charging ? 1.025 : 1,
                        y: charging ? 0.93 : 1,
                        anchor: .bottomLeading
                    )
                    .anchorPreference(key: MoneyBlockAnchorKey.self, value: .bounds) { $0 }
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.42, maximumDistance: 30) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) {
                            charging = false
                        }
                        onMoneyLongPress()
                    } onPressingChanged: { pressing in
                        if reduceMotion { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            charging = pressing
                        }
                        if pressing {
                            WNFHaptics.soft(intensity: 0.45)
                        }
                    }
            }

            HStack(spacing: 18) {
                Text("已忍 \(WNFFormat.duration(day.elapsedPaidMinutes))")
                Circle().fill(WNFTheme.muted).frame(width: 4, height: 4)
                Text("离下班 \(WNFFormat.duration(day.wallToEndMinutes))")
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(WNFTheme.inkSoft)

            ProgressTrack(day: day, startText: workStartText, endText: workEndText, isActive: isActive)
        }
    }
}

private struct MoneyBlockAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct CoinSourceAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct HomeMascotStage: View {
    var quote: String
    var bubbleOffset: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    private let stageHeight: CGFloat = 285

    var body: some View {
        HomeMascotVideoSequence()
            .frame(width: stageHeight, height: stageHeight)
            .background {
                RadialGradient(
                    colors: [WNFTheme.cyan.opacity(0.16), WNFTheme.cyan.opacity(0)],
                    center: .center,
                    startRadius: 20,
                    endRadius: 155
                )
                .frame(width: stageHeight + 70, height: stageHeight + 70)
                .blur(radius: 8)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                ThoughtBubble(quote: quote)
                    .offset(x: bubbleOffset.width, y: bubbleOffset.height + (floating ? -3 : 3))
                    .id(quote)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.65, anchor: .bottomLeading).combined(with: .opacity)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: stageHeight)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    floating = true
                }
            }
    }
}

/// The cow's inner monologue: a comic thought bubble with trailing dots
/// descending toward its head, gently bobbing while it idles.
private struct ThoughtBubble: View {
    var quote: String

    var body: some View {
        Text(quote)
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(WNFTheme.ink)
            .lineSpacing(3)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(WNFTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .bottomLeading) {
                // Trailing thought dots, outside the bubble's own bounds.
                Circle()
                    .fill(WNFTheme.surface)
                    .frame(width: 8, height: 8)
                    .offset(x: 9, y: 13)
                Circle()
                    .fill(WNFTheme.surface)
                    .frame(width: 5, height: 5)
                    .offset(x: 3, y: 22)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

private struct HomeMascotVideoSequence: View {
    @EnvironmentObject private var controller: HomeMascotVideoController

    var body: some View {
        HomeMascotPlayerView(player: controller.player)
            .accessibilityHidden(true)
    }
}

private struct HomeMascotPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class HomeMascotVideoController: ObservableObject {
    let player = AVQueuePlayer()
    private let clips: [HomeMascotVideoClip]
    private var pendingClips: [HomeMascotVideoClip] = []
    private var lastPlayedClip: HomeMascotVideoClip?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    nonisolated(unsafe) private var memoryWarningObserver: NSObjectProtocol?
    private var isPlaybackRequested = false
    private let minimumQueuedItemCount = 3

    init() {
        self.clips = HomeMascotVideoClip.all
        configurePlayer()
        installEndObserver()
        installMemoryWarningObserver()
    }

    private func configurePlayer() {
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = .advance
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func start() {
        if isPlaybackRequested, !player.items().isEmpty {
            player.play()
            return
        }

        isPlaybackRequested = true
        fillQueue()
        player.play()
    }

    func pauseTemporarily() {
        player.pause()
    }

    func pauseAndRelease() {
        isPlaybackRequested = false
        player.pause()
        player.removeAllItems()
        pendingClips.removeAll(keepingCapacity: true)
    }

    private func fillQueue() {
        guard !clips.isEmpty else { return }

        while player.items().count < minimumQueuedItemCount {
            guard let item = makeNextItem() else { return }
            player.insert(item, after: nil)
        }
    }

    private func makeNextItem() -> AVPlayerItem? {
        guard !clips.isEmpty else { return nil }

        for _ in clips.indices {
            guard let clip = nextClip(),
                  let url = Bundle.main.url(forResource: clip.resourceName, withExtension: "mov")
            else {
                continue
            }

            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 1
            return item
        }

        return nil
    }

    private func nextClip() -> HomeMascotVideoClip? {
        if pendingClips.isEmpty {
            pendingClips = clips.shuffled()
            if clips.count > 1,
               pendingClips.first == lastPlayedClip,
               let nextIndex = pendingClips.dropFirst().firstIndex(where: { $0 != lastPlayedClip }) {
                pendingClips.swapAt(0, nextIndex)
            }
        }

        guard !pendingClips.isEmpty else { return nil }
        let clip = pendingClips.removeFirst()
        lastPlayedClip = clip
        return clip
    }

    private func installEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.isPlaybackRequested == true else { return }
                self?.fillQueue()
            }
        }
    }

    private func installMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pauseAndRelease()
            }
        }
    }
}

private struct HomeMascotVideoClip: Equatable {
    var resourceName: String

    static let all = [
        HomeMascotVideoClip(resourceName: "home-typing")
    ]
}

// MARK: - Long-press coin fountain

struct CoinFountainBurst: Identifiable, Equatable {
    let id = UUID()
    var coins: [FountainCoin] = (0..<14).map { FountainCoin(seed: $0) }

    static func == (lhs: CoinFountainBurst, rhs: CoinFountainBurst) -> Bool {
        lhs.id == rhs.id
    }
}

struct FountainCoin: Identifiable {
    let id = UUID()
    var size: CGFloat
    var launchX: CGFloat
    var driftX: CGFloat
    var peakY: CGFloat
    var fallY: CGFloat
    var upDuration: Double
    var downDuration: Double
    var spin: Double
    var delay: Double

    init(seed: Int) {
        size = CGFloat(20 + (seed % 4) * 4)
        launchX = CGFloat.random(in: -56...110)
        driftX = CGFloat.random(in: -90...110)
        peakY = -CGFloat.random(in: 110...230)
        fallY = CGFloat.random(in: 380...520)
        upDuration = Double.random(in: 0.3...0.44)
        downDuration = Double.random(in: 0.52...0.72)
        spin = Double.random(in: -540...540)
        delay = Double(seed % 7) * 0.022
    }
}

private struct CoinFountainLayer: View {
    var bursts: [CoinFountainBurst]
    var origin: CGPoint
    var pageSize: CGSize
    var onBurstFinished: (UUID) -> Void

    var body: some View {
        ZStack {
            ForEach(bursts) { burst in
                ForEach(burst.coins) { coin in
                    FountainCoinView(coin: coin, origin: origin)
                }
                .task(id: burst.id) {
                    let longest = burst.coins.map { $0.delay + $0.upDuration + $0.downDuration }.max() ?? 1.2
                    try? await Task.sleep(nanoseconds: UInt64((longest + 0.25) * 1_000_000_000))
                    onBurstFinished(burst.id)
                }
            }
        }
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FountainCoinPose {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotation: Double = 0
    var scale: CGFloat = 0.3
    var opacity: Double = 0
}

private struct FountainCoinView: View {
    var coin: FountainCoin
    var origin: CGPoint

    @State private var launched = false

    var body: some View {
        YenCoin(size: coin.size)
            .keyframeAnimator(initialValue: FountainCoinPose(), trigger: launched) { view, pose in
                view
                    .scaleEffect(pose.scale)
                    .rotationEffect(.degrees(pose.rotation))
                    .opacity(pose.opacity)
                    .position(x: origin.x + coin.launchX + pose.x, y: origin.y + pose.y)
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    MoveKeyframe(0)
                    CubicKeyframe(0, duration: coin.delay)
                    // Up fast with an ease-out, hang, then accelerate down.
                    CubicKeyframe(coin.peakY, duration: coin.upDuration, startVelocity: coin.peakY / (coin.upDuration * 0.42))
                    CubicKeyframe(coin.fallY, duration: coin.downDuration, endVelocity: coin.fallY / (coin.downDuration * 0.38))
                }
                KeyframeTrack(\.x) {
                    MoveKeyframe(0)
                    CubicKeyframe(0, duration: coin.delay)
                    CubicKeyframe(coin.driftX * 0.55, duration: coin.upDuration)
                    CubicKeyframe(coin.driftX, duration: coin.downDuration)
                }
                KeyframeTrack(\.rotation) {
                    MoveKeyframe(0)
                    CubicKeyframe(0, duration: coin.delay)
                    LinearKeyframe(coin.spin, duration: coin.upDuration + coin.downDuration)
                }
                KeyframeTrack(\.scale) {
                    MoveKeyframe(0.3)
                    CubicKeyframe(0.3, duration: coin.delay)
                    SpringKeyframe(1.06, duration: coin.upDuration, spring: .bouncy)
                    CubicKeyframe(0.92, duration: coin.downDuration)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    CubicKeyframe(0, duration: coin.delay)
                    LinearKeyframe(1, duration: 0.08)
                    LinearKeyframe(1, duration: coin.upDuration + coin.downDuration * 0.62 - 0.08)
                    LinearKeyframe(0, duration: coin.downDuration * 0.38)
                }
            }
            .onAppear { launched = true }
    }
}

private struct ProgressTrack: View {
    var day: WageDay
    var startText: String
    var endText: String
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The molten fill only needs frames while it is visible, moving, and
    /// non-empty; otherwise the shader freezes on its last frame for free.
    private var animatesFill: Bool {
        isActive && !reduceMotion && day.progress > 0.0005
    }

    var body: some View {
        VStack(spacing: 9) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(WNFTheme.track)

                    // Molten-gold fill: a full-width rect whose visible body is
                    // carved out by the shader — the leading edge is a lapping
                    // wave with a bright meniscus, and highlight bands drift
                    // toward the crest so the bar reads as slowly flowing metal
                    // rather than a static gradient.
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animatesFill)) { context in
                        let t = animatesFill
                            ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                            : 0
                        Rectangle()
                            .fill(Color.white)
                            .visualEffect { [progress = day.progress, reduceMotion] view, geometry in
                                view.colorEffect(
                                    ShaderLibrary.wnfMoltenGold(
                                        .float2(geometry.size),
                                        .float(t),
                                        .float(progress),
                                        .float(reduceMotion ? 0 : 5)
                                    )
                                )
                            }
                    }
                    .clipShape(Capsule())

                }
            }
            .frame(height: 10)
            .anchorPreference(key: CoinSourceAnchorKey.self, value: .bounds) { $0 }

            HStack {
                Text(startText)
                Spacer()
                Text("\(Int(day.progress * 100))%")
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: Int(day.progress * 100))
                Spacer()
                Text(endText)
            }
            .font(WNFTheme.mono(11))
            .foregroundStyle(WNFTheme.muted)
        }
    }
}

private struct HomeCoinDropLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var day: WageDay
    var isSettled: Bool
    var sourceFrame: CGRect
    var pageSize: CGSize
    var collisionY: CGFloat

    @State private var coins: [HomeFallingCoin] = []
    @State private var lastPaidSecond: Int?
    @State private var emissionIndex = 0

    private static let coinsPerBurst = 6
    private static let maxCatchUpBursts = 1
    private static let pruneIntervalNanoseconds: UInt64 = 500_000_000

    private var signal: HomeCoinSignal {
        HomeCoinSignal(
            paidSecond: day.elapsedPaidSeconds,
            canEmit: canEmitCoins,
            shouldClear: isSettled
        )
    }

    private var canEmitCoins: Bool {
        guard !isSettled else { return false }
        switch day.status {
        case .morning, .afternoon:
            return true
        case .off, .before, .lunch, .done:
            return false
        }
    }

    private var filledSourceFrame: CGRect {
        var f = sourceFrame
        f.size.width = max(0, sourceFrame.width * CGFloat(day.progress))
        return f
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(coins) { coin in
                HomeDroppingCoin(
                    coin: coin,
                    sourceFrame: filledSourceFrame,
                    collisionY: collisionY,
                    pageWidth: pageSize.width,
                    reduceMotion: reduceMotion
                )
            }
        }
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: primeBaseline)
        .onChange(of: signal) { _, newSignal in
            reconcile(newSignal)
        }
        .task {
            // Single shared pruning loop. The previous implementation spawned
            // one `Task { sleep then mutate state }` per coin — six per burst,
            // every paid second — which left orphan Tasks writing into a
            // deallocated view's `@State` when navigating away. One loop tied
            // to `.task`'s lifecycle auto-cancels on disappear and uses each
            // coin's own `spawnedAt` + `lifetime` to expire it.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pruneIntervalNanoseconds)
                if Task.isCancelled { return }
                let now = Date()
                coins.removeAll { now.timeIntervalSince($0.spawnedAt) >= $0.lifetime }
            }
        }
    }

    private func primeBaseline() {
        guard lastPaidSecond == nil else { return }
        lastPaidSecond = signal.paidSecond
        if signal.shouldClear {
            coins.removeAll()
        }
    }

    private func reconcile(_ signal: HomeCoinSignal) {
        if signal.shouldClear {
            coins.removeAll()
            lastPaidSecond = signal.paidSecond
            return
        }

        guard signal.canEmit else {
            lastPaidSecond = signal.paidSecond
            return
        }

        guard let previousPaidSecond = lastPaidSecond else {
            lastPaidSecond = signal.paidSecond
            return
        }

        guard signal.paidSecond > previousPaidSecond else {
            lastPaidSecond = signal.paidSecond
            return
        }

        let burstCount = min(signal.paidSecond - previousPaidSecond, Self.maxCatchUpBursts)
        lastPaidSecond = signal.paidSecond
        emitCoins(count: burstCount * Self.coinsPerBurst)
    }

    private func emitCoins(count: Int) {
        guard count > 0, sourceFrame.width > 0, pageSize.height > 0 else { return }

        let now = Date()
        for burstIndex in 0..<count {
            let coin = HomeFallingCoin(sequence: emissionIndex, burstIndex: burstIndex, spawnedAt: now)
            emissionIndex += 1
            coins.append(coin)
        }
    }
}

private struct HomeCoinSignal: Equatable {
    var paidSecond: Int
    var canEmit: Bool
    var shouldClear: Bool
}

private struct HomeFallingCoin: Identifiable, Equatable {
    let id = UUID()
    var sequence: Int
    var lane: Int
    var size: CGFloat
    var delay: Double
    var drift: CGFloat
    var rotation: Double
    var bounceHeight: CGFloat
    var spawnedAt: Date

    init(sequence: Int, burstIndex: Int, spawnedAt: Date) {
        self.sequence = sequence
        lane = sequence % 5
        size = CGFloat(21 + (sequence % 5) * 3)
        delay = Double(burstIndex) * 0.035

        let driftDirection: CGFloat = sequence.isMultiple(of: 2) ? -1 : 1
        drift = driftDirection * CGFloat(24 + (sequence % 4) * 12)

        let rotationDirection = sequence.isMultiple(of: 2) ? -1.0 : 1.0
        rotation = rotationDirection * Double(210 + (sequence % 6) * 32)
        bounceHeight = CGFloat(26 + (sequence % 4) * 9)
        self.spawnedAt = spawnedAt
    }

    /// Total time the coin should live in the view tree. Matches the upper
    /// bound of the multi-stage spring animation (~1.0s) plus a small buffer
    /// so the final `opacity: 0` phase has time to complete before removal.
    var lifetime: TimeInterval { 1.45 + delay }
}

private struct HomeDroppingCoin: View {
    var coin: HomeFallingCoin
    var sourceFrame: CGRect
    var collisionY: CGFloat
    var pageWidth: CGFloat
    var reduceMotion: Bool

    @State private var phase = CoinDropPhase.waiting

    private static let laneFractions: [CGFloat] = [0.30, 0.42, 0.55, 0.68, 0.78]

    var body: some View {
        YenCoin(size: coin.size)
            .scaleEffect(x: scale.width, y: scale.height, anchor: .bottom)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .position(position)
            .onAppear(perform: startAnimation)
    }

    private var position: CGPoint {
        if reduceMotion {
            return reducedMotionPosition
        }

        switch phase {
        case .waiting:
            return CGPoint(x: startX, y: spawnY)
        case .emerged:
            return CGPoint(x: startX + coin.drift * 0.08, y: emergeY)
        case .falling:
            return CGPoint(x: startX + coin.drift, y: impactCenterY)
        case .bounced:
            return CGPoint(x: startX + coin.drift * 1.08, y: bouncedY)
        case .finished:
            return CGPoint(x: startX + coin.drift * 1.16, y: impactCenterY + 3)
        }
    }

    private var reducedMotionPosition: CGPoint {
        switch phase {
        case .waiting:
            return CGPoint(x: startX, y: spawnY)
        case .emerged, .falling, .bounced:
            return CGPoint(x: startX, y: emergeY - 8)
        case .finished:
            return CGPoint(x: startX, y: emergeY - 14)
        }
    }

    private var scale: CGSize {
        switch phase {
        case .waiting:
            return CGSize(width: 0.42, height: 0.42)
        case .emerged:
            return CGSize(width: 1.08, height: 1.08)
        case .falling:
            return reduceMotion ? CGSize(width: 1, height: 1) : CGSize(width: 1.16, height: 0.74)
        case .bounced:
            return CGSize(width: 0.92, height: 1.12)
        case .finished:
            return CGSize(width: 0.76, height: 0.76)
        }
    }

    private var rotation: Double {
        switch phase {
        case .waiting:
            return -8
        case .emerged:
            return coin.rotation * 0.08
        case .falling:
            return reduceMotion ? coin.rotation * 0.08 : coin.rotation
        case .bounced:
            return coin.rotation * 1.12
        case .finished:
            return coin.rotation * 1.22
        }
    }

    private var opacity: Double {
        switch phase {
        case .waiting:
            return 0
        case .emerged, .falling:
            return 1
        case .bounced:
            return 0.92
        case .finished:
            return 0
        }
    }

    private var startX: CGFloat {
        let laneFraction = Self.laneFractions[coin.lane % Self.laneFractions.count]
        let rawX = sourceFrame.minX + sourceFrame.width * laneFraction
        let inset = coin.size / 2 + 12
        return min(max(inset, rawX), max(inset, pageWidth - inset))
    }

    private var spawnY: CGFloat {
        sourceFrame.midY
    }

    private var emergeY: CGFloat {
        sourceFrame.minY - 4
    }

    private var impactCenterY: CGFloat {
        max(sourceFrame.maxY + 72, collisionY - coin.size / 2)
    }

    private var bouncedY: CGFloat {
        max(sourceFrame.maxY + 40, impactCenterY - coin.bounceHeight)
    }

    private func startAnimation() {
        guard phase == .waiting else { return }

        if reduceMotion {
            withAnimation(.snappy(duration: 0.16).delay(coin.delay)) {
                phase = .emerged
            } completion: {
                withAnimation(.easeOut(duration: 0.28)) {
                    phase = .finished
                }
            }
            return
        }

        withAnimation(.spring(response: 0.14, dampingFraction: 0.68).delay(coin.delay)) {
            phase = .emerged
        } completion: {
            withAnimation(.easeIn(duration: 0.34)) {
                phase = .falling
            } completion: {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.48)) {
                    phase = .bounced
                } completion: {
                    withAnimation(.easeOut(duration: 0.16)) {
                        phase = .finished
                    }
                }
            }
        }
    }
}

private enum CoinDropPhase {
    case waiting
    case emerged
    case falling
    case bounced
    case finished
}

private struct YenCoin: View {
    var size: CGFloat

    var body: some View {
        Text("¥")
            .font(.system(size: size * 0.58, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RadialGradient(colors: [Color(red: 1, green: 0.92, blue: 0.62), WNFTheme.gold], center: .topLeading, startRadius: 2, endRadius: size),
                in: Circle()
            )
            .shadow(color: WNFTheme.gold.opacity(0.45), radius: 8, y: 4)
    }
}

#Preview {
    HomeView()
        .environmentObject(WageState())
        .environmentObject(HomeMascotVideoController())
}
