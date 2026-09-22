import Foundation

/// The shape of one file in the Markdown mirror: where it goes, and what is in it.
///
/// The mirror is export-only, so nothing here parses a file back; this decides names
/// and contents, and the app writes them.
public enum MirrorFile {
    public static let archiveDirectory = "_archive"
    public static let attachmentsDirectory = "attachments"

    /// `<folder path>/<sanitized title>-<8-char id>.md`, under `_archive/` when the page
    /// is archived. Relative to the mirror root.
    public static func relativePath(for page: Page) -> String {
        let folders = (page.folder?.pathComponents ?? []).map(sanitize)
        let name = "\(sanitize(page.title.isEmpty ? "untitled" : page.title))-\(shortID(page.id)).md"

        var components = folders
        if page.isArchived {
            components.insert(archiveDirectory, at: 0)
        }
        components.append(name)
        return components.joined(separator: "/")
    }

    /// Where an attachment is written, relative to the mirror root: beside its page.
    public static func attachmentRelativePath(for attachment: Attachment, page: Page) -> String {
        let directory = (relativePath(for: page) as NSString).deletingLastPathComponent
        let name = "\(attachment.id.uuidString).\(fileExtension(forMimeType: attachment.mimeType))"
        return directory.isEmpty
            ? "\(attachmentsDirectory)/\(name)"
            : "\(directory)/\(attachmentsDirectory)/\(name)"
    }

    /// Where every attachment of `page` belongs, relative to the mirror root.
    ///
    /// Derived from the model alone: the exporter uses this to decide which files on
    /// disk are still claimed, and that answer must not depend on whether a write
    /// happened to succeed, or a live image would look orphaned and be deleted.
    public static func attachmentPaths(for page: Page) -> [String] {
        (page.attachments ?? [])
            .filter { $0.data != nil }
            .map { attachmentRelativePath(for: $0, page: page) }
    }

    /// YAML frontmatter followed by the converted body.
    public static func contents(for page: Page) -> String {
        let extensions = (page.attachments ?? []).reduce(into: [UUID: String]()) { map, attachment in
            map[attachment.id] = fileExtension(forMimeType: attachment.mimeType)
        }
        let body = page.body.map {
            MarkdownConverter.markdown(from: $0, attachmentExtensions: extensions)
        } ?? ""

        return frontmatter(for: page) + "\n" + body + "\n"
    }

    // MARK: Pieces

    public static func frontmatter(for page: Page) -> String {
        var lines = ["---"]
        lines.append("id: \(page.id.uuidString)")
        lines.append("title: \(quoted(page.title))")
        lines.append("template: \(page.templateID.map(quoted) ?? "null")")
        lines.append("folder: \(quoted((page.folder?.pathComponents ?? []).joined(separator: "/")))")
        lines.append("created: \(iso(page.createdAt))")
        lines.append("updated: \(iso(page.updatedAt))")
        lines.append("period_start: \(page.periodStart.map(iso) ?? "null")")
        lines.append("event_date: \(page.eventDate.map(iso) ?? "null")")
        lines.append("goals: [\(page.goalIDs.map(quoted).joined(separator: ", "))]")
        lines.append("archived: \(page.isArchived)")
        lines.append("pinned: \(page.isPinned)")
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    /// A name safe on disk: path separators, colons and control characters out, spaces
    /// collapsed, and short enough to survive a file system.
    public static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.controlCharacters)
            .union(.newlines)

        let cleaned = name
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        let trimmed = String(cleaned.prefix(80)).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "untitled" : trimmed
    }

    public static func shortID(_ id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    }

    public static func fileExtension(forMimeType mime: String) -> String {
        switch mime.lowercased() {
        case "image/png": "png"
        case "image/jpeg", "image/jpg": "jpg"
        case "image/gif": "gif"
        case "image/heic": "heic"
        case "image/webp": "webp"
        case "application/pdf": "pdf"
        default: "png"
        }
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    /// YAML strings are quoted so a colon or a leading digit in a title cannot change
    /// what the file means.
    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}
