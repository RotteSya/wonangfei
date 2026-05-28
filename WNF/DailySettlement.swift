import SwiftUI
import UIKit

// MARK: - Data Model

enum SettlementSentiment: Int, CaseIterable, Equatable {
    case wisp = 1
    case mild = 2
    case standard = 3
    case heavy = 4

    var stars: Int { rawValue }
    var maxStars: Int { 4 }

    var label: String {
        switch self {
        case .wisp: "今日溜走"
        case .mild: "轻度搬砖"
        case .standard: "稳定窝囊"
        case .heavy: "高强度忍耐"
        }
    }

    var emoji: String {
        switch self {
        case .wisp: "🫥"
        case .mild: "😐"
        case .standard: "😮‍💨"
        case .heavy: "🥲"
        }
    }
}

struct DailySettlement: Equatable {
    var dateKey: String
    var earnedToday: Double
    var elapsedPaidMinutes: Int
    var workdayMinutes: Int
    var progress: Double
    var sentiment: SettlementSentiment
    var streakDays: Int
    var headline: String
    var subCopy: String
    var bestMoment: String
    var cumulativeEarned: Double
    var status: WorkStatus
    var capturedAt: Date

    static func derive(
        from day: WageDay,
        dailyRecords: [String: DailyWageRecord],
        at date: Date = Date()
    ) -> DailySettlement {
        let progress = day.progress
        let sentiment = deriveSentiment(progress: progress, status: day.status)
        let streakDays = deriveStreakDays(
            dailyRecords: dailyRecords,
            includingTodayEarned: day.earnedToday,
            today: date
        )
        let cumulativeEarned = deriveCumulativeEarned(
            dailyRecords: dailyRecords,
            includingTodayEarned: day.earnedToday,
            todayDateKey: WageState.dateKey(for: date)
        )
        let copy = pickCopy(sentiment: sentiment, status: day.status, streakDays: streakDays)
        return DailySettlement(
            dateKey: WageState.dateKey(for: date),
            earnedToday: day.earnedToday,
            elapsedPaidMinutes: day.elapsedPaidMinutes,
            workdayMinutes: day.workdayMinutes,
            progress: progress,
            sentiment: sentiment,
            streakDays: streakDays,
            headline: copy.headline,
            subCopy: copy.subCopy,
            bestMoment: copy.bestMoment,
            cumulativeEarned: cumulativeEarned,
            status: day.status,
            capturedAt: date
        )
    }

    /// Pick a different best-moment line than the current one. Used by the tear gesture
    /// on the settlement card so consecutive long-presses always swap content.
    static func alternateBestMoment(excluding current: String) -> String {
        let pool = bestMomentPool.filter { $0 != current }
        return pool.randomElement() ?? bestMomentPool[0]
    }

    private static func deriveSentiment(progress: Double, status: WorkStatus) -> SettlementSentiment {
        // `.done` always implies the user finished a full workday's worth of
        // elapsed time (WageCalculator caps elapsed at workdayMinutes).
        if status == .done {
            return .heavy
        }
        switch progress {
        case ..<0.05: return .wisp
        case ..<0.35: return .mild
        case ..<0.65: return .standard
        default: return .heavy
        }
    }

    static let bestMomentPool: [String] = [
        "把哈欠忍成了沉默",
        "在工位坐到走不动",
        "看完一封不想回的邮件",
        "听完一场无关的会",
        "对显示器叹了三次气",
        "把咖啡喝凉了第二轮",
        "假装在写代码其实在发呆",
        "把不耐烦藏进了「好的」",
        "刷新邮箱十七次",
        "回了一句「收到，马上处理」"
    ]

    private static func deriveCumulativeEarned(
        dailyRecords: [String: DailyWageRecord],
        includingTodayEarned: Double,
        todayDateKey: String
    ) -> Double {
        // Sum every closed daily record plus today's live amount. The dictionary may also
        // contain a record for today (when it was persisted on scene change), so we replace
        // that with the live amount to avoid double counting.
        let historicalSum = dailyRecords
            .filter { $0.key != todayDateKey }
            .values
            .map(\.earnedToday)
            .reduce(0, +)
        return historicalSum + max(includingTodayEarned, dailyRecords[todayDateKey]?.earnedToday ?? 0)
    }

    private static func deriveStreakDays(
        dailyRecords: [String: DailyWageRecord],
        includingTodayEarned: Double,
        today: Date
    ) -> Int {
        let calendar = DateComponents.calendar
        let todayEarned: Double = includingTodayEarned > 0
            ? includingTodayEarned
            : (dailyRecords[WageState.dateKey(for: today)]?.earnedToday ?? 0)

        // A streak that "ends today" must include today. If today is zero,
        // the streak is zero — don't silently pick up yesterday's history.
        guard todayEarned > 0 else { return 0 }

        let maxStreak = 60
        var streak = 1
        var cursor = today
        while streak < maxStreak {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
            let key = WageState.dateKey(for: previous)
            guard let record = dailyRecords[key], record.earnedToday > 0 else { break }
            streak += 1
        }
        return streak
    }

    private struct CopyPick {
        var headline: String
        var subCopy: String
        var bestMoment: String
    }

    private static func pickCopy(
        sentiment: SettlementSentiment,
        status: WorkStatus,
        streakDays: Int
    ) -> CopyPick {
        let bestMoment = bestMomentPool.randomElement() ?? bestMomentPool[0]

        switch sentiment {
        case .wisp:
            return CopyPick(
                headline: "今天还没真正开张",
                subCopy: streakDays > 1
                    ? "连续 \(streakDays) 天打工的你，偶尔溜走也算合理。"
                    : "今天的窝囊费比较薄，明天再战。",
                bestMoment: bestMoment
            )
        case .mild:
            return CopyPick(
                headline: "轻量忍耐入账",
                subCopy: streakDays > 1
                    ? "连续 \(streakDays) 天，今天的窝囊费小到可以请杯咖啡。"
                    : "今天的窝囊费小，但已经收下了。",
                bestMoment: bestMoment
            )
        case .standard:
            return CopyPick(
                headline: "今天稳定窝囊",
                subCopy: streakDays > 1
                    ? "连续 \(streakDays) 天稳定到账，工位虽冷板凳但票稳。"
                    : "稳定挣进口袋，没赢也没输。",
                bestMoment: bestMoment
            )
        case .heavy:
            return CopyPick(
                headline: "今天全程忍住",
                subCopy: streakDays > 1
                    ? "连续 \(streakDays) 天全勤，今日窝囊费已收下。"
                    : "完整熬完一天，窝囊费已收下。",
                bestMoment: bestMoment
            )
        }
    }
}

// MARK: - Coin Burst Animation

struct SettlementCoinBurst: View {
    var expanded: Bool
    var coinCount: Int = 24

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(expanded ? 0.0 : 0.96),
                                WNFTheme.yellow.opacity(expanded ? 0.0 : 0.78),
                                WNFTheme.gold.opacity(0)
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: size * 0.62
                        )
                    )
                    .frame(width: expanded ? size * 2.4 : 36, height: expanded ? size * 2.4 : 36)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .opacity(expanded ? 0 : 1)

                ForEach(0..<coinCount, id: \.self) { index in
                    SettlementCoinParticle(index: index, total: coinCount, expanded: expanded)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }

                Text("¥")
                    .font(.system(size: expanded ? 92 : 32, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.yellow)
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
                    .scaleEffect(expanded ? 1.18 : 0.35)
                    .opacity(expanded ? 0 : 1)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SettlementCoinParticle: View {
    var index: Int
    var total: Int
    var expanded: Bool

    private var angle: Double {
        Double(index) / Double(max(1, total)) * .pi * 2
    }

    private var distance: CGFloat {
        expanded ? CGFloat(120 + (index % 6) * 30) : 0
    }

    private var coinSize: CGFloat {
        CGFloat(26 + (index % 4) * 6)
    }

    private var fontSize: CGFloat {
        CGFloat(14 + (index % 4) * 3)
    }

    private var xOffset: CGFloat {
        CGFloat(cos(angle)) * distance
    }

    private var yOffset: CGFloat {
        CGFloat(sin(angle)) * distance
    }

    private var confettiColor: Color {
        let palette: [Color] = [WNFTheme.coral, Color(red: 0.49, green: 0.78, blue: 0.38), WNFTheme.cyan]
        return palette[index % palette.count]
    }

    private var isCoin: Bool { index % 3 != 0 }

    var body: some View {
        content
            .offset(x: xOffset, y: yOffset)
            .scaleEffect(expanded ? 1 : 0.2)
            .rotationEffect(.degrees(expanded ? Double(index * 27 + 90) : 0))
            .opacity(expanded ? 0 : 1)
            .animation(
                .spring(response: 0.72, dampingFraction: 0.78).delay(Double(index % 6) * 0.02),
                value: expanded
            )
    }

    @ViewBuilder
    private var content: some View {
        if isCoin {
            Text("¥")
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: coinSize, height: coinSize)
                .background(WNFTheme.yellow, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(confettiColor)
                .frame(width: 16, height: 11)
                .rotationEffect(.degrees(Double(index * 17)))
        }
    }
}

// MARK: - Settlement Overlay (Modal)

struct DailySettlementOverlay: View {
    enum Phase: Equatable {
        case prep
        case burst
        case reveal
        case tearing
    }

    var settlement: DailySettlement
    var template: PremiumShareTemplateID
    @Binding var hidesSensitiveInfo: Bool
    var isPreparingShare: Bool
    var onShare: () -> Void
    var onSaveAsAsset: () -> Void
    var onDismiss: () -> Void

    @State private var phase: Phase = .prep
    @State private var burstExpanded = false
    @State private var displayedAmount: Double = 0
    @State private var revealCardVisible = false
    @State private var revealActionsVisible = false
    @State private var currentBestMoment: String = ""
    @State private var tearSnapshot: UIImage?
    @State private var tearNormalizedY: CGFloat = 0.5
    @State private var tearJitter: [CGFloat] = []
    @State private var tearWindup: Double = 0
    @State private var tearSeparation: Double = 0
    @State private var tearFlight: Double = 0
    @State private var tearConfettiProgress: Double = 0
    @State private var tearConfettiSeed: UInt64 = 0

    private let burstDuration: TimeInterval = 0.85
    private let amountRampDuration: TimeInterval = 0.7
    private let revealDelay: TimeInterval = 0.5

    var body: some View {
        ZStack {
            backdrop
            content
            burstLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if currentBestMoment.isEmpty { currentBestMoment = settlement.bestMoment }
            startBurstSequence()
        }
    }

    private func tearBestMoment() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        let next = DailySettlement.alternateBestMoment(excluding: currentBestMoment)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            currentBestMoment = next
        }
    }

    private var backdrop: some View {
        Color.black
            .opacity(phase == .prep ? 0 : (phase == .burst ? 0.32 : 0.62))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                if phase == .reveal {
                    onDismiss()
                }
            }
            .animation(.easeInOut(duration: 0.32), value: phase)
    }

    private var burstLayer: some View {
        SettlementCoinBurst(expanded: burstExpanded)
            .allowsHitTesting(false)
            .opacity(phase == .burst ? 1 : 0)
            .animation(.easeOut(duration: 0.4), value: phase)
            .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            DailySettlementShareCard(
                settlement: settlement,
                template: template,
                displayedAmount: displayedAmount,
                displayedBestMoment: currentBestMoment.isEmpty ? settlement.bestMoment : currentBestMoment,
                hidesSensitiveInfo: hidesSensitiveInfo,
                showsControls: true,
                isPreparingShare: isPreparingShare,
                onTogglePrivacy: {
                    withAnimation(.snappy(duration: 0.18)) {
                        hidesSensitiveInfo.toggle()
                    }
                },
                onTearBestMoment: tearBestMoment,
                onShare: onShare,
                onDismiss: onDismiss
            )
            .scaleEffect(revealCardVisible ? 1 : 0.86)
            .opacity(phase == .tearing ? 0 : (revealCardVisible ? 1 : 0))
            .allowsHitTesting(revealCardVisible && phase != .tearing)
            .shadow(color: .black.opacity(0.32), radius: 28, y: 18)
            .overlay {
                if phase == .tearing, let snapshot = tearSnapshot {
                    tearLayer(snapshot: snapshot)
                }
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, 28)

            Spacer(minLength: 12)

            actionRow
                .opacity(revealActionsVisible && phase != .tearing ? 1 : 0)
                .offset(y: revealActionsVisible ? 0 : 14)
                .allowsHitTesting(revealActionsVisible && phase != .tearing)

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: revealCardVisible)
        .animation(.easeOut(duration: 0.32).delay(0.18), value: revealActionsVisible)
    }

    private func tearLayer(snapshot: UIImage) -> some View {
        // The top half is the dramatic piece — it gets yanked up and off-screen. The bottom half
        // stays roughly put (only a sliver of drift) so the receipt visually feels "torn off in
        // your hand," not "the whole card slides down."
        let snapTopOffset: CGFloat = -36 * tearSeparation
        let snapBottomOffset: CGFloat = 4 * tearSeparation
        let flyTopOffset: CGFloat = -480 * tearFlight
        let flyBottomOffset: CGFloat = 70 * tearFlight
        let topOffsetY = snapTopOffset + flyTopOffset
        let bottomOffsetY = snapBottomOffset + flyBottomOffset
        let topRotation = -3 * tearSeparation - 8 * tearFlight
        let bottomRotation = 0.6 * tearSeparation + 2 * tearFlight
        let windupScale = 1 - CGFloat(tearWindup) * 0.035
        let opacity = 1 - tearFlight

        return ZStack {
            Image(uiImage: snapshot)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .mask(TearMask(tearNormalizedY: tearNormalizedY, jitter: tearJitter, side: .bottom))
                .offset(y: bottomOffsetY)
                .rotationEffect(.degrees(bottomRotation), anchor: .top)
                .opacity(opacity)

            Image(uiImage: snapshot)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .mask(TearMask(tearNormalizedY: tearNormalizedY, jitter: tearJitter, side: .top))
                .offset(y: topOffsetY)
                .rotationEffect(.degrees(topRotation), anchor: .bottom)
                .opacity(opacity)

            TearConfettiBurst(
                normalizedY: tearNormalizedY,
                progress: tearConfettiProgress,
                seed: tearConfettiSeed
            )
        }
        .scaleEffect(windupScale)
        .shadow(color: .black.opacity(0.32), radius: 28, y: 18)
        .allowsHitTesting(false)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            settlementActionButton(
                title: "下班！",
                systemImage: "tray.and.arrow.down.fill",
                style: .primary
            ) {
                performClockOutTear()
            }

            settlementActionButton(
                title: isPreparingShare ? "渲染中…" : "分享卡片",
                systemImage: "square.and.arrow.up.fill",
                style: .secondary,
                isDisabled: isPreparingShare
            ) {
                onShare()
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    private enum ActionStyle { case primary, secondary }

    private func settlementActionButton(
        title: String,
        systemImage: String,
        style: ActionStyle,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .heavy))
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(style == .primary ? Color.white : WNFTheme.ink)
            .background(
                style == .primary ? WNFTheme.ink : Color.white,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(style == .secondary ? WNFTheme.hairline : Color.clear, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .opacity(isDisabled ? 0.62 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func startBurstSequence() {
        guard phase == .prep else { return }
        phase = .burst
        triggerBurstHaptic()

        withAnimation(.spring(response: burstDuration, dampingFraction: 0.76)) {
            burstExpanded = true
        }

        Task { @MainActor in
            try? await sleep(seconds: revealDelay)
            guard phase == .burst else { return }
            phase = .reveal
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                revealCardVisible = true
            }
            withAnimation(.easeOut(duration: amountRampDuration)) {
                displayedAmount = settlement.earnedToday
            }
            try? await sleep(seconds: 0.18)
            withAnimation(.easeOut(duration: 0.32)) {
                revealActionsVisible = true
            }
        }
    }

    private func triggerBurstHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    private func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64((max(0, seconds) * 1_000_000_000).rounded())
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    @MainActor
    private func performClockOutTear() {
        guard phase == .reveal else { return }

        let snapshotCard = DailySettlementShareCard(
            settlement: settlement,
            template: template,
            displayedAmount: settlement.earnedToday,
            displayedBestMoment: currentBestMoment.isEmpty ? settlement.bestMoment : currentBestMoment,
            hidesSensitiveInfo: hidesSensitiveInfo,
            showsControls: false
        )
        .frame(width: 340)

        let renderer = ImageRenderer(content: snapshotCard)
        renderer.scale = UIScreen.main.scale

        guard let image = renderer.uiImage else {
            onSaveAsAsset()
            return
        }

        tearSnapshot = image
        tearNormalizedY = CGFloat.random(in: 0.32...0.68)
        tearJitter = Self.makeTearJitter(count: 18)
        tearConfettiSeed = UInt64.random(in: 0..<UInt64.max)
        phase = .tearing

        let prepHaptic = UIImpactFeedbackGenerator(style: .light)
        let snapHaptic = UIImpactFeedbackGenerator(style: .heavy)
        prepHaptic.prepare()
        snapHaptic.prepare()

        // Stage 1: 60ms windup — card briefly compresses, like cocking back before the rip.
        prepHaptic.impactOccurred(intensity: 0.7)
        withAnimation(.easeIn(duration: 0.06)) {
            tearWindup = 1
        }

        Task { @MainActor in
            try? await sleep(seconds: 0.07)

            // Stage 2: RIP — heavy haptic, snap apart with overshoot, confetti spreads.
            snapHaptic.impactOccurred()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
                tearWindup = 0
                tearSeparation = 1
            }
            withAnimation(.easeOut(duration: 0.55)) {
                tearConfettiProgress = 1
            }

            try? await sleep(seconds: 0.14)

            // Stage 3: Fly off-screen with rotation + fade.
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.42)) {
                tearFlight = 1
            }

            try? await sleep(seconds: 0.42)
            onSaveAsAsset()
        }
    }

    private static func makeTearJitter(count: Int) -> [CGFloat] {
        (0..<count).map { _ in CGFloat.random(in: -8...8) }
    }
}

// MARK: - Tear Confetti

private struct TearConfettiBurst: View {
    var normalizedY: CGFloat
    var progress: Double
    var seed: UInt64
    var particleCount: Int = 12

    var body: some View {
        GeometryReader { proxy in
            let baseY = proxy.size.height * normalizedY
            let width = proxy.size.width
            ZStack {
                ForEach(0..<particleCount, id: \.self) { index in
                    confettiParticle(index: index, baseY: baseY, width: width)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    private func confettiParticle(index: Int, baseY: CGFloat, width: CGFloat) -> some View {
        // Deterministic per-tear, per-particle pseudo-randomness derived from the seed so the
        // particle paths feel chaotic without re-randomizing on every redraw.
        let hash = TearConfettiBurst.hash(seed: seed, index: UInt64(index))
        let lateralFraction = TearConfettiBurst.unitFraction(from: hash, offset: 0)
        let angleJitter = (TearConfettiBurst.unitFraction(from: hash, offset: 7) - 0.5) * 0.6
        let distanceJitter = TearConfettiBurst.unitFraction(from: hash, offset: 13)
        let rotationOffset = TearConfettiBurst.unitFraction(from: hash, offset: 19)
        let sizeJitter = TearConfettiBurst.unitFraction(from: hash, offset: 23)

        let originX = width * CGFloat(lateralFraction)
        let goesUp = index % 2 == 0
        // Half the particles spray up, half down — paper fibers torn from both sides of the rip.
        let baseAngle: Double = goesUp ? -.pi / 2 : .pi / 2
        let angle = baseAngle + angleJitter
        let distance: CGFloat = 70 + CGFloat(distanceJitter) * 70
        let travelled = CGFloat(progress) * distance
        let dx = CGFloat(cos(angle)) * travelled
        let dy = CGFloat(sin(angle)) * travelled

        let particleWidth: CGFloat = 5 + CGFloat(sizeJitter) * 5
        let particleHeight: CGFloat = 3 + CGFloat(sizeJitter) * 2
        let particleColor: Color = (index % 3 == 0) ? WNFTheme.yellow : WNFTheme.bg
        let fade = 1 - progress * progress

        return RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(particleColor)
            .frame(width: particleWidth, height: particleHeight)
            .rotationEffect(.degrees(rotationOffset * 360 + progress * 220))
            .position(x: originX + dx, y: baseY + dy)
            .opacity(fade)
    }

    private static func hash(seed: UInt64, index: UInt64) -> UInt64 {
        // SplitMix64-flavored mix so neighbouring indices produce wildly different bits.
        var z = seed &+ (index &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private static func unitFraction(from hash: UInt64, offset: UInt64) -> Double {
        let shifted = (hash &>> offset) & 0xFFFF
        return Double(shifted) / Double(0xFFFF)
    }
}

// MARK: - Tear Mask

private struct TearMask: Shape {
    enum Side { case top, bottom }

    var tearNormalizedY: CGFloat
    var jitter: [CGFloat]
    var side: Side

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseY = rect.height * tearNormalizedY
        let count = jitter.count

        guard count >= 2 else {
            switch side {
            case .top:
                path.addRect(CGRect(x: 0, y: 0, width: rect.width, height: baseY))
            case .bottom:
                path.addRect(CGRect(x: 0, y: baseY, width: rect.width, height: rect.height - baseY))
            }
            return path
        }

        let stepX = rect.width / CGFloat(count - 1)
        let yAt: (Int) -> CGFloat = { i in
            // Pin both ends to baseY so the tear meets the card edges cleanly.
            let offset = (i == 0 || i == count - 1) ? 0 : jitter[i]
            return baseY + offset
        }

        switch side {
        case .top:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            for i in stride(from: count - 1, through: 0, by: -1) {
                path.addLine(to: CGPoint(x: stepX * CGFloat(i), y: yAt(i)))
            }
            path.closeSubpath()
        case .bottom:
            for i in 0..<count {
                let point = CGPoint(x: stepX * CGFloat(i), y: yAt(i))
                if i == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            path.closeSubpath()
        }

        return path
    }
}

// MARK: - Settlement Share Card

struct DailySettlementShareCard: View {
    var settlement: DailySettlement
    var template: PremiumShareTemplateID
    var displayedAmount: Double?
    var displayedBestMoment: String?
    var hidesSensitiveInfo: Bool
    var showsControls: Bool
    var isPreparingShare: Bool = false
    var onTogglePrivacy: () -> Void = {}
    var onTearBestMoment: (() -> Void)? = nil
    var onShare: () -> Void = {}
    var onDismiss: () -> Void = {}

    private var renderedAmount: Double {
        displayedAmount ?? settlement.earnedToday
    }

    private var renderedBestMoment: String {
        displayedBestMoment ?? settlement.bestMoment
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            cardBody
        }
        .background(templateBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var templateBackground: Color {
        switch template {
        case .classic: WNFTheme.bg
        case .overtimeReceipt: WNFTheme.surfaceSoft
        case .survivalBadge: WNFTheme.coralSoft
        case .quietLedger: Color.white
        }
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
                Text("今日下班战绩")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(WNFTheme.inkSoft)
            }

            Spacer(minLength: 8)

            if showsControls {
                HStack(spacing: 8) {
                    settlementHeaderButton(
                        systemName: hidesSensitiveInfo ? "eye.slash" : "eye",
                        accessibilityLabel: hidesSensitiveInfo ? "显示敏感信息" : "隐藏敏感信息",
                        action: onTogglePrivacy
                    )
                    settlementHeaderButton(
                        systemName: "square.and.arrow.up",
                        accessibilityLabel: isPreparingShare ? "正在生成分享图" : "唤起系统分享",
                        isLoading: isPreparingShare,
                        isDisabled: isPreparingShare,
                        action: onShare
                    )
                    settlementHeaderButton(
                        systemName: "xmark",
                        accessibilityLabel: "退出结算",
                        action: onDismiss
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(template == .quietLedger ? Color.white : WNFTheme.gold)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 0)
                .overlay(
                    Rectangle()
                        .stroke(WNFTheme.muted.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [8, 8]))
                )
                .padding(.horizontal, -18)
                .padding(.top, -14)

            VStack(alignment: .leading, spacing: 8) {
                Text(settlement.headline)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                Text(settlement.subCopy)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            amountPanel

            statsRow

            SettlementQuoteCard(
                iconName: "quote.opening",
                prefix: "今日最佳忍耐时刻：",
                content: renderedBestMoment,
                hint: onTearBestMoment == nil ? nil : "长按可换一句",
                onTear: onTearBestMoment
            )

            cumulativeRow

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

    private var cumulativeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(WNFTheme.gold)
            Text("累积窝囊费")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(WNFTheme.inkSoft)
            Spacer(minLength: 12)
            Text(cumulativeText)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(WNFTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WNFTheme.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WNFTheme.hairline, lineWidth: 0.5)
        )
    }

    private var cumulativeText: String {
        if hidesSensitiveInfo { return "¥•••.••" }
        return WNFFormat.moneyDecimal(settlement.cumulativeEarned, privacy: false)
    }

    private var amountPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("今日窝囊费")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)
                Spacer(minLength: 12)
                sentimentBadge
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.yellow)
                Group {
                    if hidesSensitiveInfo {
                        Text("•••.••")
                            .foregroundStyle(WNFTheme.muted)
                    } else {
                        Text(formattedAmount)
                            .foregroundStyle(WNFTheme.ink)
                            .contentTransition(.numericText(value: renderedAmount))
                            .animation(.easeOut(duration: 0.25), value: renderedAmount)
                    }
                }
                .font(.system(size: 44, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(WNFTheme.muted.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .padding(6)
        )
    }

    private var formattedAmount: String {
        String(format: "%.2f", renderedAmount)
    }

    private var sentimentBadge: some View {
        HStack(spacing: 5) {
            Text(settlement.sentiment.emoji)
                .font(.system(size: 13))
            Text(settlement.sentiment.label)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(WNFTheme.ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(WNFTheme.surfaceSoft, in: Capsule())
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            settlementStatTile(
                title: "忍耐指数",
                value: settlement.sentiment.stars,
                outOf: settlement.sentiment.maxStars
            )
            settlementStatTile(
                title: "已忍时长",
                primary: durationPrimary,
                secondary: durationSecondary
            )
            settlementStatTile(
                title: "连续打工",
                primary: settlement.streakDays > 0 ? "\(settlement.streakDays)" : "—",
                secondary: settlement.streakDays > 0 ? "天" : "暂无"
            )
        }
    }

    private var durationPrimary: String {
        if hidesSensitiveInfo {
            return "••"
        }
        let h = settlement.elapsedPaidMinutes / 60
        if h > 0 { return "\(h)" }
        return "\(settlement.elapsedPaidMinutes)"
    }

    private var durationSecondary: String {
        if hidesSensitiveInfo {
            return "h••min"
        }
        let h = settlement.elapsedPaidMinutes / 60
        let m = settlement.elapsedPaidMinutes % 60
        if h > 0 {
            return m > 0 ? "h \(m)min" : "h"
        }
        return "min"
    }

    private func settlementStatTile(
        title: String,
        primary: String,
        secondary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(WNFTheme.muted)
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(primary)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                Text(secondary)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(WNFTheme.muted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WNFTheme.hairline, lineWidth: 0.5)
        )
    }

    private func settlementStatTile(
        title: String,
        value: Int,
        outOf max: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(WNFTheme.muted)
                .tracking(1)
            HStack(spacing: 2) {
                ForEach(0..<max, id: \.self) { index in
                    Image(systemName: index < value ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(index < value ? WNFTheme.yellow : WNFTheme.muted.opacity(0.5))
                }
            }
            .padding(.top, 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WNFTheme.hairline, lineWidth: 0.5)
        )
    }

    private func settlementHeaderButton(
        systemName: String,
        accessibilityLabel: String,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
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
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Quote Card (best moment)

private struct SettlementQuoteCard: View {
    var iconName: String
    var prefix: String?
    var content: String
    var hint: String?
    var onTear: (() -> Void)?

    @State private var pressFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(WNFTheme.muted)
                    .padding(.top, 2)
                Text(combined)
                    // id-driven transition: when content changes, the old text fades + slides out
                    // and the new one slides in. The parent wraps the swap in withAnimation.
                    .id(combined)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.86, anchor: .leading))
                                .combined(with: .offset(y: 12))
                        )
                    )
                Spacer(minLength: 0)
            }

            if let hint, onTear != nil {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 9, weight: .heavy))
                    Text(hint)
                        .font(.system(size: 10, weight: .heavy))
                }
                .foregroundStyle(WNFTheme.muted.opacity(0.7))
                .padding(.leading, 19)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WNFTheme.hairline, lineWidth: 0.5)
        )
        .scaleEffect(pressFeedback ? 0.97 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: pressFeedback)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4) {
            handleTear()
        } onPressingChanged: { isPressing in
            // visible feedback during the long-press hold so the user knows the gesture registered
            pressFeedback = isPressing && onTear != nil
        }
        .accessibilityHint(onTear == nil ? "" : "长按可以换一句")
    }

    private var combined: String {
        if let prefix { return "\(prefix)\(content)" }
        return content
    }

    private func handleTear() {
        guard let onTear else { return }
        onTear()
    }
}

// MARK: - CTA Button (Home entry)

struct ClockOutCTA: View {
    var status: WorkStatus
    var isSettled: Bool = false
    var action: () -> Void

    private var title: String {
        if isSettled { return "今日已下班 · 再看一眼" }
        switch status {
        case .before, .morning, .afternoon, .lunch: return "查看今天挣多少"
        case .done: return "下班！"
        }
    }

    private var subtitle: String {
        if isSettled { return "今日窝囊费已入账，剩下都是你的时间" }
        switch status {
        case .before: return "今天的窝囊费还没开张"
        case .morning: return "已经熬过早上的两小时最值钱"
        case .lunch: return "午休回血中，要不要看看今天挣多少"
        case .afternoon: return "再忍忍，也可以提前看看战绩"
        case .done: return "今日通关，看看今天的窝囊费"
        }
    }

    private var iconName: String {
        isSettled ? "checkmark.circle.fill" : "tray.and.arrow.down.fill"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(WNFTheme.ink)
                        .frame(width: 36, height: 36)
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(WNFTheme.yellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(WNFTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(WNFTheme.inkSoft)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WNFTheme.ink.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(WNFTheme.yellow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: WNFTheme.yellow.opacity(0.4), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
