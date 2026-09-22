import Foundation
import OlaiCore
import SwiftData

/// Deletes attachments no page body refers to any more.
///
/// Removing an image from a page -- with the delete key, or by undoing the paste that
/// inserted it -- takes the node out of the document but leaves the `Attachment` behind,
/// still owned by the page. Nothing in the app can reach it again, yet its bytes stay in
/// the store, sync to every device, and are written into the Markdown mirror. Every image
/// a person inserts and then thinks better of would accumulate forever.
///
/// Run once at launch and never while a page is open: an editor keeps an undo history, so
/// an image removed a moment ago can still come back, and deleting its bytes underneath
/// would restore a broken image. At launch no editor has history yet, so anything
/// unreferenced is unreachable for good.
@MainActor
enum AttachmentCleanup {
    @discardableResult
    static func run(in context: ModelContext) -> Int {
        let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
        var deleted = 0

        for page in pages {
            let attachments = page.attachments ?? []
            guard !attachments.isEmpty else { continue }

            // A body that will not parse tells us nothing about what it references.
            // Treating that as "references nothing" would delete the page's images.
            guard
                let body = page.body,
                let referenced = TipTapDocument.attachmentIDs(in: body)
            else { continue }

            for attachment in attachments where !referenced.contains(attachment.id) {
                context.delete(attachment)
                deleted += 1
            }
        }

        if deleted > 0 {
            // Saved here rather than left to autosave: the mirror export runs next and
            // reads `page.attachments`, which still lists a deleted attachment until the
            // context processes the change -- so the row went but its file stayed.
            try? context.save()
            NSLog("Olai: removed \(deleted) attachment(s) no page refers to any more.")
        }
        return deleted
    }
}
