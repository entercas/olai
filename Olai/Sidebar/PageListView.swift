import OlaiCore
import SwiftData
import SwiftUI

/// The middle column: the pages of whatever the notebook column has selected.
///
/// Search lives here rather than beside the folders, because what it finds is pages.
/// Searching looks across the whole library, not just the current folder -- a search
/// that only covered where you already were would answer the question you had not asked.
struct PageListView: View {
    let scope: NotebookScope?
    @Binding var openPage: UUID?
    let actions: TreeActions

    @Query private var allPages: [Page]
    @Query private var allFolders: [Folder]
    @State private var search = ""

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var folder: Folder? {
        guard case let .folder(id) = scope else { return nil }
        return allFolders.first { $0.id == id }
    }

    private var pages: [Page] {
        if isSearching { return matches }

        switch scope {
        case .allPages, nil:
            return allPages.filter { !$0.isArchived }.sorted(by: Page.displayOrder)
        case .archive:
            return allPages.filter(\.isArchived).sorted(by: Page.displayOrder)
        case .folder:
            guard let folder else { return [] }
            return folder.sortedPages.filter { !$0.isArchived }
        }
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

    var body: some View {
        List(selection: $openPage) {
            if pages.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: isSearching ? "magnifyingglass" : "doc.text")
                } description: {
                    Text(emptyMessage)
                }
                .listRowSeparator(.hidden)
            }

            ForEach(pages) { page in
                PageRow(page: page, allFolders: allFolders, actions: actions)
            }
        }
        .searchable(text: $search, prompt: "Search all pages")
        .navigationTitle(title)
        #if os(macOS)
        .navigationSubtitle(subtitle)
        #endif
        .safeAreaInset(edge: .top, spacing: 0) { Divider() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NewPageButton(actions: actions, folder: folder)
            }
        }
    }

    private var title: String {
        if isSearching { return "Search" }
        switch scope {
        case .allPages, nil: return "All Pages"
        case .archive: return "Archive"
        case .folder: return folder?.name ?? "Folder"
        }
    }

    private var subtitle: String {
        let count = pages.count
        return "\(count) page\(count == 1 ? "" : "s")"
    }

    private var emptyTitle: String {
        isSearching ? "No matches" : "No pages"
    }

    private var emptyMessage: String {
        if isSearching { return "Nothing matches “\(search)”." }
        switch scope {
        case .archive: return "Archived pages appear here."
        case .folder: return "This folder has no pages yet."
        default: return "Make one with New Page."
        }
    }
}
