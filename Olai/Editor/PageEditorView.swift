import OlaiCore
import SwiftData
import SwiftUI

/// Phase 1 editor: a title field and a plain `TextEditor`. The body is still written as
/// a block document so the web editor can open these pages unchanged in phase 2.
///
/// Writes are debounced 500 ms after the last keystroke, matching the debounce the
/// editor bridge will use.
struct PageEditorView: View {
    @Bindable var page: Page

    @State private var title: String = ""
    @State private var text: String = ""
    @State private var didLoad = false

    var body: some View {
        // The scroll view fills the pane so its scrollbar sits at the pane's edge, the
        // way every other document window puts it; only the *content* is inset to a
        // readable column, and the header matches that inset.
        GeometryReader { proxy in
            let inset = EditorMetrics.sideInset(forPaneWidth: proxy.size.width)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                    #if os(iOS)
                        .submitLabel(.done)
                    #endif

                    Text("Edited \(page.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, inset)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Divider()
                    .padding(.horizontal, inset)

                TextEditor(text: $text)
                    .textEditorStyle(.plain)
                    .font(.body)
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .safeAreaPadding(.horizontal, inset)
                    .safeAreaPadding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // The document's own title is the field above, so the toolbar shows where the
        // page lives instead of repeating it.
        .navigationTitle(LocationTitle.of(page.folder))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            guard !didLoad else { return }
            title = page.title
            text = page.bodyText
            didLoad = true
        }
        .task(id: text) {
            await debouncedSave {
                page.setBodyText(text)
            }
        }
        .task(id: title) {
            await debouncedSave {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed != page.title else { return }
                page.title = trimmed
                page.updatedAt = Date()
            }
        }
    }

    /// Waits out the debounce window, then applies `save` unless the field changed again
    /// (which cancels this task) or the view has not finished loading.
    private func debouncedSave(_ save: () -> Void) async {
        guard didLoad else { return }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        save()
    }
}

enum EditorMetrics {
    static let gutter: CGFloat = 28
    static let columnWidth: CGFloat = 860

    /// Side inset that centres a `columnWidth` column, never tighter than the gutter.
    static func sideInset(forPaneWidth width: CGFloat) -> CGFloat {
        max(gutter, (width - columnWidth) / 2)
    }
}

/// Where an item sits in the tree, for the detail pane's title.
enum LocationTitle {
    static func of(_ folder: Folder?) -> String {
        guard let folder else { return "Olai" }
        return folder.pathComponents.joined(separator: " / ")
    }
}
