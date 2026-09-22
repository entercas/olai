import Foundation
import SwiftData
import Testing
@testable import OlaiCore

@MainActor
struct MirrorFileTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: OlaiSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func pathIsFolderPathTitleAndShortID() throws {
        let context = try makeContext()
        let work = Folder(name: "Work")
        let projects = Folder(name: "Projects", parent: work)
        let page = Page(
            id: UUID(uuidString: "5D470D12-0E29-4E7B-8B96-66B3FA8E4ED4")!,
            title: "Week of Sep 14",
            folder: projects
        )
        [work, projects].forEach(context.insert)
        context.insert(page)

        #expect(MirrorFile.relativePath(for: page) == "Work/Projects/Week of Sep 14-5d470d12.md")
    }

    @Test func archivedPagesGoUnderArchive() throws {
        let context = try makeContext()
        let work = Folder(name: "Work")
        let page = Page(title: "Old notes", isArchived: true, folder: work)
        context.insert(work)
        context.insert(page)

        #expect(MirrorFile.relativePath(for: page).hasPrefix("_archive/Work/"))
    }

    @Test func titlesThatWouldBreakAPathAreSanitised() {
        #expect(MirrorFile.sanitize("Q3/Q4: plans") == "Q3-Q4- plans")
        #expect(MirrorFile.sanitize("  spaced   out  ") == "spaced out")
        #expect(MirrorFile.sanitize("") == "untitled")
        #expect(MirrorFile.sanitize("...") == "untitled")
        // A title is attacker-controllable in the sense that it can be typed, pasted
        // or arrive over CloudKit; it must never climb out of the mirror directory.
        #expect(!MirrorFile.sanitize("../../../etc/passwd").contains("/"))
        #expect(!MirrorFile.sanitize("..\\..\\Windows").contains("\\"))
        #expect(!MirrorFile.sanitize("../../../etc/passwd").hasPrefix("."))
        #expect(MirrorFile.sanitize(String(repeating: "a", count: 200)).count <= 80)
    }

    @Test func frontmatterCarriesEveryFieldTheSpecLists() throws {
        let context = try makeContext()
        let folder = Folder(name: "Work")
        let page = Page(
            title: "Weekly: notes",
            templateID: "weekly",
            isPinned: true,
            periodStart: Date(timeIntervalSince1970: 0),
            goalIDs: ["goal-1"],
            folder: folder
        )
        context.insert(folder)
        context.insert(page)

        let front = MirrorFile.frontmatter(for: page)
        for field in ["id:", "title:", "template:", "folder:", "created:", "updated:",
                      "period_start:", "event_date:", "goals:", "archived:", "pinned:"] {
            #expect(front.contains(field), "missing \(field)")
        }
        #expect(front.contains("title: \"Weekly: notes\""))
        #expect(front.contains("template: \"weekly\""))
        #expect(front.contains("folder: \"Work\""))
        #expect(front.contains("event_date: null"))
        #expect(front.contains("goals: [\"goal-1\"]"))
        #expect(front.contains("pinned: true"))
        #expect(front.contains("archived: false"))
    }

    @Test func contentsAreFrontmatterThenMarkdown() throws {
        let context = try makeContext()
        let page = Page(title: "Notes")
        page.body = Data("""
        {"type":"doc","content":[
          {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Wins"}]}
        ]}
        """.utf8)
        context.insert(page)

        let contents = MirrorFile.contents(for: page)
        #expect(contents.hasPrefix("---\n"))
        #expect(contents.contains("\n---\n"))
        #expect(contents.hasSuffix("## Wins\n"))
    }

    /// The exporter deletes any attachment file this list does not name, so it has to
    /// name every attachment the page actually has, and agree with where each was written.
    @Test func attachmentPathsCoverEveryAttachmentThePageHas() throws {
        let context = try ModelContext(ModelContainer(
            for: OlaiSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
        let folder = Folder(name: "Work")
        let page = Page(title: "Notes", folder: folder)
        context.insert(folder)
        context.insert(page)

        let withBytes = Attachment(mimeType: "image/png", data: Data([0x1]), page: page)
        let withoutBytes = Attachment(mimeType: "image/png", data: nil, page: page)
        context.insert(withBytes)
        context.insert(withoutBytes)

        let paths = MirrorFile.attachmentPaths(for: page)

        #expect(paths == [MirrorFile.attachmentRelativePath(for: withBytes, page: page)])
        // An attachment with no bytes is never written, so claiming it would keep a
        // file that does not exist -- and a file that does exist must be claimed.
        #expect(!paths.contains(MirrorFile.attachmentRelativePath(for: withoutBytes, page: page)))
    }

    @Test func attachmentsAreWrittenBesideTheirPage() throws {
        let context = try makeContext()
        let folder = Folder(name: "Work")
        let page = Page(title: "Notes", folder: folder)
        let attachment = Attachment(
            id: UUID(uuidString: "43A23507-C8EC-42CD-8A54-379AFD9D735B")!,
            mimeType: "image/jpeg",
            page: page
        )
        context.insert(folder)
        context.insert(page)
        context.insert(attachment)

        let path = MirrorFile.attachmentRelativePath(for: attachment, page: page)
        #expect(path == "Work/attachments/43A23507-C8EC-42CD-8A54-379AFD9D735B.jpg")
    }

    @Test func mimeTypesMapToExtensions() {
        #expect(MirrorFile.fileExtension(forMimeType: "image/png") == "png")
        #expect(MirrorFile.fileExtension(forMimeType: "image/JPEG") == "jpg")
        #expect(MirrorFile.fileExtension(forMimeType: "application/octet-stream") == "png")
    }
}
