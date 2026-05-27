import AVFoundation
import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var state: WageState
    @Binding private var isShareCardPresented: Bool
    private var onShare: () -> Void
    private var onClockOut: () -> Void

    init(
        isShareCardPresented: Binding<Bool> = .constant(false),
        onShare: @escaping () -> Void = {},
        onClockOut: @escaping () -> Void = {}
    ) {
        self._isShareCardPresented = isShareCardPresented
        self.onShare = onShare
        self.onClockOut = onClockOut
    }

    var body: some View {
        ZStack {
            WNFTheme.bg.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HeroHomePage(
                    day: state.calculation(at: context.date),
                    onShare: onShare,
                    onClockOut: onClockOut
                )
            }
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
    @StateObject private var quoteEngine: BubbleQuoteEngine
    var day: WageDay
    var onShare: () -> Void
    var onClockOut: () -> Void

    init(day: WageDay, onShare: @escaping () -> Void, onClockOut: @escaping () -> Void) {
        self.day = day
        self.onShare = onShare
        self.onClockOut = onClockOut
        self._quoteEngine = StateObject(wrappedValue: BubbleQuoteEngine(initialStatus: day.status))
    }

    private var statusPresentation: WorkStatusPresentation {
        WorkStatusPresentation(status: day.status)
    }

    private var statusChipLabel: String {
        state.isTodaySettled ? "今日已结算 · 个人时间" : statusPresentation.label
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
                TopBar(onShare: onShare)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 14) {
                    StatusChip(label: statusChipLabel)
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("今 日 窝 囊 费")
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(5)
                            .foregroundStyle(WNFTheme.inkSoft)

                        BigMoneyText(value: day.earnedToday, privacy: state.privacyMode)
                    }

                    HStack(spacing: 18) {
                        Text("已忍 \(WNFFormat.duration(day.elapsedPaidMinutes))")
                        Circle().fill(WNFTheme.muted).frame(width: 4, height: 4)
                        Text("离下班 \(WNFFormat.duration(day.wallToEndMinutes))")
                    }
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)

                    ProgressTrack(day: day, startText: state.workStart.clockText, endText: state.workEnd.clockText)

                    ClockOutCTA(
                        status: day.status,
                        isSettled: state.isTodaySettled,
                        action: onClockOut
                    )
                    .anchorPreference(key: ClockOutCTAAnchorKey.self, value: .bounds) { $0 }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 22)

                Spacer(minLength: 16)

                HomeMascotStage(quote: quoteEngine.currentQuote, bubbleOffset: quoteEngine.bubbleOffset)
                    .padding(.bottom, mascotBottomPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .overlayPreferenceValue(ClockOutCTAAnchorKey.self) { anchor in
                if let anchor {
                    HomeCoinDropLayer(
                        day: day,
                        isSettled: state.isTodaySettled,
                        ctaFrame: proxy[anchor],
                        pageSize: proxy.size,
                        collisionY: coinCollisionY(in: proxy.size)
                    )
                }
            }
        }
        .onChange(of: day.status) { _, newStatus in
            quoteEngine.setStatus(newStatus)
        }
    }

    private func coinCollisionY(in size: CGSize) -> CGFloat {
        guard tabBarFloorHeight > 0 else {
            return size.height - 72
        }
        return max(0, size.height - tabBarFloorHeight)
    }
}

private struct ClockOutCTAAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct HomeMascotStage: View {
    var quote: String
    var bubbleOffset: CGSize

    private let stageHeight: CGFloat = 285

    var body: some View {
        HomeMascotVideoSequence()
            .frame(width: stageHeight, height: stageHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                Text(quote)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(WNFTheme.ink)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 17))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    .offset(x: bubbleOffset.width, y: bubbleOffset.height)
                    .id(quote)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: stageHeight)
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

final class HomeMascotVideoController: ObservableObject {
    let player = AVQueuePlayer()
    private let clips: [HomeMascotVideoClip]
    private var pendingClips: [HomeMascotVideoClip] = []
    private var lastPlayedClip: HomeMascotVideoClip?
    private var endObserver: NSObjectProtocol?
    private var memoryWarningObserver: NSObjectProtocol?
    private var isPlaybackRequested = false
    private let minimumQueuedItemCount = 3

    init() {
        self.clips = HomeMascotVideoClip.all
        configurePlayer()
        installEndObserver()
        installMemoryWarningObserver()
    }

    fileprivate init(clips: [HomeMascotVideoClip]) {
        self.clips = clips
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
            guard self?.isPlaybackRequested == true else { return }
            self?.fillQueue()
        }
    }

    private func installMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pauseAndRelease()
        }
    }
}

private struct HomeMascotVideoClip: Equatable {
    var resourceName: String

    static let all = [
        HomeMascotVideoClip(resourceName: "home-typing"),
        HomeMascotVideoClip(resourceName: "home-bored")
    ]
}

private struct BigMoneyText: View {
    var value: Double
    var privacy: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("¥")
                .foregroundStyle(WNFTheme.yellow)
            if privacy {
                Text("•••")
                    .tracking(4)
                Text(".••")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.muted)
            } else {
                let totalCents = max(0, Int((value * 100).rounded(.down)))
                let integer = totalCents / 100
                let cents = totalCents % 100
                Text(integer.formatted(.number.grouping(.automatic)))
                Text(String(format: ".%02d", cents))
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.muted)
            }
        }
        .font(.system(size: 86, weight: .black, design: .rounded))
        .minimumScaleFactor(0.58)
        .lineLimit(1)
        .contentTransition(.numericText(value: value))
        .animation(.linear(duration: 0.2), value: value)
    }
}

private struct ProgressTrack: View {
    var day: WageDay
    var startText: String
    var endText: String

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 0.95, green: 0.90, blue: 0.75))
                    Capsule()
                        .fill(LinearGradient(colors: [WNFTheme.gold, WNFTheme.yellow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * day.progress)
                    if day.progress > 0 && day.progress < 1 {
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(WNFTheme.ink, lineWidth: 3))
                            .frame(width: 15, height: 15)
                            .offset(x: max(0, proxy.size.width * day.progress - 7))
                    }
                }
            }
            .frame(height: 13)

            HStack {
                Text(startText)
                Spacer()
                Text("\(Int(day.progress * 100))%")
                Spacer()
                Text(endText)
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(WNFTheme.muted)
        }
    }
}

private struct HomeCoinDropLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var day: WageDay
    var isSettled: Bool
    var ctaFrame: CGRect
    var pageSize: CGSize
    var collisionY: CGFloat

    @State private var coins: [HomeFallingCoin] = []
    @State private var lastMilestone: Int?
    @State private var emissionIndex = 0

    private static let coinStep: Double = 0.10
    private static let maxCatchUpCoins = 3

    private var signal: HomeCoinSignal {
        HomeCoinSignal(
            milestone: Int((max(0, day.earnedToday) / Self.coinStep + 0.0001).rounded(.down)),
            canEmit: canEmitCoins,
            shouldClear: isSettled
        )
    }

    private var canEmitCoins: Bool {
        guard !isSettled else { return false }
        switch day.status {
        case .morning, .afternoon:
            return true
        case .before, .lunch, .done:
            return false
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(coins) { coin in
                HomeDroppingCoin(
                    coin: coin,
                    ctaFrame: ctaFrame,
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
    }

    private func primeBaseline() {
        guard lastMilestone == nil else { return }
        lastMilestone = signal.milestone
        if signal.shouldClear {
            coins.removeAll()
        }
    }

    private func reconcile(_ signal: HomeCoinSignal) {
        if signal.shouldClear {
            coins.removeAll()
            lastMilestone = signal.milestone
            return
        }

        guard signal.canEmit else {
            lastMilestone = signal.milestone
            return
        }

        guard let previousMilestone = lastMilestone else {
            lastMilestone = signal.milestone
            return
        }

        guard signal.milestone > previousMilestone else {
            lastMilestone = signal.milestone
            return
        }

        let spawnCount = min(signal.milestone - previousMilestone, Self.maxCatchUpCoins)
        lastMilestone = signal.milestone
        emitCoins(count: spawnCount)
    }

    private func emitCoins(count: Int) {
        guard count > 0, ctaFrame.width > 0, pageSize.height > 0 else { return }

        for burstIndex in 0..<count {
            let coin = HomeFallingCoin(sequence: emissionIndex, burstIndex: burstIndex)
            emissionIndex += 1
            coins.append(coin)
            scheduleRemoval(for: coin)
        }
    }

    private func scheduleRemoval(for coin: HomeFallingCoin) {
        let lifetimeNanoseconds = UInt64((2.2 + coin.delay) * 1_000_000_000)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: lifetimeNanoseconds)
            coins.removeAll { $0.id == coin.id }
        }
    }
}

private struct HomeCoinSignal: Equatable {
    var milestone: Int
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

    init(sequence: Int, burstIndex: Int) {
        self.sequence = sequence
        lane = sequence % 5
        size = CGFloat(22 + (sequence % 4) * 3)
        delay = Double(burstIndex) * 0.08

        let driftDirection: CGFloat = sequence.isMultiple(of: 2) ? -1 : 1
        drift = driftDirection * CGFloat(18 + (sequence % 3) * 10)

        let rotationDirection = sequence.isMultiple(of: 2) ? -1.0 : 1.0
        rotation = rotationDirection * Double(155 + (sequence % 5) * 26)
        bounceHeight = CGFloat(22 + (sequence % 4) * 8)
    }
}

private struct HomeDroppingCoin: View {
    var coin: HomeFallingCoin
    var ctaFrame: CGRect
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
            return CGPoint(x: startX, y: insideCardY)
        case .emerged:
            return CGPoint(x: startX + coin.drift * 0.08, y: cardMouthY)
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
            return CGPoint(x: startX, y: insideCardY)
        case .emerged, .falling, .bounced:
            return CGPoint(x: startX, y: cardMouthY - 8)
        case .finished:
            return CGPoint(x: startX, y: cardMouthY - 14)
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
        let rawX = ctaFrame.minX + ctaFrame.width * laneFraction
        let inset = coin.size / 2 + 12
        return min(max(inset, rawX), max(inset, pageWidth - inset))
    }

    private var insideCardY: CGFloat {
        ctaFrame.maxY - max(18, min(30, ctaFrame.height * 0.24))
    }

    private var cardMouthY: CGFloat {
        ctaFrame.maxY - 6
    }

    private var impactCenterY: CGFloat {
        max(ctaFrame.maxY + 72, collisionY - coin.size / 2)
    }

    private var bouncedY: CGFloat {
        max(ctaFrame.maxY + 40, impactCenterY - coin.bounceHeight)
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

        withAnimation(.spring(response: 0.22, dampingFraction: 0.72).delay(coin.delay)) {
            phase = .emerged
        } completion: {
            withAnimation(.easeIn(duration: 0.58)) {
                phase = .falling
            } completion: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.56)) {
                    phase = .bounced
                } completion: {
                    withAnimation(.easeOut(duration: 0.24)) {
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
