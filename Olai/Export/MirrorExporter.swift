#if os(macOS)

import Foundation
import OlaiCore
import SwiftData

/// Writes the Markdown mirror. Export only: nothing here ever reads a file back into
/// the app.
///
/// Every file written is remembered, so a rename or a delete can clean up the file it
/// used to be. Files in the root that the mirror never wrote are left alone.
@MainActor
final class MirrorExporter {
    private static let ledgerKey = "mirror.writtenPaths"
    private static let attachmentLedgerKey = "mirror.writtenAttachmentPaths"
    private static let debounce = Duration.seconds(2)

    private let container: ModelContainer
    private let settings: MirrorSettings
    private var pending: Task<Void, Never>?

    /// page id → the relative path last written for it.
    private var ledger: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.ledgerKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.ledgerKey) }
    }

    /// page id → the attachment files last written for it. Kept separately from the
    /// page ledger because one page has many, and because a page can lose an attachment
    /// without moving: the file has to go even though the page's own path is unchanged.
    private var attachmentLedger: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: Self.attachmentLedgerKey) as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.attachmentLedgerKey) }
    }

    init(container: ModelContainer, settings: MirrorSettings) {
        self.container = container
        self.settings = settings
    }

    /// Coalesces the writes that follow a burst of edits.
    func scheduleExport() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.exportNow()
        }
    }

    func exportNow() {
        guard let root = settings.root else { return }

        let context = container.mainContext
        let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []

        var written: [String: String] = [:]
        var writtenAttachments: [String: [String]] = [:]
        let previous = ledger
        let previousAttachments = attachmentLedger

        var failed = false

        for page in pages {
            let path = MirrorFile.relativePath(for: page)
            written[page.id.uuidString] = path
            // Taken from the model rather than from the write: a page whose write fails
            // still claims its attachments, and must not have them swept as orphans.
            writtenAttachments[page.id.uuidString] = MirrorFile.attachmentPaths(for: page)

            do {
                try write(page: page, under: root, at: path)
            } catch {
                NSLog("Olai mirror: could not write \(path): \(error)")
                failed = true
            }

            // A rename or a move leaves the old file behind.
            if let old = previous[page.id.uuidString], old != path {
                remove(root.appending(path: old))
            }
        }

        // Pages that are gone take their files with them.
        for (id, path) in previous where written[id] == nil {
            remove(root.appending(path: path))
        }

        // So do attachments: deleted with their page, removed from a page that stayed,
        // or carried to a new path because the page moved. Without this the image
        // files outlived the note, which a deleted note is not supposed to do.
        for (id, paths) in previousAttachments {
            let current = Set(writtenAttachments[id] ?? [])
            for path in paths where !current.contains(path) {
                remove(root.appending(path: path))
            }
        }

        // Deleting files is only safe on a picture of the mirror we trust. If any page
        // failed to write, this pass does not know what is really out there, so the
        // sweep waits for an export that finishes cleanly.
        if !failed {
            sweepOrphanedAttachments(under: root, keeping: Set(writtenAttachments.values.joined()))
        }

        ledger = written
        attachmentLedger = writtenAttachments
    }

    /// Deletes attachment files no page claims any more.
    ///
    /// The ledger only knows about files this version wrote, so images orphaned before
    /// there was an attachment ledger -- or by a crash between writing a file and saving
    /// the ledger -- would otherwise sit in the mirror forever. Scoped tightly on
    /// purpose: only inside a folder the mirror itself creates, and only names shaped
    /// like the `<uuid>.<extension>` the mirror writes, so a file a person put there is
    /// left alone.
    private func sweepOrphanedAttachments(under root: URL, keeping current: Set<String>) {
        let manager = FileManager.default
        guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: nil) else { return }

        // Compared as resolved URLs rather than by trimming the root off each path:
        // a symlinked root, or one that resolves through /private, makes string
        // arithmetic silently disagree -- and here a disagreement deletes a live image.
        let keep = Set(current.map { root.appending(path: $0).standardizedFileURL.path })

        for case let url as URL in walker {
            guard
                url.deletingLastPathComponent().lastPathComponent == MirrorFile.attachmentsDirectory,
                UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                !keep.contains(url.standardizedFileURL.path)
            else { continue }

            remove(url)
        }
    }

    // MARK: Files

    /// Writes the page and its attachment files.
    private func write(page: Page, under root: URL, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let contents = MirrorFile.contents(for: page)
        let existing = try? String(contentsOf: url, encoding: .utf8)
        if existing != contents {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        try writeAttachments(of: page, under: root)
    }

    /// Paths come from `MirrorFile` rather than being rebuilt here, so what the sweep
    /// considers claimed and what lands on disk cannot drift apart.
    private func writeAttachments(of page: Page, under root: URL) throws {
        for attachment in (page.attachments ?? []) where attachment.data != nil {
            guard let data = attachment.data else { continue }
            let url = root.appending(path: MirrorFile.attachmentRelativePath(for: attachment, page: page))
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Attachment bytes never change once written, so an existing file is right.
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try data.write(to: url, options: .atomic)
        }
    }

    /// Removes a file, and the `attachments` folder it sat in once that folder is
    /// empty -- otherwise deleting every image leaves the directories behind.
    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)

        let parent = url.deletingLastPathComponent()
        guard parent.lastPathComponent == MirrorFile.attachmentsDirectory else { return }
        let remaining = try? FileManager.default.contentsOfDirectory(atPath: parent.path)
        if remaining?.isEmpty == true {
            try? FileManager.default.removeItem(at: parent)
        }
    }
}

#endif
