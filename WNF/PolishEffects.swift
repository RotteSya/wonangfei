import SwiftUI

// Swift drivers for `PolishShaders.metal` plus the small custom interaction
// components shared by the home and records pages: sheen sweeps, the aurora
// backdrop, the liquid-gold progress fill, jelly tab transitions, the elastic
// segmented control, and the coin/ring particle bursts.

// MARK: - Sheen

/// Applies the `sheen` layer shader at a fixed `progress`. Identity (and GPU-off
/// via `isEnabled`) outside (0, 1), so it can stay attached permanently.
struct SheenPass: ViewModifier {
    var progress: CGFloat
    var bandWidth: CGFloat
    var strength: CGFloat

    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.sheen(
                .boundingRect,
                .float(progress),
                .float(bandWidth),
                .float(strength)
            ),
            maxSampleOffset: .zero,
            isEnabled: progress > 0.0001 && progress < 0.9999
        )
    }
}

/// Animatable sheen progress. A `Shader` argument is not animatable on its own
/// (same constraint as `GenieEmergence` in ShareCard.swift), so the sweep is
/// re-applied per interpolated frame through `animatableData`.
struct SheenSweepEffect: ViewModifier, Animatable {
    var progress: CGFloat
    var bandWidth: CGFloat = 0.2
    var strength: CGFloat = 0.4

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.modifier(SheenPass(progress: progress, bandWidth: bandWidth, strength: strength))
    }
}

private struct SheenTriggerModifier<Trigger: Equatable>: ViewModifier {
    var trigger: Trigger
    var duration: Double
    var bandWidth: CGFloat
    var strength: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .modifier(SheenSweepEffect(progress: progress, bandWidth: bandWidth, strength: strength))
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) {
                    progress = 0
                }
                withAnimation(.easeInOut(duration: duration)) {
                    progress = 1
                }
            }
    }
}

/// Periodic ambient sweep: one sheen pass every `period` seconds, lasting
/// `duration`. The `TimelineView` only redraws this subtree, and the shader is
/// `isEnabled == false` during the idle window between sweeps.
struct LoopingSheen: ViewModifier {
    var period: Double = 5.2
    var duration: Double = 1.15
    var bandWidth: CGFloat = 0.16
    var strength: CGFloat = 0.5
    var enabled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            TimelineView(.animation(minimumInterval: 1.0 / 40.0)) { context in
                let cycle = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period)
                let progress = CGFloat(min(max(cycle / duration, 0.0), 1.0))
                content.modifier(SheenPass(progress: progress, bandWidth: bandWidth, strength: strength))
            }
        } else {
            content
        }
    }
}

extension View {
    /// Fires one gold sheen sweep across the view whenever `trigger` changes.
    func sheenSweep(
        on trigger: some Equatable,
        duration: Double = 0.85,
        bandWidth: CGFloat = 0.2,
        strength: CGFloat = 0.4
    ) -> some View {
        modifier(SheenTriggerModifier(trigger: trigger, duration: duration, bandWidth: bandWidth, strength: strength))
    }
}

// MARK: - Aurora backdrop

/// Slow-breathing warm light field over the brand cream background. Static under
/// Reduce Motion. Hit-testing is disabled so it is purely decorative.
struct AuroraBackdrop: View {
    var intensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                auroraRect(time: 120)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    // Wrap to keep Float precision in the shader; the hourly
                    // phase jump is imperceptible at these drift speeds.
                    auroraRect(time: context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 3600))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func auroraRect(time: TimeInterval) -> some View {
        Rectangle()
            .fill(WNFTheme.bg)
            .colorEffect(
                ShaderLibrary.aurora(
                    .boundingRect,
                    .float(time),
                    .float(intensity)
                )
            )
    }
}

// MARK: - Liquid gold fill

/// Capsule filled by the `liquidGold` shader — flowing molten gold for the home
/// progress bar. Falls back to the static brand gradient under Reduce Motion.
struct LiquidGoldCapsule: View {
    var animated = true

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                Capsule()
                    .fill(WNFTheme.yellow)
                    .colorEffect(
                        ShaderLibrary.liquidGold(
                            .boundingRect,
                            .float(context.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 600))
                        )
                    )
            }
        } else {
            Capsule()
                .fill(LinearGradient(colors: [WNFTheme.gold, WNFTheme.yellow], startPoint: .leading, endPoint: .trailing))
        }
    }
}

// MARK: - Tab transitions

/// Incoming page: slides in from `direction` while the `jellyWarp` shader bends
/// the sheet mid-flight (peaks at sin(p·π), settles flat). The warp must stay
/// off for the home tab — SwiftUI shader effects skip UIKit-backed content, so
/// the mascot's AVPlayerLayer would drop out of the warped snapshot.
struct TabSlideIn: ViewModifier, Animatable {
    var progress: CGFloat
    var direction: CGFloat
    var width: CGFloat
    var warpEnabled: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)
        let wobble = sin(p * .pi)
        content
            .offset(x: direction * width * (1 - p))
            .distortionEffect(
                ShaderLibrary.jellyWarp(
                    .boundingRect,
                    .float(-direction * wobble * 0.05)
                ),
                maxSampleOffset: CGSize(width: max(width, 1) * 0.06, height: 0),
                isEnabled: warpEnabled && wobble > 0.002
            )
            .opacity(0.35 + 0.65 * Double(p))
    }
}

/// Outgoing page: iOS-navigation-style parallax — drifts a third of the way,
/// dims, and shrinks slightly under the incoming sheet.
struct TabSlideOut: ViewModifier, Animatable {
    var progress: CGFloat
    var direction: CGFloat
    var width: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)
        content
            .offset(x: -direction * width * 0.34 * p)
            .scaleEffect(1 - 0.035 * p)
            .opacity(1 - 0.6 * Double(p))
    }
}

// MARK: - Elastic segmented control

/// Brand replacement for `Picker(.segmented)`: an ink pill slides between
/// segments with matched geometry, squashes while a finger is down, and tracks
/// a horizontal drag across segments with a selection tick per change.
/// Selection animation is owned by the caller's binding setter so page-level
/// transitions stay in the same transaction as the pill.
struct ElasticSegmentedControl<Item: Identifiable & Equatable>: View {
    var items: [Item]
    @Binding var selection: Item
    var label: (Item) -> String
    var containerFill: Color = WNFTheme.surfaceSoft
    var pillFill: Color = WNFTheme.ink
    var selectedLabelColor: Color = WNFTheme.yellow
    var idleLabelColor: Color = WNFTheme.inkSoft

    @Namespace private var pillNamespace
    @GestureState private var isPressing = false

    var body: some View {
        GeometryReader { proxy in
            let count = max(items.count, 1)
            let slot = proxy.size.width / CGFloat(count)

            HStack(spacing: 0) {
                ForEach(items) { item in
                    segment(for: item)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        let index = min(max(Int(value.location.x / slot), 0), count - 1)
                        let item = items[index]
                        if item != selection {
                            selection = item
                        }
                    }
            )
        }
        .frame(height: 38)
        .background(Capsule().fill(containerFill))
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func segment(for item: Item) -> some View {
        Text(label(item))
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(selection == item ? selectedLabelColor : idleLabelColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if selection == item {
                    Capsule()
                        .fill(pillFill)
                        .matchedGeometryEffect(id: "pill", in: pillNamespace)
                        .padding(3)
                        .scaleEffect(x: isPressing ? 1.05 : 1, y: isPressing ? 0.86 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressing)
                }
            }
            .contentShape(Rectangle())
            .accessibilityLabel(label(item))
            .accessibilityAddTraits(selection == item ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction {
                if item != selection {
                    selection = item
                }
            }
    }
}

// MARK: - Coin pop burst

/// One-shot burst of yen coins + sparkles fanning out over the top semicircle.
/// Spawn by incrementing `trigger`. Pruning follows the HomeCoinDropLayer
/// pattern: a single `.task` loop tied to view lifetime, no orphan timers.
struct CoinPopBurst: View {
    var trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [Particle] = []

    private static let particlesPerBurst = 10
    private static let lifetime: TimeInterval = 1.2

    struct Particle: Identifiable {
        let id = UUID()
        var index: Int
        var seed: Int
        var spawnedAt: Date

        var angle: Double {
            let base = Double.pi + Double.pi * (Double(index) + 0.5) / 10.0
            let jitter = Double((index * 7 + seed * 13) % 9 - 4) * 0.022
            return base + jitter
        }

        var distance: CGFloat { CGFloat(46 + ((index * 5 + seed * 3) % 4) * 16) }
        var size: CGFloat { CGFloat(13 + ((index + seed) % 3) * 4) }
        var delay: Double { Double(index % 5) * 0.016 }
        var spin: Double { (index.isMultiple(of: 2) ? 1.0 : -1.0) * Double(140 + (index % 4) * 40) }
        var isCoin: Bool { index % 3 != 2 }
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                BurstParticleView(particle: particle)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, newValue in
            guard !reduceMotion else { return }
            let now = Date()
            particles.append(contentsOf: (0..<Self.particlesPerBurst).map {
                Particle(index: $0, seed: newValue, spawnedAt: now)
            })
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                let now = Date()
                particles.removeAll { now.timeIntervalSince($0.spawnedAt) >= Self.lifetime }
            }
        }
    }
}

private struct BurstParticleView: View {
    var particle: CoinPopBurst.Particle

    @State private var phase = 0 // 0 waiting → 1 flying → 2 fading

    private var offset: CGSize {
        switch phase {
        case 0:
            return .zero
        case 1:
            return CGSize(
                width: cos(particle.angle) * particle.distance,
                height: sin(particle.angle) * particle.distance
            )
        default:
            return CGSize(
                width: cos(particle.angle) * particle.distance * 1.12,
                height: sin(particle.angle) * particle.distance * 1.12 + 14
            )
        }
    }

    var body: some View {
        Group {
            if particle.isCoin {
                Text("¥")
                    .font(.system(size: particle.size * 0.58, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: particle.size, height: particle.size)
                    .background(
                        RadialGradient(
                            colors: [Color(red: 1, green: 0.92, blue: 0.62), WNFTheme.gold],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: particle.size
                        ),
                        in: Circle()
                    )
            } else {
                Image(systemName: "sparkle")
                    .font(.system(size: particle.size * 0.8, weight: .black))
                    .foregroundStyle(WNFTheme.gold)
            }
        }
        .scaleEffect(phase == 0 ? 0.2 : phase == 1 ? 1 : 0.6)
        .rotationEffect(.degrees(phase == 0 ? 0 : particle.spin))
        .opacity(phase == 2 ? 0 : 1)
        .offset(offset)
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.6).delay(particle.delay)) {
                phase = 1
            } completion: {
                withAnimation(.easeIn(duration: 0.26)) {
                    phase = 2
                }
            }
        }
    }
}

// MARK: - Pulse ring

/// Expanding-and-fading ring, fired by incrementing `trigger`. Used for the
/// progress-bar decile milestones; size it with `.frame` and center it on the
/// point of interest.
struct PulseRing: View {
    var trigger: Int
    var color: Color = WNFTheme.gold

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rings: [RingInstance] = []

    private struct RingInstance: Identifiable {
        let id = UUID()
        var spawnedAt: Date
    }

    var body: some View {
        ZStack {
            ForEach(rings) { _ in
                RingView(color: color)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            rings.append(RingInstance(spawnedAt: Date()))
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                let now = Date()
                rings.removeAll { now.timeIntervalSince($0.spawnedAt) >= 1.0 }
            }
        }
    }

    private struct RingView: View {
        var color: Color
        @State private var expanded = false

        var body: some View {
            Circle()
                .stroke(color, lineWidth: 2)
                .scaleEffect(expanded ? 1 : 0.25)
                .opacity(expanded ? 0 : 0.9)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.7)) {
                        expanded = true
                    }
                }
        }
    }
}
