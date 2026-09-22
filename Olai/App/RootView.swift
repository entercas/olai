import OlaiCore
import SwiftData
import SwiftUI

/// What the sidebar has selected. Folders and pages share the list, so the selection
/// carries the kind alongside the model's stable `UUID`.
enum SidebarSelection: Hashable {
    case folder(UUID)
    case page(UUID)
}

/// Owns the tree-level state: what is selected, and the create / rename / delete flows.
///
/// The toolbar hangs off the split view rather than the sidebar on purpose. A sidebar's
/// toolbar region is only as wide as the sidebar, so items placed there are pushed into
/// the window's overflow menu; from here they get the width of the whole window.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scheduleMirrorExport) private var scheduleMirrorExport
    @Environment(\.mirrorRoot) private var mirrorRoot
    @Query private var allFolders: [Folder]
    @Query private var allPages: [Page]

    @State private var selection: SidebarSelection?
    @State private var renameTarget: TreeItem?
    @State private var renameText: String = ""
    @State private var deleteTarget: TreeItem?
    @State private var isImportingTranscript = false
    @State private var isImportingMarkdown = false
    @State private var importError: String?
    @State private var importSummary: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, actions: actions)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 340)
        } detail: {
            DetailView(selection: selection)
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 440)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
        // The window's own title, so it spans the whole title bar rather than belonging
        // to the detail pane.
        .navigationTitle("Olai")
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
                selection = .page(page.id)
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
        .alert("Could not read that transcript", isPresented: importErrorIsPresented) {
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
                selection = .page(page.id)
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

    /// Where new items land: the selected folder, the folder holding the selected page,
    /// or the top level.
    private var insertionFolder: Folder? {
        switch selection {
        case let .folder(id):
            return allFolders.first { $0.id == id }
        case let .page(id):
            return allPages.first { $0.id == id }?.folder
        case nil:
            return nil
        }
    }

    private func newPage() {
        let page = NoteTree.addPage(in: insertionFolder, context: context)
        if let folder = insertionFolder {
            SidebarExpansion.setExpanded(true, for: folder.id)
        }
        selection = .page(page.id)
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
        }
        selection = .page(page.id)
    }

    private func setArchived(_ item: TreeItem, _ archived: Bool) {
        switch item {
        case let .folder(folder):
            if archived, selection == .folder(folder.id) { selection = nil }
            NoteTree.setArchived(archived, on: folder)
        case let .page(page):
            if archived, selection == .page(page.id) { selection = nil }
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
            NoteTree.delete(folder, context: context)
        case let .page(page):
            if selection == .page(page.id) { selection = nil }
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

/// Resolves the selection to a page editor, a folder summary, or a placeholder.
private struct DetailView: View {
    let selection: SidebarSelection?

    @Query private var pages: [Page]
    @Query private var folders: [Folder]

    var body: some View {
        switch selection {
        case let .page(id):
            if let page = pages.first(where: { $0.id == id }) {
                PageEditorView(page: page)
                    .id(page.id)
            } else {
                ContentUnavailableView("Page not found", systemImage: "doc")
            }
        case let .folder(id):
            if let folder = folders.first(where: { $0.id == id }) {
                FolderDetailView(folder: folder)
                    .id(folder.id)
            } else {
                ContentUnavailableView("Folder not found", systemImage: "folder")
            }
        case nil:
            ContentUnavailableView(
                "No page selected",
                systemImage: "doc.text",
                description: Text("Pick a page in the sidebar, or make one with New Page.")
            )
        }
    }
}

/// Stand-in detail for a selected folder: what it holds.
private struct FolderDetailView: View {
    @Bindable var folder: Folder

    var body: some View {
        let pages = folder.sortedPages.filter { !$0.isArchived }
        let subfolders = folder.sortedChildren.filter { !$0.isArchived }

        VStack(alignment: .leading, spacing: 6) {
            Text(folder.name)
                .font(.title2.weight(.semibold))
            Text("\(subfolders.count) folder\(subfolders.count == 1 ? "" : "s") · \(pages.count) page\(pages.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, EditorMetrics.gutter)
        .padding(.top, 20)
        .frame(maxWidth: EditorMetrics.columnWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
        .navigationTitle(folder.name)
        #endif
    }
}

/// The creation buttons, shown in the window toolbar on macOS and in the sidebar's
/// navigation bar on iPhone.
struct NewItemButtons: View {
    let actions: TreeActions

    var body: some View {
        Button(action: actions.newFolder) {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        .help("New folder")

        // Click for a blank page; the menu holds the templates. A fourth toolbar item
        // does not fit beside the sidebar's collapse button -- it lands in the overflow
        // menu, where nobody finds it.
        Menu {
            ForEach(TemplateStore.all) { template in
                Button(template.name) { actions.newFromTemplate(template) }
            }
            Divider()
            Button("Import Transcript…", systemImage: "waveform") { actions.importTranscript() }
            Button("Import Markdown Folder…", systemImage: "folder.badge.plus") { actions.importMarkdown() }
        } label: {
            Label("New Page", systemImage: "square.and.pencil")
        } primaryAction: {
            actions.newPage()
        }
        .help("New page — hold for templates")
    }
}
