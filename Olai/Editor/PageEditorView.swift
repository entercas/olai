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
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
            #if os(iOS)
                .submitLabel(.done)
            #endif

            Divider()

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(page.title.isEmpty ? "Untitled" : page.title)
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
