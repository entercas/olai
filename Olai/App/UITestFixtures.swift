import Foundation
import OlaiCore
import SwiftData

/// The notes a UI test starts with. Small, but shaped like a real library: nested and
/// colour-tagged folders, a pinned page, a checklist, a page at the top level.
@MainActor
enum UITestFixtures {
    static func seed(_ context: ModelContext) {
        let work = Folder(name: "Work", sortOrder: 0, colorIndex: 6)
        let q3 = Folder(name: "Q3", sortOrder: 0, parent: work)
        let personal = Folder(name: "Personal", sortOrder: 1, colorIndex: 4)
        [work, q3, personal].forEach(context.insert)

        page("Kickoff", in: work, order: 0, pinned: true, markdown: """
        # Kickoff

        Agreed the **scope** for the quarter.

        - Ship the importer
        - Fix the tab bar
        """, context)
        page("Roadmap", in: work, order: 1, markdown: "## Next\n\nTabs, then colours.", context)
        page("Planning", in: q3, order: 0, markdown: "Planning notes for Q3.", context)
        page("Groceries", in: personal, order: 0, markdown: "- [ ] Milk\n- [x] Bread", context)
        scheduledTaskPage(in: personal, context)
        page("Inbox", in: nil, order: 0, markdown: "Loose thoughts go here.", context)

        try? context.save()
    }

    /// A task with a reminder on it. Built as the editor stores one rather than from
    /// Markdown, which has nowhere to put a reminder. The id is not a real reminder's,
    /// and nothing in a test schedules one: that would put an entry in the tester's own
    /// Reminders.
    private static func scheduledTaskPage(in folder: Folder, _ context: ModelContext) {
        let document: [String: Any] = [
            "type": "doc",
            "content": [[
                "type": "taskList",
                "content": [[
                    "type": "taskItem",
                    "attrs": ["checked": false, "reminderID": "fixture-reminder", "due": "Fri 25 Sep 09:00"],
                    "content": [["type": "paragraph", "content": [["type": "text", "text": "Call the bank"]]]],
                ]],
            ]],
        ]
        let body = (try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]))
            ?? TipTapDocument.emptyDocument
        context.insert(Page(
            title: "Errands",
            body: body,
            plainText: TipTapDocument.plainText(from: body) ?? "",
            sortOrder: 1,
            folder: folder
        ))
    }

    private static func page(
        _ title: String,
        in folder: Folder?,
        order: Int,
        pinned: Bool = false,
        markdown: String,
        _ context: ModelContext
    ) {
        let body = MarkdownParser.document(from: markdown)
        let page = Page(
            title: title,
            body: body,
            plainText: TipTapDocument.plainText(from: body) ?? "",
            isPinned: pinned,
            sortOrder: order,
            folder: folder
        )
        context.insert(page)
    }
}
