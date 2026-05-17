import AVFoundation
import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var state: WageState
    @Binding private var isShareCardPresented: Bool
    private var onShare: () -> Void

    init(isShareCardPresented: Binding<Bool> = .constant(false), onShare: @escaping () -> Void = {}) {
        self._isShareCardPresented = isShareCardPresented
        self.onShare = onShare
    }

    var body: some View {
        ZStack {
            WNFTheme.bg.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HeroHomePage(day: state.calculation(at: context.date), onShare: onShare)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar(onShare: onShare)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 14) {
                StatusChip(label: day.status.label)
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
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 16)

            HomeMascotStage(quote: day.status.quote)
                .padding(.bottom, 145)
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
            .onAppear {
                controller.start()
            }
            .onDisappear {
                controller.pause()
            }
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
        isPlaybackRequested = true
        fillQueue()
        player.play()
    }

    func pause() {
        isPlaybackRequested = false
        player.pause()
    }

    func releaseQueue() {
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
            self?.releaseQueue()
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

struct ShareCardCopy: Equatable {
    var title: String
    var subtitle: String

    static let `default` = ShareCardCopy(
        title: "今天没有赢，\n但到账了。",
        subtitle: "工位把我按住，工资负责安慰。"
    )

    static let pool: [ShareCardCopy] = [
        .default,
        ShareCardCopy(
            title: "人在工位，\n钱在路上。",
            subtitle: "今天又把生活按时熬过一段。"
        ),
        ShareCardCopy(
            title: "今天也没翻身，\n但有进账。",
            subtitle: "打工的委屈，先折成数字存起来。"
        ),
        ShareCardCopy(
            title: "班是上的，\n钱是到账的。",
            subtitle: "没有热血剧情，只有稳定入账。"
        ),
        ShareCardCopy(
            title: "又被工作拿捏，\n也被工资哄好。",
            subtitle: "今天的窝囊，明天再继续算。"
        ),
        ShareCardCopy(
            title: "体面没赢，\n余额加分。",
            subtitle: "把不想上班的心情，换成可见进度。"
        ),
        ShareCardCopy(
            title: "工位困住我，\n到账放过我。",
            subtitle: "今天的辛苦，有数字替我作证。"
        )
    ]

    static func random(excluding current: ShareCardCopy) -> ShareCardCopy {
        let nextPool = pool.filter { $0 != current }
        return nextPool.randomElement() ?? current
    }
}

struct ShareCardOverlay: View {
    var day: WageDay
    var copy: ShareCardCopy
    @Binding var hidesSensitiveInfo: Bool
    var isPreparingShare: Bool
    var onShare: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            WonangfeiShareCard(
                day: day,
                copy: copy,
                hidesSensitiveInfo: hidesSensitiveInfo,
                showsControls: true,
                isPreparingShare: isPreparingShare,
                onTogglePrivacy: {
                    withAnimation(.snappy(duration: 0.18)) {
                        hidesSensitiveInfo.toggle()
                    }
                },
                onShare: onShare,
                onDismiss: onDismiss
            )
            .frame(maxWidth: 330)
            .padding(.horizontal, 41)
            .shadow(color: .black.opacity(0.24), radius: 24, y: 16)
            .offset(y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea(.container, edges: .all)
    }
}

struct WonangfeiShareCard: View {
    var day: WageDay
    var copy: ShareCardCopy = .default
    var hidesSensitiveInfo: Bool
    var showsControls: Bool
    var isPreparingShare: Bool = false
    var onTogglePrivacy: () -> Void
    var onShare: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            bodyContent
        }
        .background(WNFTheme.bg, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("CowThreeQ")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .padding(4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("窝囊费")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                Text("今日窝囊战报")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(WNFTheme.inkSoft)
            }

            Spacer(minLength: 8)

            if showsControls {
                HStack(spacing: 8) {
                    ShareCardIconButton(
                        systemName: hidesSensitiveInfo ? "eye.slash" : "eye",
                        accessibilityLabel: hidesSensitiveInfo ? "显示敏感信息" : "隐藏敏感信息",
                        action: onTogglePrivacy
                    )
                    ShareCardIconButton(
                        systemName: "square.and.arrow.up",
                        accessibilityLabel: isPreparingShare ? "正在生成分享图" : "唤起系统分享",
                        isLoading: isPreparingShare,
                        isDisabled: isPreparingShare,
                        action: onShare
                    )
                    ShareCardIconButton(
                        systemName: "xmark",
                        accessibilityLabel: "退出分享卡片",
                        action: onDismiss
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(WNFTheme.gold)
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 0)
                .overlay(
                    Rectangle()
                        .stroke(WNFTheme.muted.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [8, 8]))
                )
                .padding(.horizontal, -18)
                .padding(.top, -13)

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.title)
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundStyle(WNFTheme.ink)
                        .lineSpacing(-2)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(copy.subtitle)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(WNFTheme.inkSoft)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(day.status.mascotAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 66, height: 66)
                    .padding(.top, 8)
            }

            statsPanel

            HStack {
                Text("丧萌有理 · 自嘲无罪")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    YenBadge(size: 16)
                    Text("来自窝囊费")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WNFTheme.ink)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [WNFTheme.bg.opacity(0.98), WNFTheme.surfaceSoft.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var statsPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日窝囊费")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)
                Spacer(minLength: 12)
                Text(WNFFormat.moneyDecimal(day.earnedToday, privacy: hidesSensitiveInfo))
                    .font(.system(size: 35, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 10)

            Rectangle()
                .fill(WNFTheme.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            HStack(alignment: .firstTextBaseline) {
                Text("上班上了多久")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)
                Spacer(minLength: 12)
                Text(hidesSensitiveInfo ? "••h••min" : WNFFormat.duration(day.elapsedPaidMinutes))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.coral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(WNFTheme.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(WNFTheme.muted.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .padding(9)
        )
        .padding(8)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }
}

private struct ShareCardIconButton: View {
    var systemName: String
    var accessibilityLabel: String
    var isLoading = false
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(WNFTheme.ink)
                        .scaleEffect(0.68)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WNFTheme.ink)
                }
            }
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
        .animation(.easeInOut(duration: 0.14), value: isLoading)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
