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

    /// The attachments a document actually references, by id.
    ///
    /// An image node carries `attachment://<uuid>`; anything else -- an external URL,
    /// a malformed source -- is not an attachment of ours and is ignored. Returns an
    /// empty set for data that is not a document, which callers must not read as
    /// "this page references nothing": deleting on that basis would throw away the
    /// attachments of a page whose body failed to parse.
    public static func attachmentIDs(in data: Data) -> Set<UUID>? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let doc = object as? [String: Any],
            doc["type"] as? String == "doc"
        else { return nil }

        var found: Set<UUID> = []
        collectAttachments(in: doc["content"] as? [[String: Any]] ?? [], into: &found)
        return found
    }

    private static func collectAttachments(in nodes: [[String: Any]], into found: inout Set<UUID>) {
        for node in nodes {
            if
                node["type"] as? String == "image",
                let attributes = node["attrs"] as? [String: Any],
                let source = attributes["src"] as? String,
                source.hasPrefix(attachmentPrefix),
                let id = UUID(uuidString: String(source.dropFirst(attachmentPrefix.count)))
            {
                found.insert(id)
            }
            collectAttachments(in: node["content"] as? [[String: Any]] ?? [], into: &found)
        }
    }

    private static let attachmentPrefix = "attachment://"

    /// Inline content runs together; blocks do not. Everything below the top level used
    /// to be joined with nothing between, so a checklist of Milk and Bread read as
    /// "MilkBread" -- in the page list's preview, and to search, which could no longer
    /// find "milk bread".
    private static func text(inNode node: [String: Any]) -> String {
        if let text = node["text"] as? String { return text }
        if node["type"] as? String == "hardBreak" { return "\n" }
        let children = node["content"] as? [[String: Any]] ?? []
        let holdsBlocks = children.contains { child in
            let type = child["type"] as? String ?? ""
            return type != "text" && type != "hardBreak"
        }
        return children.map(text(inNode:)).joined(separator: holdsBlocks ? "\n" : "")
    }
}
