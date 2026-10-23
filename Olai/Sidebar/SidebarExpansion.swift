import Foundation
import Observation
import OlaiCore

/// Which folders are open in the sidebar tree.
///
/// One set rather than a preference per folder: the tree is drawn as a flat list of the
/// rows that are showing, and working that out means asking about every folder on every
/// redraw.
@MainActor
@Observable
final class TreeExpansion {
    private static let key = "sidebar.expandedFolders"
    private static let legacyPrefix = "sidebar.expanded."

    private(set) var expanded: Set<UUID> = []

    init() {
        let defaults = AppEnvironment.defaults
        if let stored = defaults.stringArray(forKey: Self.key) {
            expanded = Set(stored.compactMap(UUID.init(uuidString:)))
        } else {
            // Before 1.4 each folder had a key of its own; keep what people had open.
            expanded = Set(defaults.dictionaryRepresentation().compactMap { key, value in
                guard key.hasPrefix(Self.legacyPrefix), value as? Bool == true else { return nil }
                return UUID(uuidString: String(key.dropFirst(Self.legacyPrefix.count)))
            })
        }
    }

    func isExpanded(_ id: UUID) -> Bool { expanded.contains(id) }

    func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        save()
    }

    func expand(_ id: UUID) {
        guard !expanded.contains(id) else { return }
        expanded.insert(id)
        save()
    }

    /// Opens every folder above `folder`, and the folder itself, so a row inside it
    /// can be seen.
    func reveal(_ folder: Folder?) {
        var node = folder
        var depth = 0
        var changed = false
        while let current = node, depth < 64 {
            changed = expanded.insert(current.id).inserted || changed
            node = current.parent
            depth += 1
        }
        if changed { save() }
    }

    func collapseAll() {
        expanded = []
        save()
    }

    private func save() {
        AppEnvironment.defaults.set(expanded.map(\.uuidString), forKey: Self.key)
    }
}
