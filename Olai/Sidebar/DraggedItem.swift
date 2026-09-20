import CoreTransferable
import Foundation
import OlaiCore
import UniformTypeIdentifiers

extension UTType {
    /// Private type for sidebar drags. Declared in both Info.plists so the pasteboard
    /// knows it; nothing outside the app reads it.
    static let olaiTreeItem = UTType(exportedAs: "com.entercas.olai.tree-item")
}

/// What a sidebar drag carries: which kind of thing, and which one.
///
/// The model objects themselves are not sent. A drag crosses view boundaries and can
/// outlive the row it started from, so it carries the stable `UUID` and the drop side
/// looks the object up.
struct DraggedItem: Codable, Transferable {
    enum Kind: String, Codable {
        case folder
        case page
    }

    var kind: Kind
    var id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .olaiTreeItem)
    }
}
