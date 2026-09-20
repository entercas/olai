import OlaiCore
import SwiftData
import SwiftUI

/// The folder/page tree. Folders nest through recursive `DisclosureGroup`s whose
/// expansion is persisted; pages are leaves.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    let onNewFolder: () -> Void
    let onNewPage: () -> Void
    let onMove: (DraggedItem, Folder?) -> Bool
    let onRename: (TreeItem, Bool) -> Void
    let onDelete: (TreeItem) -> Void

    @Query private var allFolders: [Folder]
    @Query private var allPages: [Page]

    private var rootFolders: [Folder] {
        allFolders.filter { $0.parent == nil && !$0.isArchived }.sorted(by: Folder.displayOrder)
    }

    private var rootPages: [Page] {
        allPages.filter { $0.folder == nil && !$0.isArchived }.sorted(by: Page.displayOrder)
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(rootFolders) { folder in
                FolderDisclosure(
                    folder: folder,
                    allFolders: allFolders,
                    selection: $selection,
                    onMove: onMove,
                    onRename: onRename,
                    onDelete: onDelete
                )
            }
            ForEach(rootPages) { page in
                PageRow(
                    page: page,
                    allFolders: allFolders,
                    onRename: onRename,
                    onDelete: onDelete
                )
            }
        }
        .listStyle(.sidebar)
        // Separates the tree from the window's title bar, which the sidebar would
        // otherwise run straight into.
        .safeAreaInset(edge: .top, spacing: 0) {
            Divider()
        }
        .toolbar {
            // macOS: beside the sidebar's collapse button. iOS: the sidebar's own
            // navigation bar, which is where a collapsed split view shows actions.
            #if os(macOS)
            ToolbarItemGroup(placement: .primaryAction) {
                NewItemButtons(newFolder: onNewFolder, newPage: onNewPage)
            }
            #else
            ToolbarItemGroup(placement: .primaryAction) {
                NewItemButtons(newFolder: onNewFolder, newPage: onNewPage)
            }
            #endif
        }
        #if os(iOS)
        .navigationTitle("Olai")
        #endif
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
    let onMove: (DraggedItem, Folder?) -> Bool
    let onRename: (TreeItem, Bool) -> Void
    let onDelete: (TreeItem) -> Void

    @AppStorage private var isExpanded: Bool
    @State private var isDropTarget = false
    @Environment(\.modelContext) private var context

    init(
        folder: Folder,
        allFolders: [Folder],
        selection: Binding<SidebarSelection?>,
        onMove: @escaping (DraggedItem, Folder?) -> Bool,
        onRename: @escaping (TreeItem, Bool) -> Void,
        onDelete: @escaping (TreeItem) -> Void
    ) {
        _folder = Bindable(folder)
        self.allFolders = allFolders
        _selection = selection
        self.onMove = onMove
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
                    onMove: onMove,
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
            .contentShape(.rect)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.tint.opacity(isDropTarget ? 0.25 : 0))
                    .padding(.vertical, -2)
            )
            .contextMenu { menu }
            .draggable(DraggedItem(kind: .folder, id: folder.id))
            .dropDestination(for: DraggedItem.self) { items, _ in
                // A drop that lands on the folder it came from, or that would put a
                // folder inside its own subtree, is refused by onMove.
                items.reduce(false) { done, item in onMove(item, folder) || done }
            } isTargeted: { isDropTarget = $0 }
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
        .draggable(DraggedItem(kind: .page, id: page.id))
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
