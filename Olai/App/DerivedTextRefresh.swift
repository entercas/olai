import Foundation
import OlaiCore
import SwiftData

/// Recomputes each page's stored plain text from its document.
///
/// Plain text is derived, kept only for search and the page list's preview. When the way
/// it is derived changes -- list items used to run together with nothing between them --
/// pages written before the change keep the old text until someone next edits them, so
/// search misses them and their previews read wrong. Recomputing is cheap and touches
/// nothing a person wrote: `updatedAt` is left alone, since the page did not change.
@MainActor
enum DerivedTextRefresh {
    static func run(in context: ModelContext) {
        let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
        var changed = 0
        for page in pages {
            guard let body = page.body, let fresh = TipTapDocument.plainText(from: body) else { continue }
            if fresh != page.plainText {
                page.plainText = fresh
                changed += 1
            }
        }
        if changed > 0 { try? context.save() }
    }
}
