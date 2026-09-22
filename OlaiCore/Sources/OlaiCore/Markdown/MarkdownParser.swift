import Foundation

/// Turns Markdown into the TipTap document Olai stores.
///
/// The inverse of `MarkdownConverter`, and deliberately scoped to what the editor can
/// actually represent: the extensions it loads are StarterKit, Highlight, Image, Link,
/// TaskList and Underline. Markdown that has no home in that schema (tables, footnotes,
/// raw HTML beyond `<u>`) is kept as text rather than dropped, on the same principle the
/// converter uses in the other direction -- an import that silently loses a paragraph is
/// worse than one that keeps it looking plain.
public enum MarkdownParser {
    /// - Parameter resolveImage: given the path written in the Markdown, returns the
    ///   `src` to store instead -- `attachment://<uuid>` once the importer has read the
    ///   file in. Returning nil keeps the original path, which still renders for an
    ///   absolute URL and harmlessly does not for a relative one.
    public static func document(
        from markdown: String,
        resolveImage: ((String) -> String?)? = nil
    ) -> Data {
        let blocks = documentObject(from: markdown, resolveImage: resolveImage)
        return (try? JSONSerialization.data(withJSONObject: blocks, options: [.sortedKeys]))
            ?? TipTapDocument.emptyDocument
    }

    /// The same result before serialising, for tests and for callers that want to look
    /// at the structure.
    public static func documentObject(
        from markdown: String,
        resolveImage: ((String) -> String?)? = nil
    ) -> [String: Any] {
        let parser = Parser(resolveImage: resolveImage)
        var content = parser.blocks(in: Parser.lines(of: markdown))
        // ProseMirror will not accept a doc with no content.
        if content.isEmpty { content = [["type": "paragraph"]] }
        return ["type": "doc", "content": content]
    }
}

// MARK: - Blocks

private struct Parser {
    let resolveImage: ((String) -> String?)?

    static func lines(of markdown: String) -> [String] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
    }

    func blocks(in lines: [String]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fenceLanguage(trimmed) {
                let (node, next) = codeBlock(from: lines, at: index, language: fence)
                result.append(node)
                index = next
                continue
            }

            if isHorizontalRule(trimmed) {
                result.append(["type": "horizontalRule"])
                index += 1
                continue
            }

            if let heading = heading(trimmed) {
                result.append(heading)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                let (node, next) = blockquote(from: lines, at: index)
                result.append(node)
                index = next
                continue
            }

            if listMarker(line) != nil {
                let (nodes, next) = lists(from: lines, at: index)
                result.append(contentsOf: nodes)
                index = next
                continue
            }

            let (node, next) = paragraph(from: lines, at: index)
            if let node { result.append(node) }
            index = next
        }

        return result
    }

    // MARK: Leaf blocks

    private func heading(_ trimmed: String) -> [String: Any]? {
        var level = 0
        var rest = Substring(trimmed)
        while rest.first == "#", level < 7 {
            level += 1
            rest = rest.dropFirst()
        }
        guard (1...6).contains(level), rest.first == " " || rest.isEmpty else { return nil }

        // The editor offers h1-h3; deeper headings would be dropped by the schema, so
        // they land on the closest level that survives.
        let text = String(rest).trimmingCharacters(in: .whitespaces)
        return [
            "type": "heading",
            "attrs": ["level": min(level, 3)],
            "content": inline(text),
        ]
    }

    private func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    private func fenceLanguage(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("```") else { return nil }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    private func codeBlock(
        from lines: [String],
        at start: Int,
        language: String
    ) -> ([String: Any], Int) {
        var body: [String] = []
        var index = start + 1

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                index += 1
                break
            }
            body.append(lines[index])
            index += 1
        }

        var node: [String: Any] = ["type": "codeBlock"]
        if !language.isEmpty { node["attrs"] = ["language": language] }
        let text = body.joined(separator: "\n")
        if !text.isEmpty { node["content"] = [["type": "text", "text": text]] }
        return (node, index)
    }

    private func blockquote(from lines: [String], at start: Int) -> ([String: Any], Int) {
        var inner: [String] = []
        var index = start

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            var rest = Substring(trimmed.dropFirst())
            if rest.first == " " { rest = rest.dropFirst() }
            inner.append(String(rest))
            index += 1
        }

        var content = blocks(in: inner)
        if content.isEmpty { content = [["type": "paragraph"]] }
        return (["type": "blockquote", "content": content], index)
    }

    /// Consecutive non-blank lines that are not another block. A trailing double space is
    /// how the converter writes a hard break, so it is read back as one.
    private func paragraph(from lines: [String], at start: Int) -> ([String: Any]?, Int) {
        var pieces: [String] = []
        var index = start

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if heading(trimmed) != nil || isHorizontalRule(trimmed) { break }
            if fenceLanguage(trimmed) != nil || trimmed.hasPrefix(">") { break }
            if listMarker(line) != nil { break }
            pieces.append(line.hasSuffix("  ") ? String(line.dropLast(2)) + "\u{0000}" : trimmed)
            index += 1
        }

        guard !pieces.isEmpty else { return (nil, index + 1) }

        // A lone image on its own line is a block in the schema, not inline content.
        if pieces.count == 1, let only = standaloneImage(pieces[0]) {
            return (only, index)
        }

        let joined = pieces.joined(separator: " ").replacingOccurrences(of: "\u{0000} ", with: "\u{0000}")
        return (["type": "paragraph", "content": inline(joined)], index)
    }

    private func standaloneImage(_ text: String) -> [String: Any]? {
        let nodes = inline(text)
        guard nodes.count == 1, let only = nodes.first,
              only["type"] as? String == "image"
        else { return nil }
        return only
    }

    // MARK: Lists

    private struct Marker {
        var indent: Int
        var kind: String
        var checked: Bool?
        var rest: String
    }

    private func listMarker(_ line: String) -> Marker? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        // Two spaces per level is what the converter writes; a tab counts as one level.
        let indent = leading.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
        var rest = Substring(line.dropFirst(leading.count))

        if let first = rest.first, first == "-" || first == "*" || first == "+" {
            rest = rest.dropFirst()
            guard rest.first == " " else { return nil }
            rest = rest.dropFirst()

            let text = String(rest)
            if text.hasPrefix("[ ] ") || text == "[ ]" {
                return Marker(indent: indent, kind: "taskList", checked: false,
                              rest: String(text.dropFirst(min(4, text.count))))
            }
            if text.lowercased().hasPrefix("[x] ") || text.lowercased() == "[x]" {
                return Marker(indent: indent, kind: "taskList", checked: true,
                              rest: String(text.dropFirst(min(4, text.count))))
            }
            return Marker(indent: indent, kind: "bulletList", checked: nil, rest: text)
        }

        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        rest = rest.dropFirst(digits.count)
        guard rest.first == "." || rest.first == ")" else { return nil }
        rest = rest.dropFirst()
        guard rest.first == " " else { return nil }
        return Marker(indent: indent, kind: "orderedList", checked: nil,
                      rest: String(rest.dropFirst()))
    }

    /// Reads one run of list lines into one or more list nodes -- more than one when the
    /// run changes kind, since a bullet list and a numbered list are different nodes.
    private func lists(from lines: [String], at start: Int) -> ([[String: Any]], Int) {
        var index = start
        var run: [(Marker, Int)] = []

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // A blank line inside a list only ends it if what follows is not a list.
                var lookahead = index + 1
                while lookahead < lines.count,
                      lines[lookahead].trimmingCharacters(in: .whitespaces).isEmpty {
                    lookahead += 1
                }
                guard lookahead < lines.count, listMarker(lines[lookahead]) != nil else { break }
                index = lookahead
                continue
            }
            guard let marker = listMarker(line) else { break }
            run.append((marker, index))
            index += 1
        }

        guard !run.isEmpty else { return ([], index) }
        return (build(run.map { $0.0 }), index)
    }

    /// Builds nested list nodes from a flat run of markers, using each one's indent.
    private func build(_ markers: [Marker]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var position = 0

        while position < markers.count {
            let kind = markers[position].kind
            let indent = markers[position].indent
            var items: [[String: Any]] = []

            while position < markers.count,
                  markers[position].kind == kind,
                  markers[position].indent == indent {
                let marker = markers[position]
                position += 1

                // Everything more deeply indented belongs to this item.
                var nested: [Marker] = []
                while position < markers.count, markers[position].indent > indent {
                    nested.append(markers[position])
                    position += 1
                }

                var content: [[String: Any]] = [
                    ["type": "paragraph", "content": inline(marker.rest)]
                ]
                content.append(contentsOf: build(nested))

                var item: [String: Any] = [
                    "type": kind == "taskList" ? "taskItem" : "listItem",
                    "content": content,
                ]
                if let checked = marker.checked { item["attrs"] = ["checked": checked] }
                items.append(item)
            }

            result.append(["type": kind, "content": items])
        }

        return result
    }

    // MARK: Inline

    func inline(_ text: String) -> [[String: Any]] {
        guard !text.isEmpty else { return [] }
        var nodes: [[String: Any]] = []
        var plain = ""

        func flush() {
            guard !plain.isEmpty else { return }
            nodes.append(["type": "text", "text": plain])
            plain = ""
        }

        var rest = Substring(text)
        while let character = rest.first {
            // A hard break is carried through paragraph joining as a sentinel.
            if character == "\u{0000}" {
                flush()
                nodes.append(["type": "hardBreak"])
                rest = rest.dropFirst()
                continue
            }

            if character == "\\", rest.count > 1 {
                plain.append(rest[rest.index(after: rest.startIndex)])
                rest = rest.dropFirst(2)
                continue
            }

            if let (node, remainder) = image(rest) ?? link(rest) {
                flush()
                nodes.append(node)
                rest = remainder
                continue
            }

            if let (node, remainder) = emphasis(rest) {
                flush()
                nodes.append(node)
                rest = remainder
                continue
            }

            plain.append(character)
            rest = rest.dropFirst()
        }

        flush()
        return nodes
    }

    private func image(_ rest: Substring) -> ([String: Any], Substring)? {
        guard rest.hasPrefix("!["), let parts = bracketed(rest.dropFirst()) else { return nil }
        var attrs: [String: Any] = ["src": resolveImage?(parts.target) ?? parts.target]
        if !parts.label.isEmpty { attrs["alt"] = parts.label }
        return (["type": "image", "attrs": attrs], parts.remainder)
    }

    private func link(_ rest: Substring) -> ([String: Any], Substring)? {
        guard rest.hasPrefix("["), let parts = bracketed(rest) else { return nil }
        let inner = inline(parts.label)
        let marked = inner.map { node -> [String: Any] in
            guard node["type"] as? String == "text" else { return node }
            var copy = node
            var marks = node["marks"] as? [[String: Any]] ?? []
            marks.append(["type": "link", "attrs": ["href": parts.target]])
            copy["marks"] = marks
            return copy
        }
        guard !marked.isEmpty else { return nil }
        // One node is returned at a time, so a multi-node label is wrapped by re-entry.
        return (marked.count == 1 ? marked[0] : ["type": "text", "text": parts.label,
                                                 "marks": [["type": "link",
                                                            "attrs": ["href": parts.target]]]],
                parts.remainder)
    }

    /// Splits `[label](target)` starting at `rest`.
    private func bracketed(_ rest: Substring) -> (label: String, target: String, remainder: Substring)? {
        guard rest.first == "[" else { return nil }
        var depth = 0
        var index = rest.startIndex
        var closing: Substring.Index?

        while index < rest.endIndex {
            let character = rest[index]
            if character == "[" { depth += 1 }
            if character == "]" {
                depth -= 1
                if depth == 0 { closing = index; break }
            }
            index = rest.index(after: index)
        }

        guard let close = closing else { return nil }
        let afterClose = rest.index(after: close)
        guard afterClose < rest.endIndex, rest[afterClose] == "(" else { return nil }

        var parens = 0
        var cursor = afterClose
        var end: Substring.Index?
        while cursor < rest.endIndex {
            let character = rest[cursor]
            if character == "(" { parens += 1 }
            if character == ")" {
                parens -= 1
                if parens == 0 { end = cursor; break }
            }
            cursor = rest.index(after: cursor)
        }

        guard let target = end else { return nil }
        return (
            label: String(rest[rest.index(after: rest.startIndex)..<close]),
            target: String(rest[rest.index(after: afterClose)..<target]),
            remainder: rest[rest.index(after: target)...]
        )
    }

    private static let emphasisMarkers: [(delimiter: String, mark: String)] = [
        ("***", "boldItalic"),
        ("**", "bold"),
        ("~~", "strike"),
        ("==", "highlight"),
        ("`", "code"),
        ("*", "italic"),
        ("_", "italic"),
    ]

    private func emphasis(_ rest: Substring) -> ([String: Any], Substring)? {
        if rest.hasPrefix("<u>"), let close = rest.range(of: "</u>") {
            let inner = String(rest[rest.index(rest.startIndex, offsetBy: 3)..<close.lowerBound])
            return (text(inner, marks: ["underline"]), rest[close.upperBound...])
        }

        for (delimiter, mark) in Self.emphasisMarkers where rest.hasPrefix(delimiter) {
            let after = rest.dropFirst(delimiter.count)
            guard let close = after.range(of: delimiter) else { continue }
            let inner = String(after[after.startIndex..<close.lowerBound])
            guard !inner.isEmpty else { continue }

            let marks = mark == "boldItalic" ? ["bold", "italic"] : [mark]
            return (text(inner, marks: marks), after[close.upperBound...])
        }
        return nil
    }

    /// Code is literal: anything inside backticks keeps its markers rather than being
    /// parsed again.
    private func text(_ value: String, marks: [String]) -> [String: Any] {
        if marks == ["code"] {
            return ["type": "text", "text": value, "marks": [["type": "code"]]]
        }
        let inner = inline(value)
        let combined = inner.map { node -> [String: Any] in
            guard node["type"] as? String == "text" else { return node }
            var copy = node
            var existing = node["marks"] as? [[String: Any]] ?? []
            existing.append(contentsOf: marks.map { ["type": $0] })
            copy["marks"] = existing
            return copy
        }
        if combined.count == 1 { return combined[0] }
        return ["type": "text", "text": value, "marks": marks.map { ["type": $0] }]
    }
}
