import OlaiCore
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// What the sidebar has selected: a folder, which is where New Page puts things, or a
/// page, which is the one open in front.
enum TreeSelection: Hashable {
    case folder(UUID)
    case page(UUID)
}

/// The sidebar: every folder and page in one tree, the way Obsidian's file explorer
/// shows a vault.
///
/// It used to be two columns -- folders, then the pages of the selected folder -- and
/// that split was most of what made the app hard to use. A new page landed in a list
/// sorted across every folder, so it appeared somewhere in the middle of All Pages; you
/// could not see where a page lived and what was beside it at the same time; and the
/// page list redrew every row, previews and all, on every keystroke. Now a page sits
/// under its folder, a new one appears where it was made, and only the rows showing are
/// drawn.
struct SidebarView: View {
    @Binding var selection: TreeSelection?
    /// Asks the tree to scroll a row into view -- a page just made, or found by search.
    @Binding var revealRequest: TreeSelection?
    let expansion: TreeExpansion
    let actions: TreeActions

    @Query private var allFolders: [Folder]
    @Query private var allPages: [Page]
    @State private var search = ""

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        // One list whether searching or not. Swapping in a second list for the results
        // took the keyboard away from the search field after the first letter.
        //
        // The index is built here, from the queries, and the rows are drawn by a view
        // of their own: a click changes the selection, and that should redraw the rows,
        // not regroup the whole library.
        TreeList(
            index: TreeIndex(folders: allFolders, pages: allPages),
            matches: isSearching ? matches : nil,
            allFolders: allFolders,
            selection: $selection,
            revealRequest: $revealRequest,
            expansion: expansion,
            actions: actions
        )
        .searchable(text: $search, placement: .sidebar, prompt: "Search")
        .safeAreaInset(edge: .top, spacing: 0) { header }
        #if os(iOS)
        .navigationTitle("Olai")
        #endif
    }

    // MARK: Header

    /// New page, new folder, templates, collapse all: the row of buttons at the top of
    /// Obsidian's file explorer, in the same place.
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                headerButton("New Page", systemImage: "square.and.pencil", action: actions.newPage)
                    .help("New page in the selected folder (⌘N)")
                headerButton("New Folder", systemImage: "folder.badge.plus", action: actions.newFolder)
                    .help("New folder in the selected folder (⇧⌘N)")
                Menu {
                    ForEach(TemplateStore.all) { template in
                        Button(template.name) { actions.newFromTemplate(template) }
                    }
                    Divider()
                    Button("Import Transcript…", systemImage: "waveform") { actions.importTranscript() }
                    Button("Import Markdown Folder…", systemImage: "square.and.arrow.down") {
                        actions.importMarkdown()
                    }
                } label: {
                    Image(systemName: "doc.badge.plus")
                        .frame(width: 28, height: 24)
                        .contentShape(.rect)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                .help("New from a template, or import")
                .accessibilityLabel("Templates and Import")

                headerButton("Collapse All", systemImage: "arrow.down.right.and.arrow.up.left") {
                    expansion.collapseAll()
                }
                .help("Collapse all folders")
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            Divider()
        }
    }

    private func headerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }

    // MARK: Search

    /// Title and body, across the whole library.
    private var matches: [Page] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        return allPages
            .filter {
                $0.title.localizedStandardContains(needle) || $0.plainText.localizedStandardContains(needle)
            }
            .sorted(by: Page.displayOrder)
    }
}

/// The rows of the tree, with the selection drawn on them.
private struct TreeList: View {
    let index: TreeIndex
    /// The search results, when there is a search.
    let matches: [Page]?
    let allFolders: [Folder]
    @Binding var selection: TreeSelection?
    @Binding var revealRequest: TreeSelection?
    let expansion: TreeExpansion
    let actions: TreeActions

    @State private var showArchive = false
    @State private var isRootDropTarget = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let matches {
                    searchResults(matches)
                } else {
                    tree(index)
                }
            }
                .listStyle(.sidebar)
                .environment(\.defaultMinListRowHeight, 24)
                .onChange(of: revealRequest) { _, target in
                    guard let target else { return }
                    // After the expansion that revealed it has been drawn.
                    DispatchQueue.main.async {
                        withAnimation { proxy.scrollTo(target) }
                        revealRequest = nil
                    }
                }
        }
    }

    // MARK: Tree

    private func searchResults(_ matches: [Page]) -> some View {
        Section(matches.isEmpty ? "No matches" : "\(matches.count) found") {
            ForEach(matches.prefix(200)) { page in
                Button {
                    selection = .page(page.id)
                    actions.open(page.id, false)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(page.title.isEmpty ? "Untitled" : page.title)
                            .lineLimit(1)
                        Text(LocationTitle.of(page.folder))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.title.isEmpty ? "Untitled" : page.title)
                .accessibilityIdentifier("result:\(page.title)")
            }
        }
    }

    @ViewBuilder
    private func tree(_ index: TreeIndex) -> some View {
        let pinned = index.pinned
        if !pinned.isEmpty {
            Section("Pinned") {
                ForEach(pinned, id: \.pinnedRowID) { page in
                    row(TreeRow(kind: .page(page), depth: 0, path: "pinned/"), index: index)
                }
            }
        }

        Section("Notes") {
            ForEach(index.rows(expanded: expansion.expanded)) { item in
                row(item, index: index)
            }
            // The blank space under the tree: clicking it clears the selection, so the
            // next new page goes to the top level; dropping on it moves there.
            Color.clear
                .frame(height: 80)
                .contentShape(.rect)
                .onTapGesture { selection = nil }
                .overlay(alignment: .top) {
                    if isRootDropTarget {
                        Text("Move to the top level")
                            .font(.caption)
                            .padding(6)
                            .background(.tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .dropDestination(for: DraggedItem.self) { items, _ in
                    items.reduce(false) { done, item in actions.move(item, nil) || done }
                } isTargeted: { isRootDropTarget = $0 }
                .accessibilityHidden(true)
        }

        if index.hasArchive {
            Section {
                if showArchive {
                    ForEach(index.archivedFolders) { folder in
                        ArchivedRow(title: folder.name, systemImage: "folder", actions: actions, item: .folder(folder))
                    }
                    ForEach(index.archivedPages) { page in
                        Button {
                            selection = .page(page.id)
                            actions.open(page.id, false)
                        } label: {
                            ArchivedRow.label(title: page.title, systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                        .contextMenu { ArchivedRow.menu(.page(page), actions: actions) }
                    }
                }
            } header: {
                Button {
                    showArchive.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(showArchive ? 90 : 0))
                        Text("Archive")
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Archive")
                .accessibilityValue(showArchive ? "expanded" : "collapsed")
            }
        }
    }

    private func row(_ item: TreeRow, index: TreeIndex) -> some View {
        TreeRowView(
            item: item,
            isSelected: isSelected(item),
            isExpanded: item.folderID.map(expansion.isExpanded) ?? false,
            hasChildren: item.folderID.map(index.hasChildren) ?? false,
            allFolders: allFolders,
            actions: actions,
            onClick: { newTab in click(item, newTab: newTab) }
        )
    }

    private func isSelected(_ item: TreeRow) -> Bool {
        switch item.kind {
        case let .folder(folder): selection == .folder(folder.id)
        case let .page(page): selection == .page(page.id)
        }
    }

    /// A folder opens or closes, and becomes where new pages go. A page opens in the
    /// tab in front, or in a new tab with ⌘.
    private func click(_ item: TreeRow, newTab: Bool) {
        switch item.kind {
        case let .folder(folder):
            selection = .folder(folder.id)
            expansion.toggle(folder.id)
        case let .page(page):
            selection = .page(page.id)
            actions.open(page.id, newTab)
        }
    }

}

// MARK: - The tree as rows

/// One row of the tree as it is drawn.
struct TreeRow: Identifiable {
    enum Kind {
        case folder(Folder)
        case page(Page)
    }

    let kind: Kind
    let depth: Int
    /// The names of the folders above it, for the accessibility identifier the UI test
    /// uses to check that a page sits where it should.
    let path: String

    var id: TreeSelection {
        switch kind {
        case let .folder(folder): .folder(folder.id)
        case let .page(page): .page(page.id)
        }
    }

    var folderID: UUID? {
        if case let .folder(folder) = kind { return folder.id }
        return nil
    }
}

/// The library grouped by parent, built once per redraw from the two queries.
///
/// Grouping by id rather than walking `folder.pages`: SwiftData does not always update
/// the inverse side of a relationship straight away, and a page made in a folder could
/// go missing from that folder's list until the next save.
struct TreeIndex {
    private let folders: [UUID?: [Folder]]
    private let pages: [UUID?: [Page]]
    let archivedFolders: [Folder]
    let archivedPages: [Page]
    let pinned: [Page]

    init(folders allFolders: [Folder], pages allPages: [Page]) {
        let liveFolders = allFolders.filter { !$0.isArchived }
        folders = Dictionary(grouping: liveFolders) { $0.parent?.id }
            .mapValues { $0.sorted(by: Folder.displayOrder) }
        pages = Dictionary(grouping: allPages.filter { !$0.isArchived }) { $0.folder?.id }
            .mapValues { $0.sorted(by: TreeIndex.pageOrder) }

        // Only the top of each archived branch: the rest comes back with it.
        archivedFolders = allFolders
            .filter { $0.isArchived && !($0.parent?.isArchived ?? false) }
            .sorted(by: Folder.displayOrder)
        archivedPages = allPages
            .filter { $0.isArchived && !($0.folder?.isArchived ?? false) }
            .sorted(by: Page.displayOrder)
        pinned = allPages.filter { $0.isPinned && !$0.isArchived }.sorted(by: Page.displayOrder)
    }

    /// In a folder, pages stay in the order they were made, new ones at the bottom --
    /// where the person who just made one is looking.
    static func pageOrder(_ lhs: Page, _ rhs: Page) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.createdAt < rhs.createdAt
    }

    var hasArchive: Bool { !archivedFolders.isEmpty || !archivedPages.isEmpty }

    func hasChildren(_ folderID: UUID) -> Bool {
        !(folders[folderID] ?? []).isEmpty || !(pages[folderID] ?? []).isEmpty
    }

    func pages(in folderID: UUID?) -> [Page] { pages[folderID] ?? [] }

    /// The rows showing: folders first, then pages, at each level -- as Obsidian lists
    /// them -- descending only into folders that are open.
    func rows(expanded: Set<UUID>) -> [TreeRow] {
        var result: [TreeRow] = []
        func walk(_ parent: UUID?, depth: Int, path: String) {
            guard depth < 64 else { return }
            for folder in folders[parent] ?? [] {
                result.append(TreeRow(kind: .folder(folder), depth: depth, path: path))
                if expanded.contains(folder.id) {
                    walk(folder.id, depth: depth + 1, path: path + folder.name + "/")
                }
            }
            for page in pages[parent] ?? [] {
                result.append(TreeRow(kind: .page(page), depth: depth, path: path))
            }
        }
        walk(nil, depth: 0, path: "/")
        return result
    }
}

private extension Page {
    /// Pinned pages also appear in their folders, so their rows in the Pinned section
    /// need an identity of their own.
    var pinnedRowID: String { "pinned-\(id.uuidString)" }
}

// MARK: - Rows

private struct TreeRowView: View {
    let item: TreeRow
    let isSelected: Bool
    let isExpanded: Bool
    let hasChildren: Bool
    let allFolders: [Folder]
    let actions: TreeActions
    let onClick: (_ newTab: Bool) -> Void

    @State private var isHovering = false
    @State private var isDropTarget = false

    private static let indent: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
            // Not a Button: a button tracks the mouse from the moment it goes down, so a
            // row that was one could not be dragged into a folder at all. Nor is the tap
            // handler here -- on the same view as `draggable`, a tap gesture stopped the
            // drag from ever starting -- it is on the row around this. To VoiceOver and
            // the keyboard it is still a button, through the trait and the default
            // action. Selection is drawn here rather than left to the list.
            HStack(spacing: 5) {
                leading
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isUntitled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(item.depth) * Self.indent)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contentShape(.rect)
            .draggable(dragged)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onClick(false) }
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if case let .folder(folder) = item.kind, isHovering {
                addMenu(folder)
            }
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(background)
        )
        .onHover { isHovering = $0 }
        // Outside the draggable content; see above.
        .onTapGesture { onClick(Self.commandIsDown) }
        .contextMenu { menu }
        .modifier(FolderDrop(item: item, actions: actions, isTargeted: $isDropTarget))
    }

    private var background: AnyShapeStyle {
        if isDropTarget { return AnyShapeStyle(.tint.opacity(0.3)) }
        if isSelected { return AnyShapeStyle(.tint.opacity(0.22)) }
        if isHovering { return AnyShapeStyle(Color.primary.opacity(0.05)) }
        return AnyShapeStyle(.clear)
    }

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case let .folder(folder):
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .opacity(hasChildren ? 1 : 0.35)
                .frame(width: 10)
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .foregroundStyle(FolderTag.inheritedColor(for: folder).map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .frame(width: 18)
        case let .page(page):
            Color.clear.frame(width: 10)
            Image(systemName: page.isPinned ? "pin.fill" : "doc.text")
                .foregroundStyle(page.isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 18)
                .accessibilityLabel(page.isPinned ? "Pin" : "")
        }
    }

    private var title: String {
        switch item.kind {
        case let .folder(folder): folder.name
        case let .page(page): page.title.isEmpty ? "Untitled" : page.title
        }
    }

    private var isUntitled: Bool {
        if case let .page(page) = item.kind { return page.title.isEmpty }
        return false
    }

    private var identifier: String {
        switch item.kind {
        case .folder: "folder:\(item.path)\(title)"
        case .page: "page:\(item.path)\(title)"
        }
    }

    private var accessibilityValue: String {
        guard case .folder = item.kind else { return isSelected ? "selected" : "" }
        return isExpanded ? "expanded" : "collapsed"
    }

    private var dragged: DraggedItem {
        switch item.kind {
        case let .folder(folder): DraggedItem(kind: .folder, id: folder.id)
        case let .page(page): DraggedItem(kind: .page, id: page.id)
        }
    }

    private static var commandIsDown: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.command)
        #else
        false
        #endif
    }

    /// The row's own "+", shown on hover: creates inside this folder, whatever is
    /// selected.
    private func addMenu(_ folder: Folder) -> some View {
        Menu {
            Button("New Page", systemImage: "square.and.pencil") { actions.addPage(folder) }
            Button("New Subfolder", systemImage: "folder.badge.plus") { actions.addSubfolder(folder) }
            Divider()
            templateMenu(folder)
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
        .accessibilityLabel("Add inside \(folder.name)")
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }

    private func templateMenu(_ folder: Folder) -> some View {
        Menu("New from Template") {
            ForEach(TemplateStore.all) { template in
                Button(template.name) { actions.addFromTemplate(template, folder) }
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        switch item.kind {
        case let .folder(folder):
            Button("New Page") { actions.addPage(folder) }
            Button("New Subfolder") { actions.addSubfolder(folder) }
            templateMenu(folder)
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

        case let .page(page):
            Button("Open in New Tab") { actions.open(page.id, true) }
            Divider()
            Button("Rename…") { actions.rename(.page(page), false) }
            MoveToMenu(allFolders: allFolders) { destination in
                _ = actions.move(DraggedItem(kind: .page, id: page.id), destination)
            } isEnabled: { destination in
                destination?.id != page.folder?.id
            }
            Button(page.isPinned ? "Unpin" : "Pin") { actions.togglePinned(page) }
            Button("Archive") { actions.setArchived(.page(page), true) }
            Divider()
            Button("Delete…", role: .destructive) { actions.delete(.page(page)) }
        }
    }
}

/// Dropping on a folder moves into it; dropping on a page moves beside it.
private struct FolderDrop: ViewModifier {
    let item: TreeRow
    let actions: TreeActions
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        content.dropDestination(for: DraggedItem.self) { items, _ in
            let destination: Folder?
            switch item.kind {
            case let .folder(folder): destination = folder
            case let .page(page): destination = page.folder
            }
            // A move onto where it already is, or a folder into its own subtree, is
            // refused by the move itself.
            return items.reduce(false) { done, dragged in actions.move(dragged, destination) || done }
        } isTargeted: { isTargeted = $0 }
    }
}

/// A folder or page in the Archive section.
private struct ArchivedRow: View {
    let title: String
    let systemImage: String
    let actions: TreeActions
    let item: TreeItem

    var body: some View {
        Self.label(title: title, systemImage: systemImage)
            .contextMenu { Self.menu(item, actions: actions) }
    }

    static func label(title: String, systemImage: String) -> some View {
        Label(title.isEmpty ? "Untitled" : title, systemImage: systemImage)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
    }

    @ViewBuilder
    static func menu(_ item: TreeItem, actions: TreeActions) -> some View {
        Button("Unarchive") { actions.setArchived(item, false) }
        Divider()
        Button("Delete…", role: .destructive) { actions.delete(item) }
    }
}

/// A folder or a page, for the flows that treat them alike.
enum TreeItem: Hashable {
    case folder(Folder)
    case page(Page)
}

/// What the sidebar can ask for. The work itself lives in `RootView`, which owns the
/// model context, the selection and the tabs.
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
    /// Opens a page: in the tab in front, or in a new tab when the flag is set.
    var open: (UUID, Bool) -> Void
    var move: (DraggedItem, Folder?) -> Bool
    var rename: (TreeItem, Bool) -> Void
    var setArchived: (TreeItem, Bool) -> Void
    var togglePinned: (Page) -> Void
    var tagChanged: () -> Void
    var delete: (TreeItem) -> Void
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
