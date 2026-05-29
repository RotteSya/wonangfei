import SwiftUI
import UIKit

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

/// Tunable knobs for the Dynamic-Island genie emergence. Defaults are the
/// shipping values; the DEBUG tuner mutates a copy live so the animation can be
/// dialled in without rebuilding.
struct GenieParams: Equatable {
    /// Emergence duration (seconds).
    var duration: Double = 0.62
    /// Width of the island "slot" the card necks into (points).
    var neckWidth: CGFloat = 164
    /// Funnel throat length as a fraction of the card (0…1): how much of the card
    /// tapers into the neck vs. sits at full width.
    var neckLen: CGFloat = 0.70
    /// Progress (0…1) at which the neck pinch starts releasing toward the full card.
    var unpinchStart: CGFloat = 0.78

    static let `default` = GenieParams()
}

struct ShareCardBackdrop: View {
    var isPresented: Bool
    var onDismiss: () -> Void

    var body: some View {
        Color(red: 0.27, green: 0.25, blue: 0.21)
            .opacity(isPresented ? 0.46 : 0)
            .ignoresSafeArea(.container, edges: .all)
            .contentShape(Rectangle())
            .allowsHitTesting(isPresented)
            .onTapGesture(perform: onDismiss)
            .animation(.easeInOut(duration: 0.18), value: isPresented)
    }
}

/// The share card "unfurls" out of the Dynamic Island: a black capsule at the
/// island position stretches open, the card pours out of its lower edge while a
/// rounded-rect reveal window grows (height first, then width), and finally the
/// card detaches downward as the capsule snaps back to its compact shape. On a
/// real Dynamic Island device the drawn capsule sits exactly over the hardware
/// island, so the card genuinely appears to be born from it; on notch/older
/// devices we skip the capsule and unfurl from the top edge instead.
///
/// One curve drives everything — the design system's only ease,
/// cubic-bezier(.32,.72,0,1). All geometry is a pure function of `reveal`
/// (0 = furled into the island, 1 = resting card), so dismissal reverses for free.
struct ShareCardOverlay: View {
    var isPresented: Bool
    var day: WageDay
    var copy: ShareCardCopy
    @Binding var hidesSensitiveInfo: Bool
    var isPreparingShare: Bool
    var params: GenieParams = .default
    /// When non-nil, the emergence is pinned to this progress (DEBUG scrub/tuner)
    /// instead of the internal animated `reveal`.
    var scrub: CGFloat? = nil
    var onShare: () -> Void
    var onDismiss: () -> Void

    @State private var reveal: CGFloat = 0
    @State private var cardSize: CGSize = .zero

    private var unfurlIn: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: params.duration) }
    private static let unfurlOut = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.34)

    private var displayReveal: CGFloat { scrub ?? reveal }
    private var isActive: Bool { isPresented || reveal > 0.001 || scrub != nil }

    var body: some View {
        GeometryReader { proxy in
            let island = IslandMetrics(topInset: proxy.safeAreaInsets.top)
            let centerX = proxy.size.width / 2
            let cardWidth = min(proxy.size.width - 52, 340)
            let p = displayReveal

            ZStack(alignment: .topLeading) {
                if isActive {
                    unfurlingCard(p: p, island: island, centerX: centerX, cardWidth: cardWidth)
                    if island.hasIsland {
                        islandCapsule(p: p, island: island, centerX: centerX)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea(.container, edges: .all)
        .allowsHitTesting(isPresented)
        .onChange(of: isPresented) { _, presented in
            if presented {
                // Insert the card sucked into the slot (reveal 0) THIS runloop, then
                // animate out NEXT runloop — otherwise the freshly-inserted view has
                // no "from" state and the genie snaps straight to the resting card.
                reveal = 0
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                DispatchQueue.main.async {
                    withAnimation(unfurlIn) { reveal = 1 }
                }
            } else {
                withAnimation(Self.unfurlOut) { reveal = 0 }
            }
        }
    }

    private func unfurlingCard(p: CGFloat, island: IslandMetrics, centerX: CGFloat, cardWidth: CGFloat) -> some View {
        let cardH = max(cardSize.height, 1)
        let neckHalf = params.neckWidth / 2
        // The box is pinned flush to the island's lower lip; the genie warp does
        // all the motion within it (and is the identity at rest, so the resting
        // card is crisp and its buttons hit-test).
        let topY = island.compactBottomY

        return WonangfeiShareCard(
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
        .frame(width: cardWidth)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ShareCardSizeKey.self, value: geo.size)
            }
        )
        // Animatable wrapper: a Shader uniform is NOT animatable, so passing the
        // distortion progress directly would snap to the final value (no warp).
        // Driving it through `animatableData` re-evaluates the effect every frame.
        .modifier(GenieEmergence(
            progress: p,
            size: CGSize(width: cardWidth, height: cardH),
            neckHalf: neckHalf,
            neckLen: params.neckLen,
            unpinchStart: params.unpinchStart
        ))
        .position(x: centerX, y: topY + cardH / 2)
        .onPreferenceChange(ShareCardSizeKey.self) { cardSize = $0 }
    }

    private func islandCapsule(p: CGFloat, island: IslandMetrics, centerX: CGFloat) -> some View {
        // The capsule's size is non-monotonic in progress (open a little, then
        // snap back), which `withAnimation`'s endpoint interpolation would skip —
        // so its frame is driven per-frame through an animatable modifier too.
        Capsule(style: .continuous)
            .fill(.black)
            .modifier(IslandCapsuleStretch(
                progress: p,
                compact: island.compactSize,
                expanded: CGSize(width: params.neckWidth, height: island.expandedSize.height),
                topY: island.topY,
                centerX: centerX
            ))
            .allowsHitTesting(false)
    }
}

/// Geometry of the Dynamic Island as the source/anchor of the unfurl. Values are
/// measured in points from the physical top-left of the screen (the overlay
/// ignores safe area, so the GeometryReader origin is the true top edge).
private struct IslandMetrics {
    var hasIsland: Bool
    var topY: CGFloat
    var compactSize: CGSize
    var expandedSize: CGSize
    var detachGap: CGFloat

    init(topInset: CGFloat) {
        // Dynamic Island devices report a ~59pt top inset; notch devices ~44–50pt.
        let island = topInset >= 51
        hasIsland = island
        if island {
            topY = 11
            compactSize = CGSize(width: 126, height: 37.33)
            expandedSize = CGSize(width: 164, height: 41)   // opens just a little
            detachGap = 18
        } else {
            topY = max(8, topInset * 0.4)
            compactSize = CGSize(width: 96, height: 30)
            expandedSize = CGSize(width: 150, height: 34)
            detachGap = 14
        }
    }

    var compactBottomY: CGFloat { topY + compactSize.height }
}

private struct ShareCardSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

/// Hermite smoothstep — eases a sub-range of the master `reveal` progress so
/// individual properties (width, detach, corner) can lead or trail the reveal.
private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// The funnel silhouette the genie-warped card is clipped to — pinched to the
/// island neck at the top, flaring to full width below, occupying the top
/// `progress` fraction of the card. Kept in lock-step with the `genie` shader's
/// `halfWidth`/`vFront` so the warp and the clip share one outline. At progress
/// 1 it's the full card rectangle (identity), matching the shader.
private struct GenieFunnelShape: Shape {
    var progress: CGFloat
    var neckHalf: CGFloat
    var neckLen: CGFloat = 0.70
    var unpinchStart: CGFloat = 0.78

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let p = min(max(progress, 0), 1)
        if p >= 0.999 {
            path.addRect(rect)
            return path
        }

        let w = rect.width
        let h = rect.height
        let center = rect.midX
        let fullHalf = w / 2
        let vFront = max(p, 0.001)
        let steps = 28
        let unpinch = smoothstep(unpinchStart, 1.0, p)

        func halfWidth(atSourceV s: CGFloat) -> CGFloat {
            let funnel = lerp(neckHalf, fullHalf, smoothstep(0, neckLen, s))
            return max(lerp(funnel, fullHalf, unpinch), 1)
        }

        var leftEdge: [CGPoint] = []
        for i in 0...steps {
            let v = vFront * CGFloat(i) / CGFloat(steps)   // output v in [0, vFront]
            let hw = halfWidth(atSourceV: v / vFront)
            let y = v * h
            if i == 0 {
                path.move(to: CGPoint(x: center + hw, y: y))
            } else {
                path.addLine(to: CGPoint(x: center + hw, y: y))
            }
            leftEdge.append(CGPoint(x: center - hw, y: y))
        }
        for point in leftEdge.reversed() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// Drives the genie distortion per-frame. A `Shader` argument is not animatable,
/// so the distortion must be reapplied for each interpolated `progress` — which a
/// custom `Animatable` modifier does (SwiftUI steps `animatableData` and re-runs
/// `body` every frame). The funnel mask and shadow ride the same progress so they
/// stay locked to the warp.
private struct GenieEmergence: ViewModifier, Animatable {
    var progress: CGFloat
    var size: CGSize
    var neckHalf: CGFloat
    var neckLen: CGFloat
    var unpinchStart: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let shadowP = smoothstep(0.2, 0.85, progress)
        return content
            .distortionEffect(
                ShaderLibrary.genie(
                    .float2(size.width, size.height),
                    .float(progress),
                    .float(neckHalf),
                    .float(size.width / 2),
                    .float(neckLen),
                    .float(unpinchStart)
                ),
                maxSampleOffset: size
            )
            .mask(GenieFunnelShape(progress: progress, neckHalf: neckHalf, neckLen: neckLen, unpinchStart: unpinchStart))
            .shadow(color: .black.opacity(0.22 * shadowP), radius: 22, y: 14)
    }
}

/// Per-frame stretch of the faux Dynamic Island capsule. Its size rises then
/// falls across the emergence, so it must be recomputed every frame rather than
/// interpolated between endpoints.
private struct IslandCapsuleStretch: ViewModifier, Animatable {
    var progress: CGFloat
    var compact: CGSize
    var expanded: CGSize
    var topY: CGFloat
    var centerX: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let rise = min(progress / 0.18, 1)
        let fall = smoothstep(0.6, 1.0, progress)
        let stretch = rise * (1 - fall)
        let w = lerp(compact.width, expanded.width, stretch)
        let h = lerp(compact.height, expanded.height, stretch)
        return content
            .frame(width: w, height: h)
            .position(x: centerX, y: topY + h / 2)
    }
}

#if DEBUG
/// DEBUG-only live tuner for the genie emergence. Scrub the progress by hand or
/// hit Play, and drag the sliders to dial in duration / neck width / throat /
/// release point — all update the warp in real time. Never shipped.
struct GenieTunerView: View {
    var day: WageDay
    var onClose: () -> Void

    @State private var params = GenieParams.default
    @State private var scrub: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.28).ignoresSafeArea()

            ShareCardOverlay(
                isPresented: true,
                day: day,
                copy: .default,
                hidesSensitiveInfo: .constant(false),
                isPreparingShare: false,
                params: params,
                scrub: scrub,
                onShare: {},
                onDismiss: {}
            )
            .allowsHitTesting(false)

            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Genie 调参").font(.system(size: 15, weight: .bold))
                Spacer()
                Button("播放") { play() }.buttonStyle(.borderedProminent)
                Button("重置") { withAnimation { params = .default; scrub = 1 } }
                Button("关闭", action: onClose)
            }
            .controlSize(.small)

            sliderRow("进度", $scrub, 0...1)
            sliderRow("时长 s", durationBinding, 0.2...1.5)
            sliderRow("颈宽 pt", $params.neckWidth, 80...340, "%.0f")
            sliderRow("喉长", $params.neckLen, 0.1...1.0)
            sliderRow("松弛点", $params.unpinchStart, 0.4...0.98)

            Text(String(format: "duration %.2f · neckWidth %.0f · neckLen %.2f · unpinchStart %.2f",
                        params.duration, params.neckWidth, params.neckLen, params.unpinchStart))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var durationBinding: Binding<CGFloat> {
        Binding(get: { CGFloat(params.duration) }, set: { params.duration = Double($0) })
    }

    private func sliderRow(_ label: String, _ value: Binding<CGFloat>, _ range: ClosedRange<Double>, _ fmt: String = "%.2f") -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12, weight: .medium)).frame(width: 56, alignment: .leading)
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = CGFloat($0) }), in: range)
            Text(String(format: fmt, value.wrappedValue)).font(.system(size: 12, design: .monospaced)).frame(width: 46, alignment: .trailing)
        }
    }

    private func play() {
        scrub = 0
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: params.duration)) {
                scrub = 1
            }
        }
    }
}
#endif

struct WonangfeiShareCard: View {
    var day: WageDay
    var copy: ShareCardCopy = .default
    var hidesSensitiveInfo: Bool
    var showsControls: Bool
    var isPreparingShare: Bool = false
    var onTogglePrivacy: () -> Void
    var onShare: () -> Void
    var onDismiss: () -> Void

    private var statusPresentation: WorkStatusPresentation {
        WorkStatusPresentation(status: day.status)
    }

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

                Image(statusPresentation.mascotAssetName)
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
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> ActivityPresenterViewController {
        let controller = ActivityPresenterViewController()
        controller.onDismiss = { context.coordinator.dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: ActivityPresenterViewController, context: Context) {
        uiViewController.activityItems = activityItems
        uiViewController.onDismiss = { context.coordinator.dismiss() }

        if isPresented {
            uiViewController.presentActivityIfNeeded()
        } else {
            uiViewController.dismissActivityIfNeeded()
        }
    }

    final class Coordinator {
        private var isPresented: Binding<Bool>

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func dismiss() {
            DispatchQueue.main.async {
                self.isPresented.wrappedValue = false
            }
        }
    }
}

final class ActivityPresenterViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    var activityItems: [Any] = []
    var onDismiss: (() -> Void)?

    private weak var activityController: UIActivityViewController?
    private var shouldPresentWhenVisible = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if shouldPresentWhenVisible {
            presentActivityIfNeeded()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if let activityController {
            configurePopover(for: activityController)
        }
    }

    @MainActor
    func presentActivityIfNeeded() {
        guard activityController == nil else {
            if let activityController {
                configurePopover(for: activityController)
            }
            return
        }

        guard view.window != nil else {
            shouldPresentWhenVisible = true
            return
        }

        guard !activityItems.isEmpty else {
            finishActivity()
            return
        }

        shouldPresentWhenVisible = false

        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.presentationController?.delegate = self
        controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.finishActivity()
        }
        configurePopover(for: controller)

        activityController = controller
        present(controller, animated: true)
    }

    @MainActor
    func dismissActivityIfNeeded() {
        shouldPresentWhenVisible = false

        guard let activityController else { return }
        self.activityController = nil
        activityController.dismiss(animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === activityController else { return }
        finishActivity()
    }

    private func configurePopover(for controller: UIActivityViewController) {
        guard let popover = controller.popoverPresentationController else { return }

        popover.sourceView = view
        popover.sourceRect = popoverSourceRect
        popover.permittedArrowDirections = []
    }

    private var popoverSourceRect: CGRect {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        return CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
    }

    private func finishActivity() {
        shouldPresentWhenVisible = false
        activityController = nil
        onDismiss?()
    }
}
