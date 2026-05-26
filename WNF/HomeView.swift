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
    var day: WageDay
    var onShare: () -> Void
    var onClockOut: () -> Void

    private var statusPresentation: WorkStatusPresentation {
        WorkStatusPresentation(status: day.status)
    }

    private var statusChipLabel: String {
        state.isTodaySettled ? "今日已结算 · 个人时间" : statusPresentation.label
    }

    var body: some View {
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
                .padding(.top, 4)
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 16)

            HomeMascotStage(quote: statusPresentation.quote)
                .padding(.bottom, 100)
        }
    }
}

private struct HomeMascotStage: View {
    var quote: String

    private let stageHeight: CGFloat = 285
    private let trailingCoinSize: CGFloat = 25
    private let leadingCoinSize: CGFloat = 22

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
                    .offset(x: 42, y: 18)
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        YenCoin(size: trailingCoinSize)
                            .offset(x: trailingCoinOffsetX(in: proxy.size.width), y: 72)
                        YenCoin(size: leadingCoinSize)
                            .offset(x: leadingCoinOffsetX(in: proxy.size.width), y: 220)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: stageHeight)
    }

    private func trailingCoinOffsetX(in width: CGFloat) -> CGFloat {
        let requestedOffset = width - 84
        let maximumVisibleOffset = max(16, width - trailingCoinSize - 16)
        return min(max(16, requestedOffset), maximumVisibleOffset)
    }

    private func leadingCoinOffsetX(in width: CGFloat) -> CGFloat {
        let maximumVisibleOffset = max(16, width - leadingCoinSize - 16)
        return min(48, maximumVisibleOffset)
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
