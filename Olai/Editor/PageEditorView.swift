import OlaiCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

/// The editor column: the tab bar, the page in front, and one web view that every tab
/// shares.
///
/// There used to be a web view per page, rebuilt whenever the tab changed: a new web
/// content process, the 1 MB editor bundle parsed again, the document loaded into it.
/// That took most of a second on any library before anything else had happened. Now the
/// web view is made once, and changing tab only loads a different document into it.
struct EditorPane: View {
    let tabs: OpenTabs

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scheduleMirrorExport) private var scheduleMirrorExport
    @Query private var pages: [Page]

    @State private var controller = EditorController()
    @State private var dictation = DictationService()
    @State private var didWire = false
    @State private var isSchedulePresented = false
    @State private var isImporterPresented = false
    #if os(iOS)
    @State private var photoItem: PhotosPickerItem?
    #endif

    private var activePage: Page? {
        guard let id = tabs.active else { return nil }
        return pages.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBar(tabs: tabs, pages: pages)

            if let page = activePage {
                // Rebuilt per page, so its title field starts from that page's title.
                // Only the title: the toolbar below fits itself to the width by
                // measuring several versions of its row, and rebuilding it with the
                // title took longer than everything else a tab switch does.
                PageHeader(page: page, tabs: tabs, controller: controller)
                    .id(page.id)

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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
            }

            // Always in the hierarchy, in the same place, so SwiftUI keeps the one web
            // view rather than making another. Hidden, not removed, with no page open.
            EditorWebView(controller: controller, container: context.container)
                .opacity(activePage == nil ? 0 : 1)
                .allowsHitTesting(activePage != nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if activePage == nil {
                ContentUnavailableView(
                    "No page open",
                    systemImage: "doc.text",
                    description: Text("Pick a page in the sidebar, or make one with New Page.")
                )
            }
        }
        #if os(iOS)
        .navigationTitle(activePage.map { LocationTitle.of($0.folder) } ?? "Olai")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: wire)
        .onChange(of: tabs.active, initial: true) { _, _ in show(activePage) }
        .onChange(of: colorScheme) { _, new in controller.applyTheme(dark: new == .dark) }
        .onDisappear {
            controller.flush()
            dictation.stop()
        }
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

    private func wire() {
        guard !didWire else { return }
        didWire = true

        controller.onDocumentChanged = { [context, scheduleMirrorExport] pageID, data, plainText in
            // Looked up by the id the save carries, not taken from whichever tab is in
            // front: the save may belong to the tab just left.
            guard let page = Self.page(pageID, in: context) else { return }
            // The editor reports its document on every change; only a real change to the
            // stored bytes should touch the page's timestamp.
            guard data != page.body else { return }
            page.body = data
            page.plainText = plainText
            page.updatedAt = Date()
            scheduleMirrorExport()
        }

        controller.onImagePasted = { [context] data, mime, name in
            guard let id = controller.pageID, let page = Self.page(id, in: context) else { return nil }
            return Self.store(data: data, mime: mime, name: name, on: page, context: context)
        }

        dictation.onTranscript = { text, utterance, isFinal in
            controller.setDictationText(text, utterance: utterance)
            if isFinal { controller.endDictation() }
        }
        dictation.onFinish = { controller.endDictation() }

        controller.applyTheme(dark: colorScheme == .dark)
    }

    private func show(_ page: Page?) {
        PerfLog.mark("show")
        dictation.stop()
        guard let page else { return }
        controller.setDocument(json: page.body, pageID: page.id)
    }

    private static func page(_ id: UUID, in context: ModelContext) -> Page? {
        var descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Saves image bytes as an attachment of the page and returns its id; the document
    /// only ever references `attachment://<id>`.
    private static func store(data: Data, mime: String, name: String, on page: Page, context: ModelContext) -> UUID {
        let attachment = Attachment(
            filename: name,
            mimeType: Attachment.safeMimeType(mime),
            data: data,
            page: page
        )
        context.insert(attachment)
        page.updatedAt = Date()
        return attachment.id
    }

    private func insertImage(data: Data, mime: String, name: String) {
        guard let page = activePage else { return }
        controller.insertImage(id: Self.store(data: data, mime: mime, name: name, on: page, context: context))
    }
}

/// A page's title and where it lives.
private struct PageHeader: View {
    @Bindable var page: Page
    let tabs: OpenTabs
    let controller: EditorController

    @Environment(\.scheduleMirrorExport) private var scheduleMirrorExport
    @State private var title = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("Untitled", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .focused($isTitleFocused)
                    // Return goes on to the page, the way it does in Obsidian: name it,
                    // press Return, start writing.
                    .onSubmit {
                        commitTitle()
                        controller.run("focus")
                    }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            title = page.title
            // A page that was just made opens with its name ready to type.
            if tabs.titleFocusRequest == page.id {
                tabs.titleFocusRequest = nil
                isTitleFocused = true
            }
        }
        // Written as it is typed, so the sidebar follows along.
        .onChange(of: title) { _, new in
            guard new != page.title else { return }
            page.title = new
            page.updatedAt = Date()
            scheduleMirrorExport()
        }
        // Renamed from the sidebar while open.
        .onChange(of: page.title) { _, new in
            if new != title { title = new }
        }
        .onDisappear(perform: commitTitle)
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != page.title else { return }
        page.title = trimmed
        page.updatedAt = Date()
        scheduleMirrorExport()
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
}

/// Where an item sits in the tree, for the detail pane's title.
enum LocationTitle {
    static func of(_ folder: Folder?) -> String {
        guard let folder else { return "Olai" }
        return folder.pathComponents.joined(separator: " / ")
    }
}
