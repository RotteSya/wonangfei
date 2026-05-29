import SwiftUI

struct CoinSourceAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct HomeCoinDropLayer: View {
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
        case .before, .lunch, .done:
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
