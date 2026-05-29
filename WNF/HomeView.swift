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
        state.isTodaySettled ? "今日已下班 · 个人时间" : statusPresentation.label
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

                    if state.isTodaySettled || day.status == .done {
                        ClockOutCTA(
                            status: day.status,
                            isSettled: state.isTodaySettled,
                            action: onClockOut
                        )
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 22)

                Spacer(minLength: 16)

                HomeMascotStage(quote: quoteEngine.currentQuote, bubbleOffset: quoteEngine.bubbleOffset)
                    .padding(.bottom, mascotBottomPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .overlayPreferenceValue(CoinSourceAnchorKey.self) { anchor in
                if let anchor {
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
    private var endObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var memoryWarningObserver: NSObjectProtocol?
    private var isPlaybackRequested = false
    private let minimumQueuedItemCount = 3

    init() {
        self.clips = HomeMascotVideoClip.all
        configurePlayer()
        installMemoryWarningObserver()
    }

    fileprivate init(clips: [HomeMascotVideoClip]) {
        self.clips = clips
        configurePlayer()
        installMemoryWarningObserver()
    }

    private func configurePlayer() {
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = .advance
    }

    deinit {
        removeEndObservers()
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
        removeEndObservers()
        pendingClips.removeAll(keepingCapacity: true)
    }

    private func fillQueue() {
        guard !clips.isEmpty else { return }

        while player.items().count < minimumQueuedItemCount {
            guard let item = makeNextItem() else { return }
            player.insert(item, after: nil)
            installEndObserver(for: item)
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

    private func installEndObserver(for item: AVPlayerItem) {
        let id = ObjectIdentifier(item)
        guard endObservers[id] == nil else { return }

        endObservers[id] = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            guard let self else { return }
            if let item {
                self.removeEndObserver(for: item)
            }
            guard self.isPlaybackRequested else { return }
            self.fillQueue()
        }
    }

    private func removeEndObserver(for item: AVPlayerItem) {
        let id = ObjectIdentifier(item)
        guard let observer = endObservers.removeValue(forKey: id) else { return }
        NotificationCenter.default.removeObserver(observer)
    }

    private func removeEndObservers() {
        for observer in endObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
        endObservers.removeAll()
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
            .anchorPreference(key: CoinSourceAnchorKey.self, value: .bounds) { $0 }

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

#Preview {
    HomeView()
        .environmentObject(WageState())
        .environmentObject(HomeMascotVideoController())
}
