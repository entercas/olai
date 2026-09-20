import Foundation
import SwiftData

/// A single note. `body` holds the TipTap/ProseMirror JSON document; `plainText` is a
/// derived flattening of it kept for search and for the phase 1 plain-text editor.
@Model
public final class Page {
    public var id: UUID = UUID()
    public var title: String = ""
    public var templateID: String?
    public var body: Data?
    public var plainText: String = ""
    public var isArchived: Bool = false
    public var isPinned: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var periodStart: Date?
    public var eventDate: Date?
    public var goalIDs: [String] = []
    public var sortOrder: Int = 0

    public var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Attachment.page)
    public var attachments: [Attachment]?

    public init(
        id: UUID = UUID(),
        title: String = "",
        templateID: String? = nil,
        body: Data? = nil,
        plainText: String = "",
        isArchived: Bool = false,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        periodStart: Date? = nil,
        eventDate: Date? = nil,
        goalIDs: [String] = [],
        sortOrder: Int = 0,
        folder: Folder? = nil
    ) {
        self.id = id
        self.title = title
        self.templateID = templateID
        self.body = body
        self.plainText = plainText
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.periodStart = periodStart
        self.eventDate = eventDate
        self.goalIDs = goalIDs
        self.sortOrder = sortOrder
        self.folder = folder
    }
}

public extension Page {
    static func displayOrder(_ lhs: Page, _ rhs: Page) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    /// The body decoded as plain text, falling back to the stored `plainText` when the
    /// document is missing or unreadable.
    var bodyText: String {
        guard let body else { return plainText }
        return TipTapDocument.plainText(from: body) ?? plainText
    }

    /// Replaces the body with a plain-text document and refreshes derived fields.
    func setBodyText(_ text: String, now: Date = Date()) {
        guard text != bodyText else { return }
        body = TipTapDocument.document(fromPlainText: text)
        plainText = text
        updatedAt = now
    }
}
