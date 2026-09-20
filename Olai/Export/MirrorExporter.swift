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
    private static let debounce = Duration.seconds(2)

    private let container: ModelContainer
    private let settings: MirrorSettings
    private var pending: Task<Void, Never>?

    /// page id → the relative path last written for it.
    private var ledger: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.ledgerKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.ledgerKey) }
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
        let previous = ledger

        for page in pages {
            let path = MirrorFile.relativePath(for: page)
            written[page.id.uuidString] = path

            do {
                try write(page: page, to: root.appending(path: path))
            } catch {
                NSLog("Olai mirror: could not write \(path): \(error)")
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

        ledger = written
    }

    // MARK: Files

    private func write(page: Page, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let contents = MirrorFile.contents(for: page)
        let existing = try? String(contentsOf: url, encoding: .utf8)
        if existing != contents {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        try writeAttachments(of: page, near: url)
    }

    private func writeAttachments(of page: Page, near pageURL: URL) throws {
        let attachments = (page.attachments ?? []).filter { $0.data != nil }
        guard !attachments.isEmpty else { return }

        let directory = pageURL
            .deletingLastPathComponent()
            .appending(path: MirrorFile.attachmentsDirectory, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for attachment in attachments {
            guard let data = attachment.data else { continue }
            let name = "\(attachment.id.uuidString).\(MirrorFile.fileExtension(forMimeType: attachment.mimeType))"
            let url = directory.appending(path: name)

            // Attachment bytes never change once written, so an existing file is right.
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try data.write(to: url, options: .atomic)
        }
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

#endif
