import Foundation

/// Turns a TipTap document into the Markdown the mirror exports.
///
/// The mirror is export-only, so this never has to read Markdown back. Anything the
/// converter does not recognise falls back to its text, which keeps an unknown block
/// readable rather than dropping it.
public enum MarkdownConverter {
    /// - Parameter attachmentExtensions: file extension per attachment id, so an image
    ///   points at the file written beside the page. Defaults to `png`.
    public static func markdown(
        from document: Data,
        attachmentExtensions: [UUID: String] = [:]
    ) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: document),
            let doc = object as? [String: Any],
            doc["type"] as? String == "doc"
        else { return "" }

        let blocks = doc["content"] as? [[String: Any]] ?? []
        let converter = Converter(attachmentExtensions: attachmentExtensions)
        let rendered = blocks.compactMap { converter.block($0, indent: 0) }

        return rendered.joined(separator: "\n\n").trimmingCharacters(in: .newlines)
    }
}

private struct Converter {
    let attachmentExtensions: [UUID: String]

    // MARK: Blocks

    func block(_ node: [String: Any], indent: Int) -> String? {
        let type = node["type"] as? String ?? ""
        let children = node["content"] as? [[String: Any]] ?? []

        switch type {
        case "paragraph":
            let text = inline(children)
            return text.isEmpty ? "" : text

        case "heading":
            let level = (node["attrs"] as? [String: Any])?["level"] as? Int ?? 1
            return String(repeating: "#", count: min(max(level, 1), 6)) + " " + inline(children)

        case "bulletList", "orderedList", "taskList":
            return list(type: type, items: children, indent: indent)

        case "blockquote":
            let inner = children.compactMap { block($0, indent: indent) }.joined(separator: "\n\n")
            return inner
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> \($0)" }
                .joined(separator: "\n")

        case "codeBlock":
            let language = (node["attrs"] as? [String: Any])?["language"] as? String ?? ""
            return "```\(language)\n\(plainText(children))\n```"

        case "horizontalRule":
            return "---"

        case "image":
            return image(node)

        default:
            // Unknown block: keep whatever text it holds rather than losing it.
            let text = inline(children)
            return text.isEmpty ? nil : text
        }
    }

    private func list(type: String, items: [[String: Any]], indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)

        let lines = items.enumerated().map { position, item -> String in
            let marker = self.marker(for: type, item: item, position: position)
            let blocks = item["content"] as? [[String: Any]] ?? []

            // The item's own text sits on the marker line; anything nested below it
            // (a sub-list, an image) goes on its own lines, indented one level in.
            var first = ""
            var rest: [String] = []

            for child in blocks {
                let childType = child["type"] as? String ?? ""
                if childType == "paragraph", first.isEmpty {
                    first = inline(child["content"] as? [[String: Any]] ?? [])
                } else if let rendered = block(child, indent: indent + 1) {
                    // A nested list pads its own lines; anything else has to be pushed
                    // in here, or it reads as leaving the list item.
                    let isList = ["bulletList", "orderedList", "taskList"].contains(childType)
                    rest.append(isList ? rendered : indented(rendered, by: indent + 1))
                }
            }

            return ([pad + marker + first] + rest).joined(separator: "\n")
        }

        return lines.joined(separator: "\n")
    }

    private func indented(_ text: String, by level: Int) -> String {
        let pad = String(repeating: "  ", count: level)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : pad + $0 }
            .joined(separator: "\n")
    }

    private func marker(for type: String, item: [String: Any], position: Int) -> String {
        switch type {
        case "orderedList":
            return "\(position + 1). "
        case "taskList":
            let checked = (item["attrs"] as? [String: Any])?["checked"] as? Bool ?? false
            return checked ? "- [x] " : "- [ ] "
        default:
            return "- "
        }
    }

    private func image(_ node: [String: Any]) -> String {
        let attrs = node["attrs"] as? [String: Any] ?? [:]
        let source = attrs["src"] as? String ?? ""
        let alt = attrs["alt"] as? String ?? ""

        guard source.hasPrefix("attachment://") else {
            return "![\(alt)](\(source))"
        }

        let identifier = String(source.dropFirst("attachment://".count))
        let ext = UUID(uuidString: identifier).flatMap { attachmentExtensions[$0] } ?? "png"
        return "![\(alt)](attachments/\(identifier).\(ext))"
    }

    // MARK: Inline

    func inline(_ nodes: [[String: Any]]) -> String {
        nodes.map { node in
            switch node["type"] as? String {
            case "text":
                return marked(node)
            case "hardBreak":
                return "  \n"
            case "image":
                return image(node)
            default:
                return inline(node["content"] as? [[String: Any]] ?? [])
            }
        }
        .joined()
    }

    /// Wraps a text node in whatever marks it carries, innermost first.
    private func marked(_ node: [String: Any]) -> String {
        var text = node["text"] as? String ?? ""
        let marks = node["marks"] as? [[String: Any]] ?? []

        for mark in marks {
            let type = mark["type"] as? String ?? ""
            let attrs = mark["attrs"] as? [String: Any] ?? [:]

            switch type {
            case "bold": text = "**\(text)**"
            case "italic": text = "*\(text)*"
            case "strike": text = "~~\(text)~~"
            case "code": text = "`\(text)`"
            case "highlight": text = "==\(text)=="
            // Markdown has no underline; the mirror keeps the inline HTML it allows.
            case "underline": text = "<u>\(text)</u>"
            case "link": text = "[\(text)](\(attrs["href"] as? String ?? ""))"
            default: break
            }
        }

        return text
    }

    private func plainText(_ nodes: [[String: Any]]) -> String {
        nodes.map { node in
            if let text = node["text"] as? String { return text }
            return plainText(node["content"] as? [[String: Any]] ?? [])
        }
        .joined()
    }
}
