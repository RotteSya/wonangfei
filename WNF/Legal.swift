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
