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

/// Loads the bundled HTML immediately. Public / ASC copies live at
/// `docs/*.html` on GitHub Pages and must stay byte-identical with
/// `WNF/Legal/*.html`. Do not restore a remote-first request —
/// `wonangfei.app` does not resolve, and the wait is just a timeout.
private struct LegalWebView: UIViewRepresentable {
    var document: LegalDocument

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
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
