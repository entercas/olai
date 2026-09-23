import OlaiCore
import SwiftData
import SwiftUI

/// Owns the tree-level state: what is selected, which pages are open, and the create /
/// rename / delete flows.
///
/// Three columns rather than two: folders, the pages inside them, then the page itself.
/// With everything in one tree, a library of any size spent most of its height on the
/// pages of folders nobody was looking at, and moving between two folders meant
/// collapsing one to find the other.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scheduleMirrorExport) private var scheduleMirrorExport
    @Environment(\.mirrorRoot) private var mirrorRoot
    @Query private var allFolders: [Folder]
    @Query private var allPages: [Page]

    @State private var scope: NotebookScope? = .allPages
    @State private var selectedPage: UUID?
    @State private var tabs = OpenTabs()
    @State private var renameTarget: TreeItem?
    @State private var renameText: String = ""
    @State private var deleteTarget: TreeItem?
    @State private var isImportingTranscript = false
    @State private var isImportingMarkdown = false
    @State private var importError: String?
    @State private var importSummary: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(scope: $scope, actions: actions)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 300)
        } content: {
            PageListView(scope: scope, openPage: $selectedPage, actions: actions)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 380)
        } detail: {
            DetailView(tabs: tabs)
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 440)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
        // The window's own title, so it spans the whole title bar rather than belonging
        // to the detail pane.
        .navigationTitle("Olai")
        // Selecting in the page list opens a tab; the tab bar is what decides which page
        // the editor shows, so the two are kept in step in both directions.
        .onChange(of: selectedPage) { _, new in
            if let new { tabs.open(new) }
        }
        .onChange(of: tabs.active) { _, new in
            if selectedPage != new { selectedPage = new }
        }
        // A page that is deleted, or archived out of the list, must not leave a tab
        // pointing at nothing.
        .onChange(of: allPages.map(\.id)) { _, ids in
            tabs.keepOnly(Set(ids))
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
            newFolder: mirrored(newFolder),
            newPage: mirrored(newPage),
            newFromTemplate: mirrored { create(from: $0, in: insertionFolder) },
            addPage: mirrored { folder in
                let page = NoteTree.addPage(in: folder, context: context)
                SidebarExpansion.setExpanded(true, for: folder.id)
                scope = .folder(folder.id)
                tabs.open(page.id)
            },
            addSubfolder: mirrored { folder in
                let child = NoteTree.addFolder(in: folder, context: context)
                SidebarExpansion.setExpanded(true, for: folder.id)
                beginRename(.folder(child), startingEmpty: true)
            },
            addFromTemplate: mirrored { template, folder in create(from: template, in: folder) },
            importTranscript: { isImportingTranscript = true },
            importMarkdown: { isImportingMarkdown = true },
            move: { item, destination in
                let moved = move(item, into: destination)
                if moved { scheduleMirrorExport() }
                return moved
            },
            rename: beginRename,
            setArchived: mirrored(setArchived),
            togglePinned: mirrored(NoteTree.togglePinned),
            delete: { deleteTarget = $0 }
        )
    }

    // MARK: Creating

    /// Where new items land: the folder the notebook column has selected, else the
    /// folder holding the page in front, else the top level.
    private var insertionFolder: Folder? {
        if case let .folder(id) = scope {
            return allFolders.first { $0.id == id }
        }
        return tabs.active.flatMap { active in allPages.first { $0.id == active }?.folder }
    }

    private func newPage() {
        let page = NoteTree.addPage(in: insertionFolder, context: context)
        if let folder = insertionFolder {
            SidebarExpansion.setExpanded(true, for: folder.id)
        }
        tabs.open(page.id)
    }

    /// Creates a folder and asks for its name straight away. The selection is left alone:
    /// on iPhone, selecting it would push to the detail column and take the prompt with it.
    private func newFolder() {
        let folder = NoteTree.addFolder(in: insertionFolder, context: context)
        if let parent = insertionFolder {
            SidebarExpansion.setExpanded(true, for: parent.id)
        }
        beginRename(.folder(folder), startingEmpty: true)
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

        if let destination {
            SidebarExpansion.setExpanded(true, for: destination.id)
        }
        return true
    }

    /// Builds whatever a template describes and opens the page it produced.
    private func create(from template: NoteTemplate, in parent: Folder?) {
        if let parent {
            SidebarExpansion.setExpanded(true, for: parent.id)
        }
        guard let page = NoteTree.create(from: template, in: parent, context: context) else { return }
        if let folder = page.folder {
            SidebarExpansion.setExpanded(true, for: folder.id)
            scope = .folder(folder.id)
        }
        tabs.open(page.id)
    }

    /// Archiving closes the page rather than leaving a tab on something the list no
    /// longer shows.
    private func setArchived(_ item: TreeItem, _ archived: Bool) {
        switch item {
        case let .folder(folder):
            if archived {
                if scope == .folder(folder.id) { scope = .allPages }
                folder.sortedPages.forEach { tabs.close($0.id) }
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
            if scope == .folder(folder.id) { scope = .allPages }
            folder.sortedPages.forEach { tabs.close($0.id) }
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

/// The detail column: the open pages as tabs, and the one in front below them.
private struct DetailView: View {
    let tabs: OpenTabs

    @Query private var pages: [Page]

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBar(tabs: tabs, pages: pages)

            if let active = tabs.active, let page = pages.first(where: { $0.id == active }) {
                PageEditorView(page: page)
                    .id(page.id)
            } else {
                ContentUnavailableView(
                    "No page open",
                    systemImage: "doc.text",
                    description: Text("Pick a page in the list, or make one with New Page.")
                )
            }
        }
    }
}

/// New Page, with the templates and the importers behind it.
///
/// Click for a blank page; hold for the rest. A separate toolbar item for each template
/// would not fit beside a column this narrow -- they land in the overflow menu, where
/// nobody finds them.
struct NewPageButton: View {
    let actions: TreeActions
    let folder: Folder?

    var body: some View {
        Menu {
            ForEach(TemplateStore.all) { template in
                Button(template.name) {
                    if let folder {
                        actions.addFromTemplate(template, folder)
                    } else {
                        actions.newFromTemplate(template)
                    }
                }
            }
            Divider()
            Button("Import Transcript…", systemImage: "waveform") { actions.importTranscript() }
            Button("Import Markdown Folder…", systemImage: "folder.badge.plus") { actions.importMarkdown() }
        } label: {
            Label("New Page", systemImage: "square.and.pencil")
        } primaryAction: {
            if let folder { actions.addPage(folder) } else { actions.newPage() }
        }
        .help(folder.map { "New page in “\($0.name)” — hold for templates" } ?? "New page — hold for templates")
    }
}
