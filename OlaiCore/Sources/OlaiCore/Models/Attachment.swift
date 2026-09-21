import Foundation
import SwiftData

/// Binary content referenced from a page body as `attachment://<id>`.
@Model
public final class Attachment {
    public var id: UUID = UUID()
    public var filename: String = ""
    public var mimeType: String = ""

    @Attribute(.externalStorage)
    public var data: Data?

    public var createdAt: Date = Date()

    public var page: Page?

    /// The content types Olai is willing to store and serve.
    ///
    /// The type string is not derived from the bytes: it arrives from JavaScript over
    /// the editor bridge, and from other devices over CloudKit. Attachments are served
    /// from `olai://editor/attachment/<uuid>`, the same origin as the editor itself, so
    /// a type of `text/html` would put attacker-supplied markup on the editor's origin.
    /// Narrowing it to this list means an attachment can only ever be rendered as an
    /// image or a PDF.
    public static let allowedMimeTypes: Set<String> = [
        "image/png",
        "image/jpeg",
        "image/gif",
        "image/heic",
        "image/webp",
        "application/pdf",
    ]

    /// What anything unrecognised is stored and served as. Browsers download rather
    /// than render it, so it cannot execute.
    public static let fallbackMimeType = "application/octet-stream"

    /// Narrows an arbitrary type string to one of `allowedMimeTypes`, dropping any
    /// parameters (`image/png; charset=utf-8`) and spelling `image/jpg` the canonical
    /// way. Applied both when storing an attachment and when serving one, so that a
    /// value already on disk or arriving from another device is narrowed too.
    public static func safeMimeType(_ mime: String) -> String {
        let base = mime.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
        let normalized = base.trimmingCharacters(in: .whitespaces).lowercased()
        let canonical = normalized == "image/jpg" ? "image/jpeg" : normalized
        return allowedMimeTypes.contains(canonical) ? canonical : fallbackMimeType
    }

    public init(
        id: UUID = UUID(),
        filename: String = "",
        mimeType: String = "",
        data: Data? = nil,
        createdAt: Date = Date(),
        page: Page? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.createdAt = createdAt
        self.page = page
    }
}
