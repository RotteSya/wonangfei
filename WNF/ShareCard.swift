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

struct ShareCardOverlay: View {
    var day: WageDay
    var copy: ShareCardCopy
    var selectedTemplate: PremiumShareTemplateID
    var canUsePremiumTemplates: Bool
    @Binding var hidesSensitiveInfo: Bool
    var isPreparingShare: Bool
    var onSelectTemplate: (PremiumShareTemplateID) -> Void
    var onLockedTemplate: (PremiumShareTemplateID) -> Void
    var onShare: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            WonangfeiShareCard(
                day: day,
                copy: copy,
                template: selectedTemplate,
                hidesSensitiveInfo: hidesSensitiveInfo,
                showsControls: true,
                isPreparingShare: isPreparingShare,
                canUsePremiumTemplates: canUsePremiumTemplates,
                onTogglePrivacy: {
                    withAnimation(.snappy(duration: 0.18)) {
                        hidesSensitiveInfo.toggle()
                    }
                },
                onSelectTemplate: onSelectTemplate,
                onLockedTemplate: onLockedTemplate,
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
    var template: PremiumShareTemplateID = .classic
    var hidesSensitiveInfo: Bool
    var showsControls: Bool
    var isPreparingShare: Bool = false
    var canUsePremiumTemplates: Bool = false
    var onTogglePrivacy: () -> Void
    var onSelectTemplate: (PremiumShareTemplateID) -> Void = { _ in }
    var onLockedTemplate: (PremiumShareTemplateID) -> Void = { _ in }
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
        .background(templateBackground, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
    }

    private var effectiveCopy: ShareCardCopy {
        switch template {
        case .classic:
            copy
        case .overtimeReceipt:
            ShareCardCopy(title: "今日加班小票，\n老板请查收。", subtitle: "每一分钟都算数，每一分窝囊都入账。")
        case .survivalBadge:
            ShareCardCopy(title: "今天存活认证，\n工资已盖章。", subtitle: "没赢过工作，但也没有白熬。")
        case .quietLedger:
            ShareCardCopy(title: "低调记一笔，\n今天也到账。", subtitle: "数字不大声，但很诚实。")
        }
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
        .background(template == .quietLedger ? Color.white : WNFTheme.gold)
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
                    Text(effectiveCopy.title)
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundStyle(WNFTheme.ink)
                        .lineSpacing(-2)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(effectiveCopy.subtitle)
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

            if showsControls {
                ShareTemplatePicker(
                    selectedTemplate: template,
                    canUsePremiumTemplates: canUsePremiumTemplates,
                    onSelectTemplate: onSelectTemplate,
                    onLockedTemplate: onLockedTemplate
                )
            }

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

private struct ShareTemplatePicker: View {
    var selectedTemplate: PremiumShareTemplateID
    var canUsePremiumTemplates: Bool
    var onSelectTemplate: (PremiumShareTemplateID) -> Void
    var onLockedTemplate: (PremiumShareTemplateID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PremiumShareTemplateID.allCases) { template in
                    let locked = template.isPremium && !canUsePremiumTemplates
                    Button {
                        if locked {
                            onLockedTemplate(template)
                        } else {
                            onSelectTemplate(template)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if locked {
                                Image(systemName: "lock.fill")
                            }
                            Text(template.title)
                        }
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(selectedTemplate == template ? Color.white : WNFTheme.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(selectedTemplate == template ? WNFTheme.ink : Color.white, in: Capsule())
                        .overlay(Capsule().stroke(WNFTheme.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(locked ? "\(template.title)，王牌打工人专属" : template.title)
                }
            }
        }
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
