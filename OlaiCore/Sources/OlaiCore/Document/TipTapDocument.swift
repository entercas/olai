import Foundation

/// Minimal handling of the TipTap/ProseMirror JSON document shape.
///
/// Phase 1 ships a plain-text editor, but the body is still stored as a block document
/// so that the web editor in phase 2 can open existing pages without a migration. Only
/// the two conversions the plain-text editor needs live here; the full block → Markdown
/// converter arrives with the mirror in phase 5.
public enum TipTapDocument {
    public static let emptyDocument: Data = document(fromPlainText: "")

    /// Wraps plain text in a `doc` of paragraphs, one per line. Blank lines become empty
    /// paragraphs so the round trip preserves them.
    public static func document(fromPlainText text: String) -> Data {
        let paragraphs: [[String: Any]] = text
            .components(separatedBy: .newlines)
            .map { line in
                var paragraph: [String: Any] = ["type": "paragraph"]
                if !line.isEmpty {
                    paragraph["content"] = [["type": "text", "text": line]]
                }
                return paragraph
            }
        let doc: [String: Any] = ["type": "doc", "content": paragraphs]
        guard let data = try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]) else {
            return Data("{\"type\":\"doc\",\"content\":[]}".utf8)
        }
        return data
    }

    /// Flattens a document to plain text: one line per top-level block, concatenating the
    /// `text` of every descendant text node. Returns nil when the data is not a document.
    public static func plainText(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let doc = object as? [String: Any],
            doc["type"] as? String == "doc"
        else { return nil }
        let blocks = doc["content"] as? [[String: Any]] ?? []
        return blocks.map(text(inNode:)).joined(separator: "\n")
    }

    private static func text(inNode node: [String: Any]) -> String {
        if let text = node["text"] as? String { return text }
        let children = node["content"] as? [[String: Any]] ?? []
        return children.map(text(inNode:)).joined()
    }
}
