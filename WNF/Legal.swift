import SwiftUI
import WebKit

enum LegalDocument: String, Identifiable {
    case terms
    case privacy
    case acknowledgements

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Terms of Use"
        case .privacy: "Privacy Policy"
        case .acknowledgements: "字体与开源许可"
        }
    }

    var localResourceName: String {
        switch self {
        case .terms: "terms"
        case .privacy: "privacy"
        case .acknowledgements: "acknowledgements"
        }
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

/// http(s) is cancelled so acknowledgements source links cannot leave the bundled page.
enum LegalWebNavigationPolicy {
    static func allows(_ url: URL?) -> Bool {
        switch url?.scheme?.lowercased() {
        case "http", "https":
            return false
        default:
            return true
        }
    }
}

/// Canonical legal HTML is loaded from the app bundle with no network fallback.
private struct LegalWebView: UIViewRepresentable {
    var document: LegalDocument

    func makeCoordinator() -> LegalWebViewCoordinator {
        LegalWebViewCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        if let url = Bundle.main.url(forResource: document.localResourceName, withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(
                "<html><body><h1>\(document.title)</h1><p>Legal document unavailable.</p></body></html>",
                baseURL: nil
            )
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

private final class LegalWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(LegalWebNavigationPolicy.allows(navigationAction.request.url) ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}
