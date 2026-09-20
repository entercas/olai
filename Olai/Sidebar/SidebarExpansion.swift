import Foundation

/// Where per-folder expand/collapse state lives. Each folder gets its own
/// `UserDefaults` key so rows can bind to it with `@AppStorage`; writes from outside a
/// view (expanding a parent after adding a child) go through `setExpanded`.
enum SidebarExpansion {
    static func key(for folderID: UUID) -> String {
        "sidebar.expanded.\(folderID.uuidString)"
    }

    static func setExpanded(_ expanded: Bool, for folderID: UUID) {
        UserDefaults.standard.set(expanded, forKey: key(for: folderID))
    }
}
