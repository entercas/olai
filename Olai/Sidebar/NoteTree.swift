import Foundation
import OlaiCore
import SwiftData

/// Create, rename, move, and delete operations on the folder/page tree.
///
/// Everything here runs on the main actor against the view's `ModelContext`; autosave on
/// the container persists the changes.
@MainActor
enum NoteTree {
    // MARK: Create

    @discardableResult
    static func addFolder(named name: String = "New Folder", in parent: Folder?, context: ModelContext) -> Folder {
        let siblings = parent?.sortedChildren ?? rootFolders(context: context)
        let folder = Folder(
            name: name,
            sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1,
            parent: parent
        )
        context.insert(folder)
        return folder
    }

    @discardableResult
    static func addPage(titled title: String = "Untitled", in folder: Folder?, context: ModelContext) -> Page {
        let siblings = folder?.sortedPages ?? rootPages(context: context)
        let page = Page(
            title: title,
            body: TipTapDocument.emptyDocument,
            sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1,
            folder: folder
        )
        context.insert(page)
        return page
    }

    // MARK: Rename

    static func rename(_ folder: Folder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
    }

    static func rename(_ page: Page, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        page.title = trimmed
        page.updatedAt = Date()
    }

    // MARK: Move

    /// Moves a folder under `destination`, or to the top level when nil. Refuses a move
    /// into the folder's own subtree, which would orphan the branch.
    static func move(_ folder: Folder, to destination: Folder?) {
        guard destination?.id != folder.id else { return }
        if let destination, folder.contains(destination) { return }
        folder.parent = destination
    }

    static func move(_ page: Page, to destination: Folder?) {
        page.folder = destination
        page.updatedAt = Date()
    }

    static func canMove(_ folder: Folder, to destination: Folder?) -> Bool {
        folder.canBeMoved(to: destination)
    }

    // MARK: Archive and pin

    /// Archiving a folder takes its whole subtree with it, so the tree cannot show a
    /// live child under an archived parent.
    static func setArchived(_ archived: Bool, on folder: Folder) {
        folder.isArchived = archived
        folder.sortedChildren.forEach { setArchived(archived, on: $0) }
        folder.sortedPages.forEach { setArchived(archived, on: $0) }
    }

    static func setArchived(_ archived: Bool, on page: Page) {
        page.isArchived = archived
        page.updatedAt = Date()
    }

    static func togglePinned(_ page: Page) {
        page.isPinned.toggle()
        page.updatedAt = Date()
    }

    // MARK: Delete

    static func delete(_ folder: Folder, context: ModelContext) {
        context.delete(folder)
    }

    static func delete(_ page: Page, context: ModelContext) {
        context.delete(page)
    }

    // MARK: Queries

    static func rootFolders(context: ModelContext) -> [Folder] {
        let all = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        return all.filter { $0.parent == nil }.sorted(by: Folder.displayOrder)
    }

    static func rootPages(context: ModelContext) -> [Page] {
        let all = (try? context.fetch(FetchDescriptor<Page>())) ?? []
        return all.filter { $0.folder == nil }.sorted(by: Page.displayOrder)
    }

    /// Every folder in tree order, paired with its depth, for flat "move to" menus.
    static func flattened(_ roots: [Folder]) -> [(folder: Folder, depth: Int)] {
        var result: [(Folder, Int)] = []
        func walk(_ folders: [Folder], depth: Int) {
            for folder in folders where !folder.isArchived {
                result.append((folder, depth))
                walk(folder.sortedChildren, depth: depth + 1)
            }
        }
        walk(roots, depth: 0)
        return result.map { (folder: $0.0, depth: $0.1) }
    }
}
