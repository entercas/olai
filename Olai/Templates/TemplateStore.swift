import Foundation
import OlaiCore

/// The templates shipped in the app bundle.
///
/// Resources are flattened into the bundle, so they are found by name rather than by
/// walking `Resources/Templates`.
@MainActor
enum TemplateStore {
    private static let names = ["weekly", "ai-prompt", "interview", "project", "transcript", "goals"]

    static let all: [NoteTemplate] = {
        let urls = names.compactMap { Bundle.main.url(forResource: $0, withExtension: "json") }
        do {
            return try TemplateLibrary.load(urls: urls)
        } catch {
            NSLog("Olai: could not load templates: \(error)")
            return []
        }
    }()

    static func template(id: String) -> NoteTemplate? {
        all.first { $0.id == id }
    }
}
