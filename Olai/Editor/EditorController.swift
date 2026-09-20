import Foundation
import OlaiCore
import Observation
import SwiftData
import WebKit

/// Which marks and blocks are active where the caret sits, mirrored from the editor so
/// the SwiftUI toolbar can draw itself.
struct EditorState: Equatable, Decodable {
    struct Task: Equatable, Decodable {
        var active = false
        var text = ""
        var reminderID: String?
        var due: String?
    }

    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var highlight = false
    var code = false
    var h1 = false
    var h2 = false
    var h3 = false
    var bulletList = false
    var orderedList = false
    var taskList = false
    var blockquote = false
    var canUndo = false
    var canRedo = false
    var task = Task()
}

/// Owns one web view's side of the bridge: sends commands into the editor, and turns
/// the messages coming back into model changes.
///
/// Message names match the spec's bridge, with two additions the toolbar needs:
/// `stateChanged` coming back, and `command` going out.
@MainActor
@Observable
final class EditorController: NSObject {
    private(set) var state = EditorState()
    private(set) var isReady = false

    /// Set by the host view before the editor loads.
    var onDocumentChanged: ((Data, String) -> Void)?
    var onImagePasted: ((Data, String, String) -> UUID?)?

    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var pendingDocument: (json: Data, readOnly: Bool)?
    @ObservationIgnored private var pendingDark: Bool?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    // MARK: Sending

    func setDocument(json: Data?, readOnly: Bool = false) {
        let document = json ?? TipTapDocument.emptyDocument
        guard isReady else {
            pendingDocument = (document, readOnly)
            return
        }
        let text = String(decoding: document, as: UTF8.self)
        evaluate("window.olai.setDocument({json: \(text), readOnly: \(readOnly)})")
    }

    func applyTheme(dark: Bool) {
        guard isReady else {
            pendingDark = dark
            return
        }
        evaluate("window.olai.applyTheme({dark: \(dark)})")
    }

    func run(_ command: String) {
        evaluate("window.olai.command({name: '\(command)'})")
    }

    func insertText(_ text: String) {
        guard let encoded = jsString(text) else { return }
        evaluate("window.olai.insertText({text: \(encoded)})")
    }

    func insertImage(id: UUID) {
        evaluate("window.olai.insertImage({id: '\(id.uuidString)'})")
    }

    func setTaskReminder(id: String?, due: String?) {
        let reminder = id.flatMap(jsString) ?? "null"
        let dueText = due.flatMap(jsString) ?? "null"
        evaluate("window.olai.setTaskReminder({reminderID: \(reminder), due: \(dueText)})")
    }

    /// Writes out any change still sitting in the editor's debounce window.
    func flush() {
        run("flush")
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script) { _, error in
            if let error {
                NSLog("Olai editor: \(script.prefix(60))… failed: \(error)")
            }
        }
    }

    /// JSON-encodes a Swift string into a JavaScript string literal, quotes included.
    private func jsString(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Receiving

extension EditorController: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // WebKit delivers script messages on the main thread.
        MainActor.assumeIsolated {
            guard
                let body = message.body as? [String: Any],
                let name = body["name"] as? String
            else { return }
            let payload = body["payload"] as? [String: Any] ?? [:]
            handle(name: name, payload: payload)
        }
    }

    private func handle(name: String, payload: [String: Any]) {
        switch name {
        case "ready":
            isReady = true
            if let pendingDocument {
                setDocument(json: pendingDocument.json, readOnly: pendingDocument.readOnly)
                self.pendingDocument = nil
            }
            if let pendingDark {
                applyTheme(dark: pendingDark)
                self.pendingDark = nil
            }

        case "documentChanged":
            guard
                let json = payload["json"],
                let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            else { return }
            onDocumentChanged?(data, payload["plainText"] as? String ?? "")

        case "stateChanged":
            guard
                let data = try? JSONSerialization.data(withJSONObject: payload),
                let decoded = try? JSONDecoder().decode(EditorState.self, from: data)
            else { return }
            state = decoded

        case "requestImagePaste":
            guard
                let base64 = payload["base64"] as? String,
                let data = Data(base64Encoded: base64),
                let id = onImagePasted?(
                    data,
                    payload["mime"] as? String ?? "image/png",
                    payload["name"] as? String ?? "pasted"
                )
            else { return }
            insertImage(id: id)

        case "slashCommand":
            break

        default:
            break
        }
    }
}
