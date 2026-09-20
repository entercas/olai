import OlaiCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

/// A page: its title, and the TipTap editor in a web view below it.
///
/// Swift keeps storage, images and scheduling; the web view keeps the document. Saves
/// arrive from the bridge already debounced 500 ms after the last keystroke.
struct PageEditorView: View {
    @Bindable var page: Page

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scheduleMirrorExport) private var scheduleMirrorExport

    @State private var controller = EditorController()
    @State private var dictation = DictationService()
    @State private var title: String = ""
    @State private var didLoad = false
    @State private var isSchedulePresented = false
    @State private var isImporterPresented = false
    #if os(iOS)
    @State private var photoItem: PhotosPickerItem?
    #endif

    var body: some View {
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

            EditorToolbar(
                controller: controller,
                dictation: dictation,
                onInsertImage: { isImporterPresented = true },
                onScheduleTask: { isSchedulePresented = true }
            )

            if case let .failed(message) = dictation.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, EditorMetrics.gutter)
                    .padding(.bottom, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            EditorWebView(controller: controller, container: context.container)
                .padding(.horizontal, EditorMetrics.gutter - 4)
        }
        .frame(maxWidth: EditorMetrics.columnWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
        .navigationTitle(LocationTitle.of(page.folder))
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: load)
        .onDisappear {
            controller.flush()
            dictation.stop()
        }
        .onChange(of: colorScheme) { _, new in controller.applyTheme(dark: new == .dark) }
        .task(id: title) { await saveTitle() }
        .sheet(isPresented: $isSchedulePresented) {
            ScheduleTaskSheet(
                taskText: controller.state.task.text,
                existingID: controller.state.task.reminderID,
                onScheduled: { id, due in controller.setTaskReminder(id: id, due: due) },
                onCleared: { controller.setTaskReminder(id: nil, due: nil) }
            )
        }
        .modifier(ImageImporter(isPresented: $isImporterPresented, insert: insertImage))
        #if os(iOS)
        .photosPicker(isPresented: $isImporterPresented, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    insertImage(data: data, mime: "image/png", name: "photo")
                }
                photoItem = nil
            }
        }
        #endif
    }

    // MARK: Wiring

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        title = page.title

        controller.onDocumentChanged = { data, plainText in
            // The editor reports its document on every change; only a real change to the
            // stored bytes should touch the page's timestamp.
            guard data != page.body else { return }
            page.body = data
            page.plainText = plainText
            page.updatedAt = Date()
            scheduleMirrorExport()
        }

        controller.onImagePasted = { data, mime, name in
            store(data: data, mime: mime, name: name)
        }

        dictation.onTranscript = { text, isFinal in
            controller.setDictationText(text)
            if isFinal { controller.endDictation() }
        }
        dictation.onFinish = { controller.endDictation() }

        controller.setDocument(json: page.body)
        controller.applyTheme(dark: colorScheme == .dark)
    }

    private func saveTitle() async {
        guard didLoad else { return }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != page.title else { return }
        page.title = trimmed
        page.updatedAt = Date()
        scheduleMirrorExport()
    }

    /// Saves image bytes as an attachment of this page and returns its id; the document
    /// only ever references `attachment://<id>`.
    private func store(data: Data, mime: String, name: String) -> UUID {
        let attachment = Attachment(
            filename: name,
            mimeType: mime,
            data: data,
            page: page
        )
        context.insert(attachment)
        page.updatedAt = Date()
        return attachment.id
    }

    private func insertImage(data: Data, mime: String, name: String) {
        controller.insertImage(id: store(data: data, mime: mime, name: name))
    }

    private var caption: String {
        let edited = "Edited \(page.updatedAt.formatted(.relative(presentation: .named)))"
        #if os(macOS)
        return "\(LocationTitle.of(page.folder)) · \(edited)"
        #else
        return edited
        #endif
    }
}

/// Picking an image from disk. iOS uses the photo picker instead, so this only attaches
/// the file importer on the Mac.
private struct ImageImporter: ViewModifier {
    @Binding var isPresented: Bool
    let insert: (Data, String, String) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.image]
        ) { result in
            guard
                case let .success(url) = result,
                url.startAccessingSecurityScopedResource()
            else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let data = try? Data(contentsOf: url) else { return }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            insert(data, mime, url.lastPathComponent)
        }
        #else
        content
        #endif
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
