import SwiftData
import SwiftUI
import WebKit

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// Hosts the TipTap editor. Swift owns storage and navigation; the web view owns the
/// document.
struct EditorWebView: PlatformViewRepresentable {
    let controller: EditorController
    let container: ModelContainer

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            OlaiSchemeHandler(container: container),
            forURLScheme: OlaiSchemeHandler.scheme
        )
        configuration.userContentController.add(controller, name: "bridge")
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        #if os(macOS)
        // The page sits on the window's own background rather than web-view white.
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // The document scrolls inside the page, never the web view itself.
        webView.scrollView.bounces = false
        #endif
        webView.allowsLinkPreview = false

        controller.attach(webView)

        webView.load(URLRequest(url: OlaiSchemeHandler.pageURL))
        return webView
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) {}
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {}
    #endif
}
