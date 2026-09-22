import Foundation

/// Splits a Markdown file into its YAML frontmatter and the body below it.
///
/// Deliberately the same small subset the mirror writes and the MCP server reads:
/// scalars and flat lists, one per line. A file with no frontmatter is all body, which
/// is what an importer wants for Markdown that came from somewhere else.
public enum MarkdownFrontmatter {
    public struct Parsed {
        public var fields: [String: String]
        public var body: String

        public init(fields: [String: String] = [:], body: String = "") {
            self.fields = fields
            self.body = body
        }
    }

    public static func split(_ text: String) -> Parsed {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return Parsed(body: normalized)
        }
        lines.removeFirst()

        var fields: [String: String] = [:]
        var closed = false
        var consumed = 0

        for line in lines {
            consumed += 1
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                closed = true
                break
            }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let raw = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { fields[key] = unquote(raw) }
        }

        // An opening --- with no closing one is not frontmatter; a document that starts
        // with a horizontal rule would otherwise lose everything after it.
        guard closed else { return Parsed(body: normalized) }

        let body = lines.dropFirst(consumed).joined(separator: "\n")
        return Parsed(fields: fields, body: body)
    }

    private static func unquote(_ raw: String) -> String {
        guard raw.count >= 2, let first = raw.first, let last = raw.last, first == last,
              first == "\"" || first == "'"
        else { return raw }
        return String(raw.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
