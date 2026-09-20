import Foundation

/// A template as it is stored in `Resources/Templates/*.json`.
///
/// The body stays as raw TipTap JSON rather than a typed tree: the app hands it straight
/// to the editor, and nothing here needs to understand the block schema.
public struct NoteTemplate: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable {
        case page
        case folder
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let titlePattern: String
    public let body: Data?
    public let pages: [NoteTemplate]

    public init(
        id: String,
        name: String,
        kind: Kind,
        titlePattern: String,
        body: Data? = nil,
        pages: [NoteTemplate] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.titlePattern = titlePattern
        self.body = body
        self.pages = pages
    }
}

public enum TemplateError: Error, Equatable {
    case notAnObject
    case missingField(String)
    case unknownKind(String)
}

public enum TemplateLibrary {
    /// Every template in a directory, in name order.
    public static func load(from directory: URL) throws -> [NoteTemplate] {
        let urls = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        return try load(urls: urls)
    }

    /// Every template at the given file URLs, in name order. The app's templates are
    /// flattened into the bundle, so it looks them up by name rather than by directory.
    public static func load(urls: [URL]) throws -> [NoteTemplate] {
        try urls
            .map { try decode(Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func decode(_ data: Data) throws -> NoteTemplate {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TemplateError.notAnObject
        }
        return try template(from: object)
    }

    private static func template(from object: [String: Any]) throws -> NoteTemplate {
        guard let id = object["id"] as? String else { throw TemplateError.missingField("id") }
        guard let name = object["name"] as? String else { throw TemplateError.missingField("name") }
        guard let rawKind = object["kind"] as? String else { throw TemplateError.missingField("kind") }
        guard let kind = NoteTemplate.Kind(rawValue: rawKind) else {
            throw TemplateError.unknownKind(rawKind)
        }
        guard let titlePattern = object["titlePattern"] as? String else {
            throw TemplateError.missingField("titlePattern")
        }

        let body = (object["body"] as? [String: Any]).flatMap {
            try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])
        }
        let pages = try (object["pages"] as? [[String: Any]] ?? []).map(template(from:))

        return NoteTemplate(
            id: id,
            name: name,
            kind: kind,
            titlePattern: titlePattern,
            body: body,
            pages: pages
        )
    }
}

// MARK: - Title patterns

public extension TemplateLibrary {
    /// Fills `{{weekOf}}`, `{{date}}` and `{{time}}` in a title pattern.
    static func title(
        from pattern: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        // Formatting follows the calendar it was given, time zone included: a caller
        // that passes a UTC calendar should not get yesterday's date back.
        var day = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        day.locale = locale
        day.calendar = calendar
        day.timeZone = calendar.timeZone

        var clock = Date.FormatStyle.dateTime.hour().minute()
        clock.locale = locale
        clock.calendar = calendar
        clock.timeZone = calendar.timeZone

        let weekOf = monday(of: now, calendar: calendar).formatted(day)
        let date = now.formatted(day)
        let time = now.formatted(clock)

        return pattern
            .replacingOccurrences(of: "{{weekOf}}", with: weekOf)
            .replacingOccurrences(of: "{{date}}", with: date)
            .replacingOccurrences(of: "{{time}}", with: time)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The Monday of the week containing `date`. Weekly pages use it for both the title
    /// and `periodStart`, so the two have to agree.
    static func monday(of date: Date, calendar: Calendar = .current) -> Date {
        var week = calendar
        week.firstWeekday = 2 // Monday, whatever the locale would otherwise pick
        return week.dateInterval(of: .weekOfYear, for: date)?.start ?? week.startOfDay(for: date)
    }
}
