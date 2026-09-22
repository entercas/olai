import SwiftData
import SwiftUI

@main
struct OlaiApp: App {
    private let modelContainer = OlaiModelContainer.make()

    #if os(macOS)
    @State private var mirrorSettings = MirrorSettings()
    @State private var mirrorExporter: MirrorExporter
    #endif

    init() {
        #if os(macOS)
        let settings = MirrorSettings()
        _mirrorSettings = State(initialValue: settings)
        _mirrorExporter = State(
            initialValue: MirrorExporter(container: modelContainer, settings: settings)
        )
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
            #if os(macOS)
                .environment(\.scheduleMirrorExport) { mirrorExporter.scheduleExport() }
            #endif
                // One task, not two: separate `.task` modifiers start together, and the
                // cleanup has to finish first so the mirror is written from a store with
                // no unreachable attachments left in it.
                .task {
                    AttachmentCleanup.run(in: modelContainer.mainContext)
                    #if os(macOS)
                    mirrorExporter.exportNow()
                    #endif
                }
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 1040, height: 700)
        .commands {
            SidebarCommands()
        }
        #endif

        #if os(macOS)
        Settings {
            MirrorSettingsView(settings: mirrorSettings, exporter: mirrorExporter)
        }
        #endif
    }
}
