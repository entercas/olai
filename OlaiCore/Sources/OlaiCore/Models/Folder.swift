import Foundation
import SwiftData

/// A node in the note tree. Folders nest arbitrarily deep via `parent`/`children`.
///
/// CloudKit rules observed throughout the model layer: every stored property has a
/// default value or is optional, every relationship is optional, and no property is
/// marked `@Attribute(.unique)`.
@Model
public final class Folder {
    public var id: UUID = UUID()
    public var name: String = ""
    public var sortOrder: Int = 0
    public var isArchived: Bool = false
    public var createdAt: Date = Date()

    public var parent: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    public var children: [Folder]?

    @Relationship(deleteRule: .cascade, inverse: \Page.folder)
    public var pages: [Page]?

    public init(
        id: UUID = UUID(),
        name: String = "",
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        parent: Folder? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.parent = parent
    }
}

public extension Folder {
    /// Child folders in display order: sort order first, then name.
    var sortedChildren: [Folder] {
        (children ?? []).sorted(by: Folder.displayOrder)
    }

    /// Pages in display order: pinned first, then sort order, then title.
    var sortedPages: [Page] {
        (pages ?? []).sorted(by: Page.displayOrder)
    }

    /// Path components from the root down to and including this folder.
    var pathComponents: [String] {
        var components: [String] = []
        var node: Folder? = self
        var guardCount = 0
        while let current = node, guardCount < 64 {
            components.insert(current.name, at: 0)
            node = current.parent
            guardCount += 1
        }
        return components
    }

    /// True when `candidate` is this folder or one of its descendants. Used to stop a
    /// move from parenting a folder inside its own subtree.
    ///
    /// Depth-limited like `pathComponents`, and for the same reason. Moves made here
    /// cannot build a cycle, but two devices can: one parents A under B while the other
    /// parents B under A, each legal on its own, and CloudKit merges them into a loop.
    /// Recursing into that never returns.
    func contains(_ candidate: Folder, depth: Int = 0) -> Bool {
        if candidate.id == id { return true }
        guard depth < 64 else { return false }
        return (children ?? []).contains { $0.contains(candidate, depth: depth + 1) }
    }

    /// Whether this folder may become a child of `destination` (nil meaning the top
    /// level). A folder cannot move into itself or into one of its own descendants --
    /// that would cut the branch loose from the tree -- and moving it where it already
    /// sits is not a move at all.
    func canBeMoved(to destination: Folder?) -> Bool {
        guard let destination else { return parent != nil }
        if destination.id == id { return false }
        if contains(destination) { return false }
        return parent?.id != destination.id
    }

    static func displayOrder(_ lhs: Folder, _ rhs: Folder) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
