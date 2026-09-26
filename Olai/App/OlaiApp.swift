import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct OlaiApp: App {
    private let modelContainer = OlaiModelContainer.make()
    @State private var layout = LayoutState()

    #if os(macOS)
    @State private var mirrorSettings = MirrorSettings()
    @State private var mirrorExporter: MirrorExporter
    #endif

    init() {
        #if os(macOS)
        switch AppEnvironment.forcedAppearance {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
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
                .environment(layout)
            #if os(macOS)
                .environment(\.scheduleMirrorExport) { mirrorExporter.scheduleExport() }
                .environment(\.mirrorRoot, mirrorSettings.root)
            #endif
                // One task, not two: separate `.task` modifiers start together, and the
                // cleanup has to finish first so the mirror is written from a store with
                // no unreachable attachments left in it.
                .task {
                    AttachmentCleanup.run(in: modelContainer.mainContext)
                    DerivedTextRefresh.run(in: modelContainer.mainContext)
                    #if os(macOS)
                    mirrorExporter.exportNow()
                    #endif
                }
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 1200, height: 760)
        .commands {
            SidebarCommands()
            LayoutCommands(layout: layout)
        }
        #endif

        #if os(macOS)
        Settings {
            MirrorSettingsView(settings: mirrorSettings, exporter: mirrorExporter)
        }
        #endif
    }
}
