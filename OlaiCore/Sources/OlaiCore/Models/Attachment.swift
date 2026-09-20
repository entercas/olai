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
