import Foundation

/// Whether the app is running for a UI test, and where its preferences live.
///
/// Launched with `-OlaiUITesting`, the app uses an in-memory store seeded with fixture
/// notes and a preferences suite of its own that is wiped on every launch. That is not a
/// nicety: the mirror exporter deletes the Markdown file of any page it cannot find, so
/// a test run pointed at an empty store with the real mirror folder would delete the
/// real notes on disk. Here the test suite holds no mirror bookmark, so there is no
/// mirror at all.
enum AppEnvironment {
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-OlaiUITesting")

    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard isUITesting else { return .standard }
        let suite = "com.entercas.olai.uitesting"
        guard let store = UserDefaults(suiteName: suite) else { return .standard }
        // Every run starts from nothing, so a test cannot pass or fail because of what
        // the previous one left behind.
        store.removePersistentDomain(forName: suite)
        return store
    }()
}
