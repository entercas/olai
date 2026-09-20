import Foundation
import OlaiCore
import SwiftData

@MainActor
extension NoteTree {
    /// Creates whatever a template describes: a page, or a folder with its pages in it.
    /// Returns the page to open, if there is one.
    @discardableResult
    static func create(
        from template: NoteTemplate,
        in parent: Folder?,
        context: ModelContext,
        now: Date = Date()
    ) -> Page? {
        switch template.kind {
        case .page:
            return addPage(from: template, in: parent, context: context, now: now)

        case .folder:
            let folder = addFolder(
                named: TemplateLibrary.title(from: template.titlePattern, now: now),
                in: parent,
                context: context
            )
            let pages = template.pages.map {
                addPage(from: $0, in: folder, context: context, now: now)
            }
            return pages.first
        }
    }

    @discardableResult
    private static func addPage(
        from template: NoteTemplate,
        in folder: Folder?,
        context: ModelContext,
        now: Date
    ) -> Page {
        let page = addPage(
            titled: TemplateLibrary.title(from: template.titlePattern, now: now),
            in: folder,
            context: context
        )
        page.templateID = template.id
        page.body = template.body ?? TipTapDocument.emptyDocument
        page.plainText = template.body.flatMap(TipTapDocument.plainText(from:)) ?? ""

        // A weekly page is the week it covers; a transcript is the moment it records.
        switch template.id {
        case "weekly": page.periodStart = TemplateLibrary.monday(of: now)
        case "transcript": page.eventDate = now
        default: break
        }

        return page
    }
}
