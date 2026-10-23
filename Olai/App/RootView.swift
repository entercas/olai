import OlaiCore
import SwiftData
import SwiftUI

/// Owns the window's state: what is selected in the sidebar, which pages are open, and
/// the create / rename / delete flows.
///
/// Two columns, as in Obsidian: the tree of folders and pages, then the open pages as
/// tabs. It was three -- folders, a list of the selected folder's pages, then the page --
/// and that middle list was where most of the trouble was.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scheduleMirrorExport) private var scheduleMirrorExport
    @Environment(\.mirrorRoot) private var mirrorRoot
    @Query private var allFolders: [Folder]
    @Query private var allPages: [Page]

    @Environment(LayoutState.self) private var layout
    @State private var selection: TreeSelection?
    @State private var revealRequest: TreeSelection?
    @State private var expansion = TreeExpansion()
    @State private var tabs = OpenTabs()
    @State private var renameTarget: TreeItem?
    @State private var renameText: String = ""
    @State private var deleteTarget: TreeItem?
    @State private var isImportingTranscript = false
    @State private var isImportingMarkdown = false
    @State private var importError: String?
    @State private var importSummary: String?

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { layout.columnVisibility },
            set: { visibility in
                // Two-way, so the split view's own sidebar button and a dragged divider
                // still register -- but only when a person did it. The split view also
                // writes here by itself, restoring state after a force-quit or folding
                // the sidebar away to fit a narrow window, and since the preference is
                // saved, one such write left the sidebar hidden on every launch after.
                guard LayoutState.isUserInitiated else { return }
                layout.showFolders = (visibility != .detailOnly)
            }
        )) {
            SidebarView(
                selection: $selection,
                revealRequest: $revealRequest,
                expansion: expansion,
                actions: actions
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
        } detail: {
            EditorPane(tabs: tabs, selection: $selection)
                // The binder tabs stand in for the sidebar while it is hidden.
                .safeAreaInset(edge: .leading, spacing: 0) {
                    if !layout.showFolders { rail }
                }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 440)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
        .navigationTitle("Olai")
        .focusedSceneValue(\.treeActions, actions)
        // A page that is deleted must not leave a tab pointing at nothing.
        .onChange(of: pageIDs) { _, ids in
            tabs.keepOnly(ids)
        }
        .fileImporter(
            isPresented: $isImportingTranscript,
            allowedContentTypes: TranscriptImport.readableTypes
        ) { result in
            do {
                guard case let .success(url) = result else { return }
                let page = try TranscriptImport.importTranscript(
                    from: url,
                    into: insertionFolder,
                    context: context
                )
                reveal(page)
                tabs.open(page.id)
                scheduleMirrorExport()
            } catch {
                importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isImportingMarkdown,
            allowedContentTypes: MarkdownFolderImport.readableTypes
        ) { result in
            do {
                guard case let .success(url) = result else { return }
                let summary = try MarkdownFolderImport.importFolder(
                    at: url,
                    into: insertionFolder,
                    context: context,
                    mirrorRoot: mirrorRoot
                )
                var message = "Imported \(summary.sentence)."
                if !summary.skipped.isEmpty {
                    message += "\n\nCould not read \(summary.skipped.count) file(s): "
                        + summary.skipped.prefix(5).joined(separator: ", ")
                        + (summary.skipped.count > 5 ? "…" : "")
                }
                importSummary = message
                scheduleMirrorExport()
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("Import finished", isPresented: importSummaryIsPresented) {
            Button("OK", role: .cancel) { importSummary = nil }
        } message: {
            Text(importSummary ?? "")
        }
        .alert("Could not read that file", isPresented: importErrorIsPresented) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Rename", isPresented: renameIsPresented) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") { commitRename() }
        }
        .confirmationDialog(
            deleteQuestion,
            isPresented: deleteIsPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            if case .folder = deleteTarget {
                Text("Its subfolders and pages are deleted too.")
            }
        }
    }

    private var pageIDs: Set<UUID> {
        Set(allPages.map(\.id))
    }

    private var rail: some View {
        FolderTagRail(
            folders: allFolders.filter { $0.parent == nil && !$0.isArchived }
                .sorted(by: Folder.displayOrder),
            selectedFolder: {
                if case let .folder(id) = selection { return id }
                return nil
            }()
        ) { folder in
            layout.showFolders = true
            selection = .folder(folder.id)
            expansion.reveal(folder)
            revealRequest = .folder(folder.id)
        }
    }

    private var actions: TreeActions {
        // Each action is wrapped so the mirror hears about it; forgetting one is the
        // only way the export can fall behind.
        func mirrored(_ work: @escaping () -> Void) -> () -> Void {
            { work(); scheduleMirrorExport() }
        }
        func mirrored<T>(_ work: @escaping (T) -> Void) -> (T) -> Void {
            { work($0); scheduleMirrorExport() }
        }
        func mirrored<T, U>(_ work: @escaping (T, U) -> Void) -> (T, U) -> Void {
            { work($0, $1); scheduleMirrorExport() }
        }

        return TreeActions(
            newFolder: mirrored { makeFolder(in: insertionFolder) },
            newPage: mirrored { makePage(in: insertionFolder) },
            newFromTemplate: mirrored { create(from: $0, in: insertionFolder) },
            addPage: mirrored { folder in makePage(in: folder) },
            addSubfolder: mirrored { folder in makeFolder(in: folder) },
            addFromTemplate: mirrored { template, folder in create(from: template, in: folder) },
            importTranscript: { isImportingTranscript = true },
            importMarkdown: { isImportingMarkdown = true },
            open: { id, newTab in
                if newTab { tabs.open(id) } else { tabs.show(id) }
            },
            move: { item, destination in
                let moved = move(item, into: destination)
                if moved { scheduleMirrorExport() }
                return moved
            },
            rename: beginRename,
            setArchived: mirrored(setArchived),
            togglePinned: mirrored(NoteTree.togglePinned),
            // A tag changes nothing the mirror writes, but the store still has to save.
            tagChanged: { try? context.save() },
            delete: { deleteTarget = $0 }
        )
    }

    // MARK: Creating

    /// Where New Page and New Folder put things, as in Obsidian: inside the selected
    /// folder, or beside the selected page, or at the top level with nothing selected.
    /// The sidebar shows the selection, so the place is never a surprise -- and the new
    /// row appears there, selected.
    private var insertionFolder: Folder? {
        switch selection {
        case let .folder(id):
            return allFolders.first { $0.id == id && !$0.isArchived }
        case let .page(id):
            guard let folder = allPages.first(where: { $0.id == id })?.folder, !folder.isArchived else { return nil }
            return folder
        case nil:
            return nil
        }
    }

    /// Makes a page, shows it in the tree where it was made, opens it in a new tab and
    /// puts the cursor in its title.
    private func makePage(in folder: Folder?) {
        let page = NoteTree.addPage(in: folder, context: context)
        try? context.save()
        reveal(page)
        tabs.titleFocusRequest = page.id
        tabs.open(page.id)
    }

    private func makeFolder(in parent: Folder?) {
        let folder = NoteTree.addFolder(in: parent, context: context)
        try? context.save()
        expansion.reveal(parent)
        selection = .folder(folder.id)
        revealRequest = .folder(folder.id)
        beginRename(.folder(folder), startingEmpty: true)
    }

    private func reveal(_ page: Page) {
        expansion.reveal(page.folder)
        selection = .page(page.id)
        revealRequest = .page(page.id)
    }

    /// Applies a drag: moves the dragged folder or page into `destination`. Returns
    /// false for a move that would be a no-op or would put a folder inside itself.
    private func move(_ item: DraggedItem, into destination: Folder?) -> Bool {
        switch item.kind {
        case .folder:
            guard
                let folder = allFolders.first(where: { $0.id == item.id }),
                NoteTree.canMove(folder, to: destination)
            else { return false }
            NoteTree.move(folder, to: destination)

        case .page:
            guard
                let page = allPages.first(where: { $0.id == item.id }),
                page.folder?.id != destination?.id
            else { return false }
            NoteTree.move(page, to: destination)
        }

        expansion.reveal(destination)
        return true
    }

    /// Builds whatever a template describes and opens the page it produced.
    private func create(from template: NoteTemplate, in parent: Folder?) {
        guard let page = NoteTree.create(from: template, in: parent, context: context) else { return }
        try? context.save()
        reveal(page)
        tabs.open(page.id)
    }

    /// Archiving closes the page rather than leaving a tab on something the list no
    /// longer shows.
    private func setArchived(_ item: TreeItem, _ archived: Bool) {
        switch item {
        case let .folder(folder):
            if archived {
                if selection == .folder(folder.id) { selection = nil }
                closeTabs(under: folder)
            }
            NoteTree.setArchived(archived, on: folder)
        case let .page(page):
            if archived { tabs.close(page.id) }
            NoteTree.setArchived(archived, on: page)
        }
    }

    // MARK: Renaming and deleting

    private func beginRename(_ item: TreeItem, startingEmpty: Bool = false) {
        switch item {
        case let .folder(folder): renameText = startingEmpty ? "" : folder.name
        case let .page(page): renameText = startingEmpty ? "" : page.title
        }
        renameTarget = item
    }

    private func commitRename() {
        switch renameTarget {
        case let .folder(folder): NoteTree.rename(folder, to: renameText)
        case let .page(page): NoteTree.rename(page, to: renameText)
        case nil: break
        }
        renameTarget = nil
        scheduleMirrorExport()
    }

    private func commitDelete() {
        switch deleteTarget {
        case let .folder(folder):
            if selection == .folder(folder.id) { selection = nil }
            closeTabs(under: folder)
            NoteTree.delete(folder, context: context)
        case let .page(page):
            tabs.close(page.id)
            NoteTree.delete(page, context: context)
        case nil:
            break
        }
        deleteTarget = nil
        scheduleMirrorExport()
    }

    /// Every page in the folder and its subfolders.
    private func closeTabs(under folder: Folder) {
        for page in allPages where page.folder.map({ folder.contains($0) }) ?? false {
            tabs.close(page.id)
        }
    }

    private var importSummaryIsPresented: Binding<Bool> {
        Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })
    }

    private var importErrorIsPresented: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    private var renameIsPresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deleteIsPresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var deleteQuestion: String {
        switch deleteTarget {
        case let .folder(folder): "Delete “\(folder.name)”?"
        case let .page(page): "Delete “\(page.title)”?"
        case nil: "Delete?"
        }
    }
}
