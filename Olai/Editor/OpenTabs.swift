import Foundation
import Observation

/// Which pages are open in the detail column, and which of them is in front.
///
/// Opening a page that is already open brings it forward rather than opening it twice,
/// so clicking around the page list does not fill the bar with duplicates.
@MainActor
@Observable
final class OpenTabs {
    private static let storageKey = "editor.openTabs"
    private static let activeKey = "editor.activeTab"
    /// Enough to be useful, few enough that they all fit the row: the bar shares its
    /// width between tabs rather than scrolling, and ten at their narrowest still fit
    /// the detail column at the window's minimum size. Opening past this closes the
    /// least recently used tab rather than refusing.
    private static let limit = 10

    private(set) var ids: [UUID] = []
    private(set) var active: UUID?

    /// Most recently looked at first, for deciding what to drop at the limit.
    @ObservationIgnored private var recency: [UUID] = []

    init() { restore() }

    func open(_ id: UUID) {
        if !ids.contains(id) {
            ids.append(id)
            if ids.count > Self.limit, let oldest = recency.last(where: { $0 != id }) {
                ids.removeAll { $0 == oldest }
                recency.removeAll { $0 == oldest }
            }
        }
        activate(id)
    }

    func activate(_ id: UUID) {
        active = id
        recency.removeAll { $0 == id }
        recency.insert(id, at: 0)
        save()
    }

    /// Closing the page in front moves to its neighbour rather than to nothing, so the
    /// column does not empty out mid-read.
    func close(_ id: UUID) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.remove(at: index)
        recency.removeAll { $0 == id }

        if active == id {
            active = ids.indices.contains(index) ? ids[index] : ids.last
        }
        save()
    }

    func closeOthers(than id: UUID) {
        ids = ids.filter { $0 == id }
        recency = recency.filter { $0 == id }
        active = ids.first
        save()
    }

    func closeAll() {
        ids = []
        recency = []
        active = nil
        save()
    }

    /// Called when pages disappear underneath -- deleted, or archived out of view.
    func keepOnly(_ existing: Set<UUID>) {
        let kept = ids.filter { existing.contains($0) }
        guard kept.count != ids.count else { return }
        ids = kept
        recency = recency.filter { existing.contains($0) }
        if let active, !existing.contains(active) { self.active = kept.last }
        save()
    }

    // MARK: Persistence

    private func save() {
        let defaults = AppEnvironment.defaults
        defaults.set(ids.map(\.uuidString), forKey: Self.storageKey)
        defaults.set(active?.uuidString, forKey: Self.activeKey)
    }

    private func restore() {
        let defaults = AppEnvironment.defaults
        ids = (defaults.stringArray(forKey: Self.storageKey) ?? []).compactMap(UUID.init(uuidString:))
        active = defaults.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))
        // A stored active tab that is not in the list would leave the bar with nothing
        // selected and the editor showing a page no tab points at.
        if let active, !ids.contains(active) { self.active = ids.last }
        recency = ids.reversed()
    }
}
