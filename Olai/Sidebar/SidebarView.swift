import OlaiCore
import SwiftData
import SwiftUI

/// The folder/page tree. Folders nest through recursive `DisclosureGroup`s whose
/// expansion is persisted; pages are leaves. Searching replaces the tree with matches,
/// and archived items live in their own section at the bottom.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    let actions: TreeActions

    @Query private var allFolders: [Folder]
    @Query private var allPages: [Page]
    @State private var search = ""

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var rootFolders: [Folder] {
        allFolders.filter { $0.parent == nil && !$0.isArchived }.sorted(by: Folder.displayOrder)
    }

    private var rootPages: [Page] {
        allPages.filter { $0.folder == nil && !$0.isArchived }.sorted(by: Page.displayOrder)
    }

    /// Title and body, as the spec's search covers both.
    private var matches: [Page] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        return allPages
            .filter {
                $0.title.localizedStandardContains(needle)
                    || $0.plainText.localizedStandardContains(needle)
            }
            .sorted(by: Page.displayOrder)
    }

    /// Only the roots of archived subtrees: archiving cascades, so showing every
    /// archived folder would list a subtree's insides alongside it.
    private var archivedFolders: [Folder] {
        allFolders
            .filter { $0.isArchived && !($0.parent?.isArchived ?? false) }
            .sorted(by: Folder.displayOrder)
    }

    private var archivedPages: [Page] {
        allPages
            .filter { $0.isArchived && !($0.folder?.isArchived ?? false) }
            .sorted(by: Page.displayOrder)
    }

    var body: some View {
        List(selection: $selection) {
            if isSearching {
                Section("Results") {
                    if matches.isEmpty {
                        Text("No pages match “\(search)”")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matches) { page in
                        PageRow(page: page, allFolders: allFolders, actions: actions)
                    }
                }
            } else {
                ForEach(rootFolders) { folder in
                    FolderDisclosure(
                        folder: folder,
                        allFolders: allFolders,
                        selection: $selection,
                        actions: actions
                    )
                }
                ForEach(rootPages) { page in
                    PageRow(page: page, allFolders: allFolders, actions: actions)
                }

                if !archivedFolders.isEmpty || !archivedPages.isEmpty {
                    Section("Archive") {
                        ForEach(archivedFolders) { folder in
                            FolderDisclosure(
                                folder: folder,
                                allFolders: allFolders,
                                selection: $selection,
                                actions: actions
                            )
                        }
                        ForEach(archivedPages) { page in
                            PageRow(page: page, allFolders: allFolders, actions: actions)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, prompt: "Search pages")
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
                NewItemButtons(actions: actions)
            }
            #else
            ToolbarItemGroup(placement: .primaryAction) {
                NewItemButtons(actions: actions)
            }
            #endif
        }
        #if os(iOS)
        .navigationTitle("Olai")
        #endif
    }
}

/// A folder or a page, for the flows that treat them alike.
enum TreeItem: Hashable {
    case folder(Folder)
    case page(Page)
}

/// What the sidebar can ask for. The work itself lives in `RootView`, which owns the
/// model context and the selection.
@MainActor
struct TreeActions {
    var newFolder: () -> Void
    var newPage: () -> Void
    var newFromTemplate: (NoteTemplate) -> Void
    var addPage: (Folder) -> Void
    var addSubfolder: (Folder) -> Void
    var addFromTemplate: (NoteTemplate, Folder) -> Void
    var importTranscript: () -> Void
    var move: (DraggedItem, Folder?) -> Bool
    var rename: (TreeItem, Bool) -> Void
    var setArchived: (TreeItem, Bool) -> Void
    var togglePinned: (Page) -> Void
    var delete: (TreeItem) -> Void
}

// MARK: - Rows

private struct FolderDisclosure: View {
    @Bindable var folder: Folder
    let allFolders: [Folder]
    @Binding var selection: SidebarSelection?
    let actions: TreeActions

    @AppStorage private var isExpanded: Bool
    @State private var isDropTarget = false

    init(
        folder: Folder,
        allFolders: [Folder],
        selection: Binding<SidebarSelection?>,
        actions: TreeActions
    ) {
        _folder = Bindable(folder)
        self.allFolders = allFolders
        _selection = selection
        self.actions = actions
        _isExpanded = AppStorage(wrappedValue: false, SidebarExpansion.key(for: folder.id))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(folder.sortedChildren.filter { $0.isArchived == folder.isArchived }) { child in
                FolderDisclosure(
                    folder: child,
                    allFolders: allFolders,
                    selection: $selection,
                    actions: actions
                )
            }
            ForEach(folder.sortedPages.filter { $0.isArchived == folder.isArchived }) { page in
                PageRow(page: page, allFolders: allFolders, actions: actions)
            }
        } label: {
            // The menu hangs off the label, not the DisclosureGroup: attached to the
            // group it would also cover every child row inside it.
            HStack(spacing: 4) {
                Label(folder.name, systemImage: folder.isArchived ? "folder.badge.minus" : "folder")
                    .lineLimit(1)
                Spacer(minLength: 2)
                if !folder.isArchived { addMenu }
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
                // folder inside its own subtree, is refused by the move itself.
                items.reduce(false) { done, item in actions.move(item, folder) || done }
            } isTargeted: { isDropTarget = $0 }
        }
        .tag(SidebarSelection.folder(folder.id))
    }

    /// The row's own "+": creates inside *this* folder, whatever is selected elsewhere.
    private var addMenu: some View {
        Menu {
            Button("New Page", systemImage: "square.and.pencil") { actions.addPage(folder) }
            Button("New Subfolder", systemImage: "folder.badge.plus") { actions.addSubfolder(folder) }
            Divider()
            templateMenu
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

    private var templateMenu: some View {
        Menu("New from Template") {
            ForEach(TemplateStore.all) { template in
                Button(template.name) { actions.addFromTemplate(template, folder) }
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Group {
            if folder.isArchived {
                Button("Unarchive") { actions.setArchived(.folder(folder), false) }
            } else {
                Button("New Page") { actions.addPage(folder) }
                Button("New Subfolder") { actions.addSubfolder(folder) }
                templateMenu
                Divider()
                Button("Rename…") { actions.rename(.folder(folder), false) }
                MoveToMenu(allFolders: allFolders) { destination in
                    _ = actions.move(DraggedItem(kind: .folder, id: folder.id), destination)
                } isEnabled: { destination in
                    folder.canBeMoved(to: destination)
                }
                Button("Archive") { actions.setArchived(.folder(folder), true) }
            }
            Divider()
            Button("Delete…", role: .destructive) { actions.delete(.folder(folder)) }
        }
    }
}

private struct PageRow: View {
    @Bindable var page: Page
    let allFolders: [Folder]
    let actions: TreeActions

    var body: some View {
        Label {
            Text(page.title.isEmpty ? "Untitled" : page.title)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
        }
        .tag(SidebarSelection.page(page.id))
        .draggable(DraggedItem(kind: .page, id: page.id))
        .contextMenu {
            if page.isArchived {
                Button("Unarchive") { actions.setArchived(.page(page), false) }
            } else {
                Button("Rename…") { actions.rename(.page(page), false) }
                MoveToMenu(allFolders: allFolders) { destination in
                    _ = actions.move(DraggedItem(kind: .page, id: page.id), destination)
                } isEnabled: { destination in
                    destination?.id != page.folder?.id
                }
                Button(page.isPinned ? "Unpin" : "Pin") { actions.togglePinned(page) }
                Button("Archive") { actions.setArchived(.page(page), true) }
            }
            Divider()
            Button("Delete…", role: .destructive) { actions.delete(.page(page)) }
        }
    }

    private var icon: String {
        if page.isArchived { return "doc.badge.ellipsis" }
        return page.isPinned ? "pin.fill" : "doc.text"
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
