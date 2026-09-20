import Foundation

/// Turns a parsed transcript into the body of a `transcript` page.
public enum TranscriptDocument {
    public static func body(
        for transcript: ParsedTranscript,
        title: String,
        locale: Locale = .current
    ) -> Data {
        var blocks: [[String: Any]] = []

        blocks += section("Title", [paragraph(title)])
        blocks += section("Date/time", [paragraph(dateText(transcript.eventDate, locale: locale))])

        let participants = transcript.participants.isEmpty
            ? [paragraph("")]
            : [bulletList(transcript.participants)]
        blocks += section("Participants", participants)

        let lines = transcript.cues.map { paragraph(line(for: $0)) }
        blocks += section("Transcript", lines.isEmpty ? [paragraph("")] : lines)

        blocks += section("Summary", [paragraph("")])
        blocks += section("Actions", [taskList(count: 3)])

        let document: [String: Any] = ["type": "doc", "content": blocks]
        return (try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]))
            ?? TipTapDocument.emptyDocument
    }

    /// `[mm:ss] Speaker: what they said`, dropping whichever parts are missing.
    public static func line(for cue: TranscriptCue) -> String {
        var parts: [String] = []
        if let start = cue.start { parts.append("[\(timestamp(start))]") }
        if let speaker = cue.speaker { parts.append("\(speaker):") }
        parts.append(cue.text)
        return parts.joined(separator: " ")
    }

    public static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    private static func dateText(_ date: Date?, locale: Locale) -> String {
        guard let date else { return "" }
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year().hour().minute()
        style.locale = locale
        return date.formatted(style)
    }

    // MARK: Blocks

    private static func section(_ heading: String, _ content: [[String: Any]]) -> [[String: Any]] {
        [
            [
                "type": "heading",
                "attrs": ["level": 2],
                "content": [["type": "text", "text": heading]],
            ]
        ] + content
    }

    private static func paragraph(_ text: String) -> [String: Any] {
        var node: [String: Any] = ["type": "paragraph"]
        if !text.isEmpty {
            node["content"] = [["type": "text", "text": text]]
        }
        return node
    }

    private static func bulletList(_ items: [String]) -> [String: Any] {
        [
            "type": "bulletList",
            "content": items.map { ["type": "listItem", "content": [paragraph($0)]] },
        ]
    }

    private static func taskList(count: Int) -> [String: Any] {
        [
            "type": "taskList",
            "content": (0..<count).map { _ in
                ["type": "taskItem", "attrs": ["checked": false], "content": [paragraph("")]]
            },
        ]
    }
}
