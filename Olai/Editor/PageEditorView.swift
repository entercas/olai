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
        // The column is constrained by layout, never by measured geometry: an inset
        // computed from a GeometryReader goes stale mid-resize and can exceed the pane,
        // squeezing the text to a single character per line.
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                #if os(iOS)
                    .submitLabel(.done)
                #endif

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, EditorMetrics.gutter)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, EditorMetrics.gutter)

            TextEditor(text: $text)
                .textEditorStyle(.plain)
                .font(.body)
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .safeAreaPadding(.horizontal, EditorMetrics.gutter)
                .safeAreaPadding(.vertical, 14)
        }
        // Narrower of the pane and a readable column, centred in the pane.
        .frame(maxWidth: EditorMetrics.columnWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The document's own title is the field above, so the toolbar shows where the
        // page lives instead of repeating it.
        #if os(iOS)
        .navigationTitle(LocationTitle.of(page.folder))
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

    /// Where the page lives and when it last changed. On iPhone the location is already
    /// in the navigation bar, so the caption there is just the timestamp.
    private var caption: String {
        let edited = "Edited \(page.updatedAt.formatted(.relative(presentation: .named)))"
        #if os(macOS)
        return "\(LocationTitle.of(page.folder)) · \(edited)"
        #else
        return edited
        #endif
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
}

/// Where an item sits in the tree, for the detail pane's title.
enum LocationTitle {
    static func of(_ folder: Folder?) -> String {
        guard let folder else { return "Olai" }
        return folder.pathComponents.joined(separator: " / ")
    }
}
