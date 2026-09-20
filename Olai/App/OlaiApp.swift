import SwiftData
import SwiftUI

@main
struct OlaiApp: App {
    private let modelContainer = OlaiModelContainer.make()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .commands {
            SidebarCommands()
        }
        #endif
    }
}
