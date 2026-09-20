import Foundation
import Testing
@testable import OlaiCore

struct TemplateTests {
    private let weekly = Data("""
    {
      "id": "weekly",
      "name": "Weekly page",
      "kind": "page",
      "titlePattern": "Week of {{weekOf}}",
      "body": {"type": "doc", "content": [{"type": "paragraph"}]}
    }
    """.utf8)

    @Test func decodesAPageTemplate() throws {
        let template = try TemplateLibrary.decode(weekly)
        #expect(template.id == "weekly")
        #expect(template.kind == .page)
        #expect(template.titlePattern == "Week of {{weekOf}}")
        #expect(template.pages.isEmpty)
        #expect(TipTapDocument.plainText(from: try #require(template.body)) == "")
    }

    @Test func decodesAFolderTemplateWithItsPages() throws {
        let data = Data("""
        {
          "id": "project", "name": "Project", "kind": "folder", "titlePattern": "Project",
          "pages": [
            {"id": "overview", "name": "Overview", "kind": "page", "titlePattern": "Overview"},
            {"id": "decisions", "name": "Decisions", "kind": "page", "titlePattern": "Decisions"}
          ]
        }
        """.utf8)

        let template = try TemplateLibrary.decode(data)
        #expect(template.kind == .folder)
        #expect(template.pages.map(\.id) == ["overview", "decisions"])
        #expect(template.pages.allSatisfy { $0.kind == .page })
    }

    @Test func rejectsATemplateMissingAField() throws {
        let data = Data(#"{"id": "x", "name": "X", "kind": "page"}"#.utf8)
        #expect(throws: TemplateError.missingField("titlePattern")) {
            try TemplateLibrary.decode(data)
        }
    }

    @Test func rejectsAnUnknownKind() throws {
        let data = Data(#"{"id":"x","name":"X","kind":"diagram","titlePattern":"X"}"#.utf8)
        #expect(throws: TemplateError.unknownKind("diagram")) {
            try TemplateLibrary.decode(data)
        }
    }

    @Test func mondayIsTheStartOfTheWeekWhateverTheLocalePrefers() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        // A Sunday, which several locales treat as the first day of the week.
        let sunday = try #require(
            DateComponents(calendar: calendar, year: 2026, month: 9, day: 20).date
        )

        let monday = TemplateLibrary.monday(of: sunday, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: monday)
        #expect(parts.weekday == 2)
        #expect(parts.day == 14)
        #expect(parts.month == 9)
    }

    @Test func mondayOfAMondayIsThatSameDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let monday = try #require(
            DateComponents(calendar: calendar, year: 2026, month: 9, day: 14, hour: 15).date
        )

        let start = TemplateLibrary.monday(of: monday, calendar: calendar)
        #expect(calendar.dateComponents([.day], from: start).day == 14)
        #expect(start <= monday)
    }

    @Test func titlePatternsAreFilledIn() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(
            DateComponents(calendar: calendar, year: 2026, month: 9, day: 20, hour: 9, minute: 30).date
        )
        let locale = Locale(identifier: "en_US_POSIX")

        let title = TemplateLibrary.title(
            from: "Week of {{weekOf}}",
            now: now,
            calendar: calendar,
            locale: locale
        )
        #expect(title.hasPrefix("Week of "))
        #expect(title.contains("14"))
        #expect(!title.contains("{{"))

        let stamped = TemplateLibrary.title(
            from: "{{date}} {{time}}",
            now: now,
            calendar: calendar,
            locale: locale
        )
        #expect(!stamped.contains("{{"))
        #expect(stamped.contains("20"))
    }
}
