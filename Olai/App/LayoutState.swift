import Observation
import SwiftUI

/// Which columns are showing.
///
/// Held outside the view so the View menu can drive it. Menu commands are built beside
/// the scene, not inside the view hierarchy, and a keyboard shortcut attached to a
/// toggle inside a toolbar menu does not register at all -- which is why hiding a column
/// had no shortcut worth the name until this existed.
@MainActor
@Observable
final class LayoutState {
    var showFolders = true {
        didSet { UserDefaults.standard.set(showFolders, forKey: Self.foldersKey) }
    }

    var showPageList = true {
        didSet { UserDefaults.standard.set(showPageList, forKey: Self.pagesKey) }
    }

    private static let foldersKey = "layout.showFolders"
    private static let pagesKey = "layout.showPageList"

    init() {
        let defaults = UserDefaults.standard
        // `object(forKey:)` rather than `bool(forKey:)`: a missing key reads as false,
        // which would start a fresh install with every column hidden.
        showFolders = defaults.object(forKey: Self.foldersKey) as? Bool ?? true
        showPageList = defaults.object(forKey: Self.pagesKey) as? Bool ?? true
    }

    var columnVisibility: NavigationSplitViewVisibility {
        showFolders ? .all : .doubleColumn
    }
}

/// View ▸ Folders / Page List.
struct LayoutCommands: Commands {
    @Bindable var layout: LayoutState

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Folders", isOn: $layout.showFolders)
                .keyboardShortcut("1", modifiers: [.command, .option])
            Toggle("Page List", isOn: $layout.showPageList)
                .keyboardShortcut("2", modifiers: [.command, .option])
            Divider()
        }
    }
}
