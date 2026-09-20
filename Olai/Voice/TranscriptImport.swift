import Foundation
import OlaiCore
import SwiftData
import UniformTypeIdentifiers

/// Reads a `.vtt`, `.srt` or `.txt` transcript into a new `transcript` page.
@MainActor
enum TranscriptImport {
    /// The open panel greys out anything not conforming to these, and macOS knows
    /// neither extension on its own -- both are declared in Info.plist as plain text so
    /// a .vtt or .srt can actually be picked.
    static let readableTypes: [UTType] = [
        UTType("org.w3.webvtt"),
        UTType("public.subrip-subtitle"),
        UTType(filenameExtension: "vtt"),
        UTType(filenameExtension: "srt"),
        .plainText,
        .text,
    ].compactMap { $0 }

    /// The date comes from the filename, then the file's own header, and only then the
    /// modification date -- what the file says about itself beats when it was written.
    @discardableResult
    static func importTranscript(
        from url: URL,
        into folder: Folder?,
        context: ModelContext
    ) throws -> Page {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let contents = try String(contentsOf: url, encoding: .utf8)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate

        let parsed = TranscriptParser.parse(
            contents,
            filename: url.lastPathComponent,
            modifiedAt: modified
        )

        let title = url.deletingPathExtension().lastPathComponent
        let page = NoteTree.addPage(titled: title, in: folder, context: context)
        page.templateID = "transcript"
        page.eventDate = parsed.eventDate

        let body = TranscriptDocument.body(for: parsed, title: title)
        page.body = body
        page.plainText = TipTapDocument.plainText(from: body) ?? ""

        return page
    }
}
