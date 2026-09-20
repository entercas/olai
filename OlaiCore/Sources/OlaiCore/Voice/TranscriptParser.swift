import Foundation

/// One line of a transcript.
public struct TranscriptCue: Equatable, Sendable {
    public let start: TimeInterval?
    public let speaker: String?
    public let text: String

    public init(start: TimeInterval? = nil, speaker: String? = nil, text: String) {
        self.start = start
        self.speaker = speaker
        self.text = text
    }
}

/// A transcript file, read into the parts a transcript page needs.
public struct ParsedTranscript: Equatable, Sendable {
    public let cues: [TranscriptCue]
    public let participants: [String]
    public let eventDate: Date?

    public init(cues: [TranscriptCue], participants: [String], eventDate: Date?) {
        self.cues = cues
        self.participants = participants
        self.eventDate = eventDate
    }
}

/// Reads `.vtt`, `.srt` and `.txt` transcripts.
///
/// The formats differ only in how they mark time, so one line reader handles all three:
/// timing lines set the clock, `Speaker:` prefixes and VTT voice tags name the speaker,
/// and everything else is what was said.
public enum TranscriptParser {
    public static func parse(
        _ contents: String,
        filename: String = "",
        modifiedAt: Date? = nil
    ) -> ParsedTranscript {
        var cues: [TranscriptCue] = []
        var speakers: [String] = []
        var pendingStart: TimeInterval?
        var headerDate: Date?

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty { continue }
            if line == "WEBVTT" || line.hasPrefix("WEBVTT ") { continue }
            if line.hasPrefix("NOTE") || line.hasPrefix("#") {
                headerDate = headerDate ?? date(inText: line)
                continue
            }
            // An SRT cue number on its own line.
            if Int(line) != nil { continue }

            if let start = timing(in: line) {
                pendingStart = start
                continue
            }

            let (speaker, text) = speakerAndText(in: line)
            guard !text.isEmpty else { continue }

            if let speaker, !speakers.contains(speaker) {
                speakers.append(speaker)
            }
            cues.append(TranscriptCue(start: pendingStart, speaker: speaker, text: text))
            pendingStart = nil
        }

        let eventDate = date(inText: filename)
            ?? headerDate
            ?? date(inText: contents.prefix(400).description)
            ?? modifiedAt

        return ParsedTranscript(cues: cues, participants: speakers, eventDate: eventDate)
    }

    // MARK: Lines

    /// The start time of a cue, from either a VTT (`00:00:01.000`) or an SRT
    /// (`00:00:01,000`) timing line.
    public static func timing(in line: String) -> TimeInterval? {
        guard line.contains("-->") else { return nil }
        let start = line
            .components(separatedBy: "-->")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return seconds(from: start)
    }

    public static func seconds(from stamp: String) -> TimeInterval? {
        let normalized = stamp.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.components(separatedBy: ":")
        guard (2...3).contains(parts.count) else { return nil }

        var total: TimeInterval = 0
        for part in parts {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// `Name: said this`, or VTT's `<v Name>said this`.
    public static func speakerAndText(in line: String) -> (speaker: String?, text: String) {
        if line.hasPrefix("<v ") , let close = line.firstIndex(of: ">") {
            let name = line[line.index(line.startIndex, offsetBy: 3)..<close]
                .trimmingCharacters(in: .whitespaces)
            let rest = String(line[line.index(after: close)...])
                .replacingOccurrences(of: "</v>", with: "")
                .trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? nil : name, rest)
        }

        // "Name: text", but not a stray colon in a sentence: a speaker label is short
        // and has no sentence punctuation before the colon.
        if let colon = line.firstIndex(of: ":") {
            let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let looksLikeName = !name.isEmpty
                && name.count <= 40
                && name.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?")) == nil
                && !rest.isEmpty
            if looksLikeName { return (name, rest) }
        }

        return (nil, stripTags(line))
    }

    private static func stripTags(_ line: String) -> String {
        line.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Dates

    /// A date written into a filename or a header: `2026-09-20`, `20260920`, or either
    /// followed by a time such as `14-30` or `1430`.
    public static func date(inText text: String, calendar: Calendar = .current) -> Date? {
        let patterns = [
            #"(\d{4})-(\d{2})-(\d{2})[ T_-]+(\d{2})[:.-](\d{2})"#,
            #"(\d{4})-(\d{2})-(\d{2})"#,
            #"(\d{4})(\d{2})(\d{2})[ T_-]+(\d{2})(\d{2})"#,
            #"(\d{4})(\d{2})(\d{2})"#,
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..., in: text)
                )
            else { continue }

            func number(_ index: Int) -> Int? {
                guard
                    index < match.numberOfRanges,
                    let range = Range(match.range(at: index), in: text)
                else { return nil }
                return Int(text[range])
            }

            guard
                let year = number(1), let month = number(2), let day = number(3),
                (1...12).contains(month), (1...31).contains(day)
            else { continue }

            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = number(4) ?? 0
            components.minute = number(5) ?? 0

            if let date = calendar.date(from: components) { return date }
        }
        return nil
    }
}
