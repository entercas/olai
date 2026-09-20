import Foundation
import SwiftData

/// The model types backing the store, in one place so the app and the tests build the
/// same schema.
public enum OlaiSchema {
    public static let identifier = "iCloud.com.entercas.olai"

    public static var models: [any PersistentModel.Type] {
        [Folder.self, Page.self, Attachment.self]
    }

    public static var schema: Schema {
        Schema(models)
    }
}
