import SwiftUI
import WebKit

enum LegalDocument: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Terms of Use"
        case .privacy: "Privacy Policy"
        }
    }

    var remoteURL: URL {
        switch self {
        case .terms: URL(string: "https://wonangfei.app/terms")!
        case .privacy: URL(string: "https://wonangfei.app/privacy")!
        }
    }

    var localResourceName: String {
        switch self {
        case .terms: "terms"
        case .privacy: "privacy"
        }
    }
}

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var premium: PremiumEntitlementStore
    @EnvironmentObject private var paywall: PremiumPaywallController
    @State private var legalDocument: LegalDocument?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    benefits
                    statusPanel
                    actions
                    legalLinks
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(WNFTheme.bg)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        paywall.dismiss()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(WNFTheme.ink)
                            .frame(width: 36, height: 36)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .sheet(item: $legalDocument) { document in
                LegalDocumentView(document: document)
            }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                YenBadge(size: 24)
                Text("窝囊费王牌打工人")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                    .minimumScaleFactor(0.8)
            }
            Text("一次买断，解锁小组件、主题、分享模板和历史导出。")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WNFTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
    }

    private var benefits: some View {
        VStack(spacing: 10) {
            ForEach(PremiumFeature.allCases) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(WNFTheme.ink)
                        .frame(width: 38, height: 38)
                        .background(WNFTheme.yellow, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(feature.title)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(WNFTheme.ink)
                        Text(feature.subtitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WNFTheme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    @ViewBuilder
    private var statusPanel: some View {
        switch premium.productState {
        case .unavailable:
            PaywallStatusPanel(symbol: "clock.badge.exclamationmark", title: "王牌打工人 · 即将开放", message: "当前地区暂时无法购买。免费功能可以继续使用。")
        case .failed(let message):
            PaywallStatusPanel(symbol: "wifi.exclamationmark", title: "商品加载失败", message: message)
        default:
            if let message = premium.statusMessage {
                PaywallStatusPanel(symbol: "info.circle", title: "提示", message: message)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await premium.purchaseLifetime() }
            } label: {
                HStack {
                    if premium.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "crown.fill")
                    }
                    Text(primaryActionTitle)
                        .font(.system(size: 16, weight: .black))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(primaryActionDisabled ? WNFTheme.muted : WNFTheme.ink, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(primaryActionDisabled)
            .accessibilityLabel(primaryActionTitle)

            Button {
                Task { await premium.restorePurchases() }
            } label: {
                HStack {
                    if premium.isRestoring {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Restore Purchases")
                        .font(.system(size: 14, weight: .black))
                }
                .foregroundStyle(WNFTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(WNFTheme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(premium.isRestoring)
            .accessibilityLabel("Restore Purchases")
        }
    }

    private var primaryActionTitle: String {
        if premium.isPremiumUnlocked { return "王牌打工人 · 已解锁" }
        if !premium.canMakePayments { return "App 内购买受限" }
        switch premium.productState {
        case .loading, .idle:
            return "加载中..."
        case .unavailable:
            return "王牌打工人 · 即将开放"
        case .failed:
            return "重试加载商品"
        case .loaded:
            return "\(premium.displayPrice) 解锁"
        }
    }

    private var primaryActionDisabled: Bool {
        premium.isPremiumUnlocked || premium.isPurchasing || !premium.canMakePayments || {
            if case .unavailable = premium.productState { return true }
            return false
        }()
    }

    private var legalLinks: some View {
        HStack(spacing: 14) {
            Button("Terms of Use") {
                legalDocument = .terms
            }
            Button("Privacy Policy") {
                legalDocument = .privacy
            }
        }
        .font(.system(size: 12, weight: .heavy))
        .foregroundStyle(WNFTheme.ink)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
    }
}

private struct PaywallStatusPanel: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(WNFTheme.coral)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WNFTheme.ink)
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WNFTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WNFTheme.coralSoft.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PremiumStatusPill: View {
    var isUnlocked: Bool
    var isPending: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isUnlocked ? "checkmark.seal.fill" : isPending ? "clock.fill" : "lock.fill")
            Text(isUnlocked ? "已解锁" : isPending ? "等待批准" : "未解锁")
        }
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(isUnlocked ? WNFTheme.ink : Color.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(isUnlocked ? WNFTheme.yellow : isPending ? WNFTheme.coral : WNFTheme.ink, in: Capsule())
    }
}

struct PremiumFeatureLockButton: View {
    var title: String
    var isUnlocked: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isUnlocked ? "checkmark" : "lock")
                Text(title)
            }
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(isUnlocked ? WNFTheme.ink : Color.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(isUnlocked ? WNFTheme.yellow : WNFTheme.ink, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    var document: LegalDocument

    var body: some View {
        NavigationStack {
            LegalWebView(document: document)
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct LegalWebView: UIViewRepresentable {
    var document: LegalDocument

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: document.remoteURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        var document: LegalDocument
        private var didLoadFallback = false

        init(document: LegalDocument) {
            self.document = document
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            loadFallback(into: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            loadFallback(into: webView)
        }

        private func loadFallback(into webView: WKWebView) {
            guard !didLoadFallback else { return }
            didLoadFallback = true
            if let url = Bundle.main.url(forResource: document.localResourceName, withExtension: "html") {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.loadHTMLString("<html><body><h1>\(document.title)</h1><p>Legal document unavailable offline.</p></body></html>", baseURL: nil)
            }
        }
    }
}
