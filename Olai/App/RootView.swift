import OlaiCore
import SwiftData
import SwiftUI

/// What the sidebar has selected. Folders and pages share the list, so the selection
/// carries the kind alongside the model's stable `UUID`.
enum SidebarSelection: Hashable {
    case folder(UUID)
    case page(UUID)
}

struct RootView: View {
    @State private var selection: SidebarSelection?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            DetailView(selection: selection)
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
                description: Text("Pick a page in the sidebar, or create one with the + button.")
            )
        }
    }
}

/// Stand-in detail for a selected folder: what it holds, and a way in.
private struct FolderDetailView: View {
    @Bindable var folder: Folder

    var body: some View {
        let pages = folder.sortedPages.filter { !$0.isArchived }
        let subfolders = folder.sortedChildren.filter { !$0.isArchived }

        VStack(alignment: .leading, spacing: 12) {
            Text(folder.name)
                .font(.largeTitle)
            Text("\(subfolders.count) folder\(subfolders.count == 1 ? "" : "s") · \(pages.count) page\(pages.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .navigationTitle(folder.name)
    }
}
