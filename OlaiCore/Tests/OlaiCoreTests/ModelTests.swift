import Foundation
import SwiftData
import Testing
@testable import OlaiCore

@MainActor
struct ModelTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: OlaiSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func schemaBuildsInMemory() throws {
        let context = try makeContext()
        let folder = Folder(name: "Work")
        context.insert(folder)
        let page = Page(title: "Notes", folder: folder)
        context.insert(page)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())
        #expect(folders.count == 1)
        #expect(folders.first?.sortedPages.map(\.title) == ["Notes"])
    }

    @Test func settingBodyTextUpdatesDerivedFields() throws {
        let context = try makeContext()
        let page = Page(title: "Notes")
        context.insert(page)
        let before = page.updatedAt

        page.setBodyText("hello\nworld", now: before.addingTimeInterval(10))

        #expect(page.plainText == "hello\nworld")
        #expect(page.bodyText == "hello\nworld")
        #expect(page.updatedAt > before)
    }

    @Test func pathComponentsWalkUpTheTree() throws {
        let context = try makeContext()
        let root = Folder(name: "Work")
        let child = Folder(name: "Projects", parent: root)
        context.insert(root)
        context.insert(child)
        #expect(child.pathComponents == ["Work", "Projects"])
    }

    @Test func containsDetectsDescendants() throws {
        let context = try makeContext()
        let root = Folder(name: "Work")
        let child = Folder(name: "Projects", parent: root)
        let sibling = Folder(name: "Personal")
        context.insert(root)
        context.insert(child)
        context.insert(sibling)
        try context.save()

        #expect(root.contains(child))
        #expect(root.contains(root))
        #expect(!root.contains(sibling))
        #expect(!child.contains(root))
    }

    @Test func aFolderCannotMoveIntoItsOwnSubtree() throws {
        let context = try makeContext()
        let root = Folder(name: "Work")
        let child = Folder(name: "Projects", parent: root)
        let grandchild = Folder(name: "Olai", parent: child)
        let other = Folder(name: "Personal")
        for folder in [root, child, grandchild, other] { context.insert(folder) }
        try context.save()

        #expect(!root.canBeMoved(to: root))
        #expect(!root.canBeMoved(to: child))
        #expect(!root.canBeMoved(to: grandchild))
        #expect(root.canBeMoved(to: other))
    }

    @Test func movingWhereItAlreadySitsIsNotAMove() throws {
        let context = try makeContext()
        let root = Folder(name: "Work")
        let child = Folder(name: "Projects", parent: root)
        let sibling = Folder(name: "Archive", parent: root)
        for folder in [root, child, sibling] { context.insert(folder) }
        try context.save()

        #expect(!child.canBeMoved(to: root))
        #expect(child.canBeMoved(to: sibling))
        #expect(child.canBeMoved(to: nil))
        #expect(!root.canBeMoved(to: nil))
    }

    @Test func pinnedPagesSortFirst() throws {
        let pinned = Page(title: "Zebra", isPinned: true)
        let plain = Page(title: "Alpha")
        #expect([plain, pinned].sorted(by: Page.displayOrder).map(\.title) == ["Zebra", "Alpha"])
    }
}
