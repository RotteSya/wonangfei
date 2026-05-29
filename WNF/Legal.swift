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

    /// Chinese display name used by the offline fallback page; the app is
    /// Chinese-only, so the only state the user can reach offline must not be
    /// English (E-7).
    var localizedTitle: String {
        switch self {
        case .terms: "使用条款"
        case .privacy: "隐私政策"
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
        /// Custom scheme tapped by the "重新加载" button in the offline fallback page.
        /// Intercepted below so the synthetic page can ask us to retry the remote load.
        private static let retryScheme = "wnf-legal-retry"

        var document: LegalDocument
        private var didLoadFallback = false

        init(document: LegalDocument) {
            self.document = document
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.request.url?.scheme == Self.retryScheme {
                decisionHandler(.cancel)
                // Re-arm the fallback so a second failure shows the page again.
                didLoadFallback = false
                webView.load(URLRequest(url: document.remoteURL))
                return
            }
            decisionHandler(.allow)
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
                webView.loadHTMLString(Self.offlineFallbackHTML(for: document), baseURL: nil)
            }
        }

        /// Brand-tinted, Chinese offline page shown only if the bundled HTML resource
        /// is also missing. Colors mirror `WNFTheme` (bg / ink / yellow / muted) so the
        /// deepest fallback still reads as the same app. The retry button navigates to
        /// the custom `retryScheme`, which `decidePolicyFor` turns into a remote reload.
        private static func offlineFallbackHTML(for document: LegalDocument) -> String {
            """
            <!doctype html>
            <html lang="zh-Hans">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <style>
                :root { color-scheme: light; }
                body {
                  font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
                  margin: 0; min-height: 100vh; box-sizing: border-box;
                  display: flex; flex-direction: column; align-items: center; justify-content: center;
                  text-align: center; padding: 32px;
                  background: #FFF6E5; color: #0D0D0D;
                }
                h1 { font-size: 22px; font-weight: 800; margin: 0 0 12px; }
                p { font-size: 15px; line-height: 1.6; color: #9A9389; margin: 0 0 28px; max-width: 30ch; }
                a.retry {
                  display: inline-block; text-decoration: none;
                  font-size: 15px; font-weight: 800; color: #0D0D0D;
                  background: #FFC83D; border-radius: 999px; padding: 13px 30px;
                }
              </style>
            </head>
            <body>
              <h1>\(document.localizedTitle)</h1>
              <p>暂时无法加载\(document.localizedTitle)，请检查网络后重试。</p>
              <a class="retry" href="\(retryScheme)://reload">重新加载</a>
            </body>
            </html>
            """
        }
    }
}
