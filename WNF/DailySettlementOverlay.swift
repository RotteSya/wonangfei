import SwiftUI
import UIKit

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

struct DailySettlementOverlay: View {
    enum Phase: Equatable {
        case prep
        case burst
        case reveal
        case tearing
    }

    var settlement: DailySettlement
    @Binding var hidesSensitiveInfo: Bool
    var isPreparingShare: Bool
    var renderScale: CGFloat = 1
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
            displayedAmount: settlement.earnedToday,
            displayedBestMoment: currentBestMoment.isEmpty ? settlement.bestMoment : currentBestMoment,
            hidesSensitiveInfo: hidesSensitiveInfo,
            showsControls: false
        )
        .frame(width: 340)

        let scale = renderScale > 0 ? renderScale : 1
        let renderer = ImageRenderer(content: snapshotCard)
        renderer.scale = scale

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
