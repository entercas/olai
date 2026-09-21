import Foundation
import OlaiCore
import SwiftData
import WebKit

/// Serves the editor and its attachments from one custom scheme.
///
/// The page could be loaded with `loadFileURL`, but a `file://` origin is not allowed to
/// load a custom scheme, so attachment images never resolve. Serving the page from
/// `olai://editor/index.html` and images from `olai://editor/attachment/<uuid>` puts
/// both on the same origin. Documents still store `attachment://<uuid>`, as the spec
/// requires; the editor maps between the two when it renders and parses.
final class OlaiSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "olai"
    static let pageURL = URL(string: "olai://editor/index.html")!
    static let attachmentPath = "/attachment/"

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }

        let payload: (data: Data, mime: String)? =
            url.path.hasPrefix(Self.attachmentPath) ? attachmentPayload(for: url) : pagePayload()

        guard let payload else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: payload.mime,
            expectedContentLength: payload.data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(payload.data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func pagePayload() -> (Data, String)? {
        guard
            let url = Bundle.main.url(forResource: "editor", withExtension: "html"),
            let data = try? Data(contentsOf: url)
        else {
            NSLog("Olai: editor.html is missing from the bundle")
            return nil
        }
        return (data, "text/html")
    }

    private func attachmentPayload(for url: URL) -> (Data, String)? {
        let identifier = String(url.path.dropFirst(Self.attachmentPath.count))
        guard
            let id = UUID(uuidString: identifier),
            let attachment = attachment(id: id),
            let data = attachment.data
        else { return nil }

        // Narrowed again here, not just when storing: an attachment can reach this
        // device over CloudKit without ever passing through the paste path.
        return (data, Attachment.safeMimeType(attachment.mimeType))
    }

    /// Runs on whichever thread WebKit calls on, against a context created there: the
    /// scheme task is not sendable, so it cannot be handed to the main actor.
    private func attachment(id: UUID) -> Attachment? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
