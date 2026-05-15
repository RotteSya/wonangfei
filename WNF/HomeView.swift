import AVFoundation
import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var state: WageState

    private var day: WageDay { state.calculation }
    private var display: WageDisplayModel {
        WageDisplayModel(day: day, settings: state.settings, now: state.currentDate)
    }

    var body: some View {
        ZStack {
            WNFTheme.bg.ignoresSafeArea()

            HeroHomePage(day: day, display: display)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct HeroHomePage: View {
    @EnvironmentObject private var state: WageState
    var day: WageDay
    var display: WageDisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 13) {
                StatusChip(label: display.statusLabel)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 5) {
                    Text(display.headline)
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(5)
                        .foregroundStyle(WNFTheme.inkSoft)

                    BigMoneyText(value: display.mainAmount, privacy: state.privacyMode, showsPlus: display.showsPlus)
                }

                Text(display.detailText)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if day.status == .overtime {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            state.endToday()
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("结束今日")
                        }
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WNFTheme.ink)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(WNFTheme.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }

                ProgressTrack(day: day, startText: state.workStart.clockText, endText: state.workEnd.clockText)

                if day.status == .afterWork || day.status == .overtime || day.status == .lateNight || day.status == .dayOff {
                    DailySummaryCard(rows: display.summaryRows)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 10)

            ZStack(alignment: .topLeading) {
                HomeSpriteView(fallbackAsset: display.mascotAsset, usesAnimatedSprite: display.usesAnimatedSprite)
                    .frame(width: 285, height: 285)
                    .frame(maxWidth: .infinity)

                Text(display.quote)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(WNFTheme.ink)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 17))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    .offset(x: 42, y: 18)

                YenCoin(size: 25)
                    .offset(x: UIScreen.main.bounds.width - 84, y: 72)
                YenCoin(size: 22)
                    .offset(x: 48, y: 220)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, day.status == .afterWork || day.status == .overtime || day.status == .dayOff ? 116 : 145)
        }
    }
}

private struct HomeSpriteView: View {
    var fallbackAsset: String
    var usesAnimatedSprite: Bool

    var body: some View {
        if usesAnimatedSprite, let url = Bundle.main.url(forResource: "HomeSprite", withExtension: "mov") {
            LoopingVideoView(url: url)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel("窝囊牛动画")
        } else {
            Image(fallbackAsset)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("窝囊牛")
        }
    }
}

private struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: url)

        context.coordinator.player = player
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)

        player.isMuted = true
        player.play()
        view.playerLayer.player = player

        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        context.coordinator.player?.play()
    }

    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.looper = nil
        coordinator.player = nil
        uiView.playerLayer.player = nil
    }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }
}

private final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
    }
}

private struct BigMoneyText: View {
    var value: Double
    var privacy: Bool
    var showsPlus = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(showsPlus ? "+¥" : "¥")
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

private struct DailySummaryCard: View {
    var rows: [WageSummaryRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日小结")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(WNFTheme.muted)
                .tracking(1.5)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(WNFTheme.muted)
                        Text(row.value)
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundStyle(WNFTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WNFTheme.hairline, lineWidth: 0.5))
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
}
