#if os(macOS)

import Foundation
import Observation

/// Where the Markdown mirror is written.
///
/// The app is sandboxed, so the root is whatever folder the user picked, kept as a
/// security-scoped bookmark. The panel starts at `~/Olai`, the spec's default, but the
/// folder has to be chosen once before anything can be written there.
@MainActor
@Observable
final class MirrorSettings {
    private static let bookmarkKey = "mirror.rootBookmark"

    private(set) var root: URL?
    /// Why the last attempt to set a root failed, shown in Settings: a mirror that
    /// silently does nothing is worse than one that says what went wrong.
    private(set) var lastError: String?
    @ObservationIgnored private var accessedRoot: URL?

    /// The folder the "choose" panel should open on.
    var suggestedRoot: URL {
        URL.homeDirectory.appending(path: "Olai", directoryHint: .isDirectory)
    }

    init() {
        restore()
    }

    func choose(_ url: URL) {
        lastError = nil

        // Access has to be open before the bookmark is made: a URL from the file
        // importer is security-scoped, and bookmarking one that has not been opened
        // fails with "the file couldn't be opened".
        beginAccess(to: url)

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            AppEnvironment.defaults.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            // Without a bookmark the choice cannot survive a relaunch, though it still
            // mirrors for this run.
            lastError = "Could not remember this folder: \(error.localizedDescription)"
        }
    }

    func clear() {
        endAccess()
        AppEnvironment.defaults.removeObject(forKey: Self.bookmarkKey)
        root = nil
    }

    private func restore() {
        guard let bookmark = AppEnvironment.defaults.data(forKey: Self.bookmarkKey) else { return }

        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else {
            AppEnvironment.defaults.removeObject(forKey: Self.bookmarkKey)
            return
        }

        beginAccess(to: url)
        if isStale { choose(url) }
    }

    /// A URL straight from the open panel is already accessible, and answers false to
    /// `startAccessingSecurityScopedResource`; only a URL resolved from a bookmark has
    /// to be opened for access. Either way the folder becomes the root -- refusing it
    /// on a false here left the mirror switched off after the user had chosen a folder.
    private func beginAccess(to url: URL) {
        endAccess()
        if url.startAccessingSecurityScopedResource() {
            accessedRoot = url
        }
        root = url
    }

    private func endAccess() {
        accessedRoot?.stopAccessingSecurityScopedResource()
        accessedRoot = nil
    }
}

#endif
