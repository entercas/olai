import OlaiCore
import SwiftData
import SwiftUI

/// The folder/page tree. Folders nest through recursive `DisclosureGroup`s whose
/// expansion is persisted; pages are leaves.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?

    @Environment(\.modelContext) private var context
    @Query private var allFolders: [Folder]
    @Query private var allPages: [Page]

    @State private var renameTarget: TreeItem?
    @State private var renameText: String = ""
    @State private var deleteTarget: TreeItem?

    private var rootFolders: [Folder] {
        allFolders.filter { $0.parent == nil && !$0.isArchived }.sorted(by: Folder.displayOrder)
    }

    private var rootPages: [Page] {
        allPages.filter { $0.folder == nil && !$0.isArchived }.sorted(by: Page.displayOrder)
    }

    /// The folder new items land in: the selected folder, or the folder holding the
    /// selected page, or the top level.
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

    var body: some View {
        List(selection: $selection) {
            ForEach(rootFolders) { folder in
                FolderDisclosure(
                    folder: folder,
                    allFolders: allFolders,
                    selection: $selection,
                    onRename: beginRename,
                    onDelete: { deleteTarget = $0 }
                )
            }
            ForEach(rootPages) { page in
                PageRow(
                    page: page,
                    allFolders: allFolders,
                    onRename: beginRename,
                    onDelete: { deleteTarget = $0 }
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Olai")
        #if os(macOS)
        // A sidebar's toolbar area is only as wide as the sidebar, so a second button
        // there is pushed into the window's overflow menu however wide the window is.
        // A footer keeps both in reach and reads like Finder's.
        .safeAreaInset(edge: .bottom, spacing: 0) { newItemBar }
        #else
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { newFolder() } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .help("New folder")

                Button { newPage() } label: {
                    Label("New Page", systemImage: "square.and.pencil")
                }
                .help("New page")
            }
        }
        #endif
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

    #if os(macOS)
    private var newItemBar: some View {
        HStack(spacing: 2) {
            Button { newFolder() } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .help("New folder")

            Button { newPage() } label: {
                Label("New Page", systemImage: "square.and.pencil")
            }
            .help("New page")

            Spacer(minLength: 0)
        }
        .buttonStyle(.accessoryBar)
        .font(.subheadline)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.bar)
    }
    #endif

    // MARK: Actions

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
    }

    // MARK: Presentation bindings

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

/// A folder or a page, for the rename/delete flows that treat them alike.
enum TreeItem: Hashable {
    case folder(Folder)
    case page(Page)
}

// MARK: - Rows

private struct FolderDisclosure: View {
    @Bindable var folder: Folder
    let allFolders: [Folder]
    @Binding var selection: SidebarSelection?
    let onRename: (TreeItem, Bool) -> Void
    let onDelete: (TreeItem) -> Void

    @AppStorage private var isExpanded: Bool
    @Environment(\.modelContext) private var context

    init(
        folder: Folder,
        allFolders: [Folder],
        selection: Binding<SidebarSelection?>,
        onRename: @escaping (TreeItem, Bool) -> Void,
        onDelete: @escaping (TreeItem) -> Void
    ) {
        _folder = Bindable(folder)
        self.allFolders = allFolders
        _selection = selection
        self.onRename = onRename
        self.onDelete = onDelete
        _isExpanded = AppStorage(wrappedValue: false, SidebarExpansion.key(for: folder.id))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(folder.sortedChildren.filter { !$0.isArchived }) { child in
                FolderDisclosure(
                    folder: child,
                    allFolders: allFolders,
                    selection: $selection,
                    onRename: onRename,
                    onDelete: onDelete
                )
            }
            ForEach(folder.sortedPages.filter { !$0.isArchived }) { page in
                PageRow(page: page, allFolders: allFolders, onRename: onRename, onDelete: onDelete)
            }
        } label: {
            // The menu hangs off the label, not the DisclosureGroup: attached to the
            // group it would also cover every child row inside it.
            HStack(spacing: 4) {
                Label(folder.name, systemImage: "folder")
                    .lineLimit(1)
                Spacer(minLength: 2)
                addMenu
            }
            .contextMenu { menu }
        }
        .tag(SidebarSelection.folder(folder.id))
    }

    /// The row's own "+": creates inside *this* folder, whatever is selected elsewhere.
    private var addMenu: some View {
        Menu {
            Button("New Page", systemImage: "square.and.pencil") { addPage() }
            Button("New Subfolder", systemImage: "folder.badge.plus") { addSubfolder() }
        } label: {
            Image(systemName: "plus")
                .font(.caption.weight(.semibold))
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Add inside “\(folder.name)”")
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }

    private func addPage() {
        let page = NoteTree.addPage(in: folder, context: context)
        isExpanded = true
        selection = .page(page.id)
    }

    private func addSubfolder() {
        let child = NoteTree.addFolder(in: folder, context: context)
        isExpanded = true
        onRename(.folder(child), true)
    }

    @ViewBuilder
    private var menu: some View {
        Group {
            Button("New Page") { addPage() }
            Button("New Subfolder") { addSubfolder() }
            Divider()
            Button("Rename…") { onRename(.folder(folder), false) }
            MoveToMenu(allFolders: allFolders) { destination in
                guard NoteTree.canMove(folder, to: destination) else { return }
                NoteTree.move(folder, to: destination)
            } isEnabled: { destination in
                NoteTree.canMove(folder, to: destination)
            }
            Divider()
            Button("Delete…", role: .destructive) { onDelete(.folder(folder)) }
        }
    }
}

private struct PageRow: View {
    @Bindable var page: Page
    let allFolders: [Folder]
    let onRename: (TreeItem, Bool) -> Void
    let onDelete: (TreeItem) -> Void

    var body: some View {
        Label {
            Text(page.title.isEmpty ? "Untitled" : page.title)
                .lineLimit(1)
        } icon: {
            Image(systemName: page.isPinned ? "pin.fill" : "doc.text")
        }
        .tag(SidebarSelection.page(page.id))
        .contextMenu {
            Button("Rename…") { onRename(.page(page), false) }
            MoveToMenu(allFolders: allFolders) { destination in
                NoteTree.move(page, to: destination)
            } isEnabled: { destination in
                destination?.id != page.folder?.id
            }
            Divider()
            Button("Delete…", role: .destructive) { onDelete(.page(page)) }
        }
    }
}

/// "Move to" submenu listing the top level and every folder, indented by depth.
private struct MoveToMenu: View {
    let allFolders: [Folder]
    let move: (Folder?) -> Void
    let isEnabled: (Folder?) -> Bool

    var body: some View {
        Menu("Move to") {
            Button("Top Level") { move(nil) }
                .disabled(!isEnabled(nil))
            Divider()
            ForEach(NoteTree.flattened(roots), id: \.folder.id) { entry in
                Button(String(repeating: "    ", count: entry.depth) + entry.folder.name) {
                    move(entry.folder)
                }
                .disabled(!isEnabled(entry.folder))
            }
        }
    }

    private var roots: [Folder] {
        allFolders.filter { $0.parent == nil && !$0.isArchived }.sorted(by: Folder.displayOrder)
    }
}
