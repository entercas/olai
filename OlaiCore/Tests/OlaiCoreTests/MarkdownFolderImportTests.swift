import Foundation
import SwiftData
import Testing
@testable import OlaiCore

@MainActor
struct MarkdownFolderImportTests {
    private func context() throws -> ModelContext {
        try ModelContext(ModelContainer(
            for: OlaiSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
    }

    /// A folder shaped the way a OneNote converter would leave one: sections as
    /// directories, pages as files, images beside them.
    private func fixture() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "import-\(UUID().uuidString)/Notebook")
        let manager = FileManager.default
        try manager.createDirectory(at: root.appending(path: "Biology/media"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appending(path: "Chemistry"), withIntermediateDirectories: true)

        try """
        # Cell Structure

        The **nucleus** holds the DNA.

        - Mitochondria
          - Produces ATP
        - [x] Read chapter 3

        ![Cell diagram](media/cell.png)
        """.write(to: root.appending(path: "Biology/Cells.md"), atomically: true, encoding: .utf8)

        try "# Genetics\n\n1. Mendel\n2. Punnett"
            .write(to: root.appending(path: "Biology/Genetics.md"), atomically: true, encoding: .utf8)

        try """
        ---
        id: 11111111-2222-3333-4444-555555555555
        title: "Kickoff — Q3"
        template: "weekly"
        created: 2026-03-01T09:00:00Z
        updated: 2026-03-02T10:30:00Z
        period_start: 2026-03-01T00:00:00Z
        pinned: true
        archived: false
        ---

        ## Priorities

        - Ship it
        """.write(to: root.appending(path: "Chemistry/Kickoff.md"), atomically: true, encoding: .utf8)

        // A real PNG, so the importer has bytes to read rather than a stub.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        try png.write(to: root.appending(path: "Biology/media/cell.png"))

        // Not Markdown: must be ignored rather than imported as a page.
        try "ignore me".write(to: root.appending(path: "Biology/notes.txt"), atomically: true, encoding: .utf8)

        return root
    }

    @Test func directoriesBecomeFoldersAndFilesBecomePages() throws {
        let context = try context()
        let summary = try MarkdownFolderImport.importFolder(at: fixture(), into: nil, context: context)

        #expect(summary.pages == 3)
        // Notebook, Biology, Chemistry -- "media" holds no Markdown so it makes no folder.
        #expect(summary.folders == 3)
        #expect(summary.skipped.isEmpty)

        let folders = try context.fetch(FetchDescriptor<Folder>())
        #expect(Set(folders.map(\.name)) == ["Notebook", "Biology", "Chemistry"])

        let biology = try #require(folders.first { $0.name == "Biology" })
        #expect(biology.parent?.name == "Notebook")
        #expect(Set(biology.sortedPages.map(\.title)) == ["Cell Structure", "Genetics"])
    }

    @Test func aTitleComesFromTheFirstHeadingWhenThereIsNoFrontmatter() throws {
        let context = try context()
        try MarkdownFolderImport.importFolder(at: fixture(), into: nil, context: context)

        let pages = try context.fetch(FetchDescriptor<Page>())
        // The file is Cells.md but the heading says Cell Structure.
        #expect(pages.contains { $0.title == "Cell Structure" })
        #expect(!pages.contains { $0.title == "Cells" })
    }

    @Test func frontmatterIsHonouredSoAMirrorFolderRoundTrips() throws {
        let context = try context()
        try MarkdownFolderImport.importFolder(at: fixture(), into: nil, context: context)

        let pages = try context.fetch(FetchDescriptor<Page>())
        let kickoff = try #require(pages.first { $0.title == "Kickoff — Q3" })
        #expect(kickoff.templateID == "weekly")
        #expect(kickoff.isPinned)
        #expect(!kickoff.isArchived)
        #expect(kickoff.periodStart != nil)
        #expect(kickoff.createdAt < kickoff.updatedAt)
    }

    @Test func imagesAreReadInAsAttachmentsAndTheBodyPointsAtThem() throws {
        let context = try context()
        let summary = try MarkdownFolderImport.importFolder(at: fixture(), into: nil, context: context)
        #expect(summary.images == 1)

        let pages = try context.fetch(FetchDescriptor<Page>())
        let cells = try #require(pages.first { $0.title == "Cell Structure" })
        let attachment = try #require(cells.attachments?.first)
        #expect(attachment.mimeType == "image/png")
        #expect((attachment.data?.count ?? 0) > 0)

        // The document must reference the attachment, not the path on disk, or the page
        // breaks as soon as the imported folder is deleted.
        let body = try #require(cells.body)
        let referenced = try #require(TipTapDocument.attachmentIDs(in: body))
        #expect(referenced == [attachment.id])
    }

    @Test func markdownStructureSurvivesTheImport() throws {
        let context = try context()
        try MarkdownFolderImport.importFolder(at: fixture(), into: nil, context: context)

        let pages = try context.fetch(FetchDescriptor<Page>())
        let genetics = try #require(pages.first { $0.title == "Genetics" })
        let markdown = MarkdownConverter.markdown(from: try #require(genetics.body))
        #expect(markdown.contains("1. Mendel"))
        #expect(markdown.contains("2. Punnett"))
        #expect(genetics.plainText.contains("Mendel"))
    }

    /// The mirror is what Olai writes; importing it back would make a second copy of
    /// every page, and the copies would themselves be exported.
    @Test func importingTheMirrorBackIntoItselfIsRefused() throws {
        let root = try fixture()
        #expect(throws: MarkdownFolderImport.Failure.self) {
            try MarkdownFolderImport.importFolder(
                at: root.appending(path: "Biology"),
                into: nil,
                context: try context(),
                mirrorRoot: root
            )
        }
    }

    @Test func aFolderWithNoMarkdownSaysSoRatherThanMakingAnEmptyFolder() throws {
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let context = try context()
        #expect(throws: MarkdownFolderImport.Failure.self) {
            try MarkdownFolderImport.importFolder(at: empty, into: nil, context: context)
        }
        #expect(try context.fetch(FetchDescriptor<Folder>()).isEmpty)
    }
}
