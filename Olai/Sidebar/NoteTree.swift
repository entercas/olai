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
        let siblings = allFolders(context: context).filter { $0.parent?.id == parent?.id }
        let folder = Folder(name: name, sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1)
        // Inserted before it is parented. A relationship set on an object the context
        // does not yet hold can leave the other side -- the parent's list of children --
        // without it until the next save.
        context.insert(folder)
        folder.parent = parent
        return folder
    }

    /// A new page goes at the bottom of its folder. Its title starts empty, with
    /// "Untitled" shown in its place, so typing a name does not first mean deleting one.
    @discardableResult
    static func addPage(titled title: String = "", in folder: Folder?, context: ModelContext) -> Page {
        let siblings = allPages(context: context).filter { $0.folder?.id == folder?.id }
        let page = Page(
            title: title,
            body: TipTapDocument.emptyDocument,
            sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(page)
        page.folder = folder
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
        if let context = folder.modelContext {
            let siblings = allFolders(context: context).filter { $0.parent?.id == destination?.id && $0.id != folder.id }
            folder.sortOrder = (siblings.map(\.sortOrder).max() ?? -1) + 1
        }
        folder.parent = destination
    }

    /// A moved page goes to the bottom of its new folder, as a new one does. Keeping its
    /// old position put it somewhere in the middle, wherever that number fell.
    static func move(_ page: Page, to destination: Folder?) {
        if let context = page.modelContext {
            let siblings = allPages(context: context).filter { $0.folder?.id == destination?.id && $0.id != page.id }
            page.sortOrder = (siblings.map(\.sortOrder).max() ?? -1) + 1
        }
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
        allFolders(context: context).filter { $0.parent == nil }.sorted(by: Folder.displayOrder)
    }

    static func rootPages(context: ModelContext) -> [Page] {
        allPages(context: context).filter { $0.folder == nil }.sorted(by: Page.displayOrder)
    }

    private static func allFolders(context: ModelContext) -> [Folder] {
        (try? context.fetch(FetchDescriptor<Folder>())) ?? []
    }

    private static func allPages(context: ModelContext) -> [Page] {
        (try? context.fetch(FetchDescriptor<Page>())) ?? []
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
