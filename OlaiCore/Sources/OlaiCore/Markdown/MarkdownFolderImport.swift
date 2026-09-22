import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Imports a folder of Markdown into the tree.
///
/// Built for bulk: a converter elsewhere turns something else -- OneNote, say -- into a
/// folder of `.md` files, and this reads the whole tree in one go. Directory structure
/// becomes folders, each file becomes a page, and images the Markdown points at are read
/// in as attachments so the pages keep working after the source folder is deleted.
///
/// Frontmatter is honoured when a file has it, which makes a mirror folder re-importable:
/// what Olai exported can be read back with its titles, templates and dates intact.
public enum MarkdownFolderImport {
    public static let readableTypes: [UTType] = [.folder]

    public struct Summary {
        public internal(set) var folders = 0
        public internal(set) var pages = 0
        public internal(set) var images = 0
        /// Files that could not be read. Named rather than counted, so a failed import
        /// says which pages are missing instead of leaving it to be discovered later.
        public internal(set) var skipped: [String] = []

        public var sentence: String {
            var parts = ["\(pages) page\(pages == 1 ? "" : "s")"]
            if folders > 0 { parts.append("\(folders) folder\(folders == 1 ? "" : "s")") }
            if images > 0 { parts.append("\(images) image\(images == 1 ? "" : "s")") }
            return parts.joined(separator: ", ")
        }
    }

    public enum Failure: LocalizedError {
        case insideMirror
        case unreadable(String)
        case nothingFound

        public var errorDescription: String? {
            switch self {
            case .insideMirror:
                "That folder is the Markdown mirror Olai writes. Importing it would make a second copy of every page. Pick the folder your converter wrote instead."
            case let .unreadable(name):
                "Could not read \(name)."
            case .nothingFound:
                "No .md files in that folder."
            }
        }
    }

    /// - Parameter mirrorRoot: where the mirror is written, so importing it back into
    ///   itself can be refused rather than silently doubling the library.
    @discardableResult
    public static func importFolder(
        at url: URL,
        into parent: Folder?,
        context: ModelContext,
        mirrorRoot: URL? = nil,
        now: Date = Date()
    ) throws -> Summary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if let mirrorRoot, isInside(url, mirrorRoot) { throw Failure.insideMirror }

        let files = try markdownFiles(under: url)
        guard !files.isEmpty else { throw Failure.nothingFound }

        var summary = Summary()
        let root = makeFolder(named: url.lastPathComponent, in: parent, context: context)
        summary.folders += 1

        // One folder per directory, made on demand and remembered, so twenty files in
        // the same section do not make twenty folders.
        var folders: [String: Folder] = ["": root]

        for file in files.sorted(by: { $0.path < $1.path }) {
            let relative = relativeDirectory(of: file, under: url)
            let folder = folder(for: relative, root: root, cache: &folders, context: context, summary: &summary)

            do {
                let images = try importFile(at: file, into: folder, context: context, now: now)
                summary.pages += 1
                summary.images += images
            } catch {
                summary.skipped.append(file.lastPathComponent)
            }
        }

        return summary
    }

    // MARK: One file

    private static func importFile(
        at url: URL,
        into folder: Folder,
        context: ModelContext,
        now: Date
    ) throws -> Int {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            throw Failure.unreadable(url.lastPathComponent)
        }

        let parsed = MarkdownFrontmatter.split(raw)
        let page = makePage(titled: title(from: parsed, url: url), in: folder, context: context)

        var imported = 0
        let directory = url.deletingLastPathComponent()
        let body = MarkdownParser.document(from: parsed.body) { path in
            guard let attachment = attachment(for: path, relativeTo: directory, page: page) else {
                return nil
            }
            context.insert(attachment)
            imported += 1
            return "attachment://\(attachment.id.uuidString)"
        }

        page.body = body
        page.plainText = TipTapDocument.plainText(from: body) ?? ""
        apply(parsed.fields, to: page, now: now)
        return imported
    }

    /// Frontmatter first, then the document's own first heading, then the filename --
    /// the filename is the last resort because a converter tends to make it a slug.
    private static func title(from parsed: MarkdownFrontmatter.Parsed, url: URL) -> String {
        if let fromFields = parsed.fields["title"]?.trimmingCharacters(in: .whitespaces),
           !fromFields.isEmpty {
            return fromFields
        }
        for line in parsed.body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            let text = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
            break
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func apply(_ fields: [String: String], to page: Page, now: Date) {
        if let template = fields["template"], !template.isEmpty, template != "null" {
            page.templateID = template
        }
        page.isPinned = fields["pinned"] == "true"
        page.isArchived = fields["archived"] == "true"
        page.createdAt = date(fields["created"]) ?? now
        page.updatedAt = date(fields["updated"]) ?? page.createdAt
        page.periodStart = date(fields["period_start"])
        page.eventDate = date(fields["event_date"])
    }

    /// Built per call rather than shared: `ISO8601DateFormatter` is not `Sendable`, and
    /// an import parses a few dates per file, not a few thousand.
    private static func date(_ raw: String?) -> Date? {
        guard let raw, raw != "null", !raw.isEmpty else { return nil }
        if let plain = ISO8601DateFormatter().date(from: raw) { return plain }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }

    // MARK: Images

    private static func attachment(for path: String, relativeTo directory: URL, page: Page) -> Attachment? {
        // A remote image stays a remote image; only files next to the Markdown are read in.
        guard !path.hasPrefix("http://"), !path.hasPrefix("https://"), !path.hasPrefix("attachment://")
        else { return nil }

        let decoded = path.removingPercentEncoding ?? path
        let url = decoded.hasPrefix("/")
            ? URL(fileURLWithPath: decoded)
            : directory.appending(path: decoded)

        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }

        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        let narrowed = Attachment.safeMimeType(mime)
        // An unrecognised type would be stored as bytes the editor cannot render.
        guard narrowed != Attachment.fallbackMimeType else { return nil }

        return Attachment(
            filename: url.lastPathComponent,
            mimeType: narrowed,
            data: data,
            page: page
        )
    }

    // MARK: Making nodes

    /// Sort order continues after whatever is already there, the same rule `NoteTree`
    /// uses, so imported items land at the end rather than interleaving.
    private static func makeFolder(named name: String, in parent: Folder?, context: ModelContext) -> Folder {
        let siblings = parent?.sortedChildren ?? []
        let folder = Folder(
            name: name,
            sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1,
            parent: parent
        )
        context.insert(folder)
        return folder
    }

    private static func makePage(titled title: String, in folder: Folder?, context: ModelContext) -> Page {
        let page = Page(
            title: title,
            body: TipTapDocument.emptyDocument,
            sortOrder: ((folder?.sortedPages ?? []).map(\.sortOrder).max() ?? -1) + 1,
            folder: folder
        )
        context.insert(page)
        return page
    }

    // MARK: Walking the folder

    private static func markdownFiles(under root: URL) throws -> [URL] {
        let manager = FileManager.default
        guard let walker = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw Failure.unreadable(root.lastPathComponent) }

        var found: [URL] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "md" {
            found.append(url)
        }
        return found
    }

    private static func relativeDirectory(of file: URL, under root: URL) -> String {
        let rootParts = root.standardizedFileURL.pathComponents
        let fileParts = file.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard fileParts.count > rootParts.count else { return "" }
        return fileParts.dropFirst(rootParts.count).joined(separator: "/")
    }

    private static func folder(
        for relative: String,
        root: Folder,
        cache: inout [String: Folder],
        context: ModelContext,
        summary: inout Summary
    ) -> Folder {
        if let existing = cache[relative] { return existing }

        var parent = root
        var walked: [String] = []
        for component in relative.components(separatedBy: "/") where !component.isEmpty {
            walked.append(component)
            let key = walked.joined(separator: "/")
            if let existing = cache[key] {
                parent = existing
                continue
            }
            let made = makeFolder(named: component, in: parent, context: context)
            summary.folders += 1
            cache[key] = made
            parent = made
        }

        cache[relative] = parent
        return parent
    }

    private static func isInside(_ url: URL, _ root: URL) -> Bool {
        let target = url.standardizedFileURL.pathComponents
        let base = root.standardizedFileURL.pathComponents
        guard target.count >= base.count else { return false }
        return Array(target.prefix(base.count)) == base
    }
}
