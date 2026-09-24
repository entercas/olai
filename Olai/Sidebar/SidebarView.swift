import OlaiCore
import SwiftData
import SwiftUI

/// What the notebook column has selected, and therefore which pages the middle column
/// lists. Folders are held by id rather than by object so the selection survives the
/// folder being re-fetched.
enum NotebookScope: Hashable {
    case allPages
    case folder(UUID)
    case archive
}

/// The notebook column: folders only.
///
/// Pages used to live in here too, nested under their folders, which meant a library of
/// any size spent most of its height on the pages of folders nobody was looking at. The
/// folders are the map; the pages are in the column beside it.
struct SidebarView: View {
    @Binding var scope: NotebookScope?
    let actions: TreeActions

    @Query private var allFolders: [Folder]
    @State private var isRootDropTarget = false

    private var rootFolders: [Folder] {
        allFolders.filter { $0.parent == nil && !$0.isArchived }.sorted(by: Folder.displayOrder)
    }

    private var hasArchive: Bool {
        allFolders.contains { $0.isArchived } || archiveHasPages
    }

    // Kept separate so the row appears for an archived page even with no archived folder.
    @Query private var allPages: [Page]
    private var archiveHasPages: Bool { allPages.contains { $0.isArchived } }

    var body: some View {
        List(selection: $scope) {
            Label("All Pages", systemImage: "tray.full")
                .tag(NotebookScope.allPages)

            Section("Notebooks") {
                ForEach(rootFolders) { folder in
                    FolderDisclosure(folder: folder, allFolders: allFolders, actions: actions)
                }
            }

            if hasArchive {
                Label("Archive", systemImage: "archivebox")
                    .tag(NotebookScope.archive)
            }
        }
        .listStyle(.sidebar)
        // Dropping on the empty space below the folders moves an item to the top level,
        // which otherwise needs the context menu.
        .dropDestination(for: DraggedItem.self) { items, _ in
            items.reduce(false) { done, item in actions.move(item, nil) || done }
        } isTargeted: { isRootDropTarget = $0 }
        .overlay(alignment: .bottom) {
            if isRootDropTarget {
                Text("Move to the top level")
                    .font(.caption)
                    .padding(6)
                    .background(.tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { Divider() }
        .toolbar {
            // `.navigation`, not `.primaryAction`: primaryAction is the window's trailing
            // edge, so with three columns this button crossed the window to sit beside
            // the page controls and was the first thing pushed into the overflow menu.
            ToolbarItem(placement: .navigation) {
                Button(action: actions.newFolder) {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .help("New folder")
            }
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
    var importMarkdown: () -> Void
    var move: (DraggedItem, Folder?) -> Bool
    var rename: (TreeItem, Bool) -> Void
    var setArchived: (TreeItem, Bool) -> Void
    var togglePinned: (Page) -> Void
    var tagChanged: () -> Void
    var delete: (TreeItem) -> Void
}

// MARK: - Rows

private struct FolderDisclosure: View {
    @Bindable var folder: Folder
    let allFolders: [Folder]
    let actions: TreeActions

    @AppStorage private var isExpanded: Bool
    @State private var isDropTarget = false

    init(folder: Folder, allFolders: [Folder], actions: TreeActions) {
        _folder = Bindable(folder)
        self.allFolders = allFolders
        self.actions = actions
        _isExpanded = AppStorage(
            wrappedValue: false,
            SidebarExpansion.key(for: folder.id),
            store: AppEnvironment.defaults
        )
    }

    private var children: [Folder] {
        folder.sortedChildren.filter { !$0.isArchived }
    }

    var body: some View {
        Group {
            if children.isEmpty {
                row
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    ForEach(children) { child in
                        FolderDisclosure(folder: child, allFolders: allFolders, actions: actions)
                    }
                } label: {
                    row
                }
            }
        }
        .tag(NotebookScope.folder(folder.id))
    }

    /// The menu hangs off the label, not the DisclosureGroup: attached to the group it
    /// would also cover every child row inside it.
    private var row: some View {
        HStack(spacing: 4) {
            // The binder tab: a coloured bar on the leading edge, drawn only when the
            // folder has been given a colour so an untagged library stays quiet.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(FolderTag.color(folder.colorIndex) ?? .clear)
                .frame(width: 3, height: 15)

            Label(folder.name, systemImage: "folder")
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(pageCount)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            addMenu
        }
        // One element per folder, named for the folder. Left to itself, inside a
        // disclosure group SwiftUI folded the name, the count and the Add button into a
        // single menu button called "Work, 2" -- VoiceOver announced a folder as a menu,
        // and activating it opened Add instead of the folder. Add's two choices become
        // actions on the folder instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(folder.name)
        .accessibilityValue(pageCount.isEmpty ? "no pages" : "\(pageCount) pages")
        .accessibilityAction(named: "New Page") { actions.addPage(folder) }
        .accessibilityAction(named: "New Subfolder") { actions.addSubfolder(folder) }
        .contentShape(.rect)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(.tint.opacity(isDropTarget ? 0.25 : 0))
                .padding(.vertical, -2)
        )
        .contextMenu { menu }
        .draggable(DraggedItem(kind: .folder, id: folder.id))
        .dropDestination(for: DraggedItem.self) { items, _ in
            // A drop that lands on the folder it came from, or that would put a folder
            // inside its own subtree, is refused by the move itself.
            items.reduce(false) { done, item in actions.move(item, folder) || done }
        } isTargeted: { isDropTarget = $0 }
    }

    private var pageCount: String {
        let count = folder.sortedPages.filter { !$0.isArchived }.count
        return count == 0 ? "" : "\(count)"
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
            Button("New Page") { actions.addPage(folder) }
            Button("New Subfolder") { actions.addSubfolder(folder) }
            templateMenu
            Divider()
            Button("Rename…") { actions.rename(.folder(folder), false) }
            FolderTagMenu(folder: folder, onChange: actions.tagChanged)
            MoveToMenu(allFolders: allFolders) { destination in
                _ = actions.move(DraggedItem(kind: .folder, id: folder.id), destination)
            } isEnabled: { destination in
                folder.canBeMoved(to: destination)
            }
            Button("Archive") { actions.setArchived(.folder(folder), true) }
            Divider()
            Button("Delete…", role: .destructive) { actions.delete(.folder(folder)) }
        }
    }
}

/// One page in the middle column.
struct PageRow: View {
    @Bindable var page: Page
    let allFolders: [Folder]
    let actions: TreeActions

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(page.isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title.isEmpty ? "Untitled" : page.title)
                    .lineLimit(1)
                if let preview = preview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .tag(page.id)
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

    /// The first line with words in it, so a list of similarly titled weekly pages is
    /// still tellable apart -- skipping a first line that only repeats the title, which
    /// a page that opens with its own heading always has.
    private var preview: String? {
        let title = page.title.trimmingCharacters(in: .whitespaces)
        let line = page.plainText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0.caseInsensitiveCompare(title) != .orderedSame }
        guard let line else { return nil }
        return String(line.prefix(80))
    }

    private var icon: String {
        if page.isArchived { return "doc.badge.ellipsis" }
        return page.isPinned ? "pin.fill" : "doc.text"
    }
}

/// "Move to" submenu listing the top level and every folder, indented by depth.
struct MoveToMenu: View {
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
