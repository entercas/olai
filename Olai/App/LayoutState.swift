import Observation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Whether the sidebar is showing.
///
/// Held outside the view so the View menu can drive it. Menu commands are built beside
/// the scene, not inside the view hierarchy, and a keyboard shortcut attached to a
/// toggle inside a toolbar menu does not register at all -- which is why hiding a column
/// had no shortcut worth the name until this existed.
@MainActor
@Observable
final class LayoutState {
    var showFolders = true {
        didSet { AppEnvironment.defaults.set(showFolders, forKey: Self.foldersKey) }
    }

    private static let foldersKey = "layout.showFolders"

    init() {
        let defaults = AppEnvironment.defaults
        // `object(forKey:)` rather than `bool(forKey:)`: a missing key reads as false,
        // which would start a fresh install with every column hidden.
        showFolders = defaults.object(forKey: Self.foldersKey) as? Bool ?? true
    }

    var columnVisibility: NavigationSplitViewVisibility {
        showFolders ? .all : .detailOnly
    }

    /// Whether the change being made right now comes from a person -- a click, a drag, a
    /// key -- rather than from the framework rearranging itself.
    static var isUserInitiated: Bool {
        #if os(macOS)
        guard let event = NSApp.currentEvent else { return false }
        let personal: Set<NSEvent.EventType> = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .keyDown, .keyUp,
        ]
        return personal.contains(event.type)
        #else
        return true
        #endif
    }
}

/// View ▸ Sidebar, and File ▸ New Page / New Folder.
struct LayoutCommands: Commands {
    @Bindable var layout: LayoutState
    @FocusedValue(\.treeActions) private var actions

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Sidebar", isOn: $layout.showFolders)
                .keyboardShortcut("1", modifiers: [.command, .option])
            Divider()
        }
        // In place of New Window: one window holds every page, as tabs.
        CommandGroup(replacing: .newItem) {
            Button("New Page") { actions?.newPage() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button("New Folder") { actions?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
    }
}

extension FocusedValues {
    /// The window's create and open actions, for the menu bar.
    @Entry var treeActions: TreeActions?
}
