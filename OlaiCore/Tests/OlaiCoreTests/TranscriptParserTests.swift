import Foundation
import Testing
@testable import OlaiCore

struct TranscriptParserTests {
    private let vtt = """
    WEBVTT

    NOTE recorded 2026-09-14 14:30

    1
    00:00:01.000 --> 00:00:04.000
    <v Priya>Shall we start with the mirror?

    2
    00:00:04.500 --> 00:00:09.000
    <v Rahul>Yes. The converter is done, the server is next.
    """

    private let srt = """
    1
    00:00:02,000 --> 00:00:05,000
    Priya: Shall we start with the mirror?

    2
    00:01:00,000 --> 00:01:04,000
    Rahul: The converter is done.
    """

    @Test func readsVTTCuesSpeakersAndTimes() {
        let parsed = TranscriptParser.parse(vtt, filename: "meeting.vtt")

        #expect(parsed.cues.count == 2)
        #expect(parsed.cues[0].speaker == "Priya")
        #expect(parsed.cues[0].text == "Shall we start with the mirror?")
        #expect(parsed.cues[0].start == 1)
        #expect(parsed.cues[1].start == 4.5)
        #expect(parsed.participants == ["Priya", "Rahul"])
    }

    @Test func readsSRTWithItsCommaTimestamps() {
        let parsed = TranscriptParser.parse(srt, filename: "call.srt")

        #expect(parsed.cues.count == 2)
        #expect(parsed.cues[1].start == 60)
        #expect(parsed.participants == ["Priya", "Rahul"])
    }

    @Test func readsPlainTextWithSpeakerLabels() {
        let parsed = TranscriptParser.parse("Priya: one\nRahul: two\nno label here", filename: "notes.txt")

        #expect(parsed.cues.map(\.text) == ["one", "two", "no label here"])
        #expect(parsed.cues[2].speaker == nil)
        #expect(parsed.participants == ["Priya", "Rahul"])
    }

    @Test func aSentenceWithAColonIsNotASpeaker() {
        let (speaker, text) = TranscriptParser.speakerAndText(
            in: "We agreed on this. Next: ship the thing."
        )
        #expect(speaker == nil)
        #expect(text == "We agreed on this. Next: ship the thing.")
    }

    @Test func timestampsParseFromBothFormats() {
        #expect(TranscriptParser.seconds(from: "00:00:01.500") == 1.5)
        #expect(TranscriptParser.seconds(from: "00:01:00,000") == 60)
        #expect(TranscriptParser.seconds(from: "01:02:03") == 3723)
        #expect(TranscriptParser.seconds(from: "nonsense") == nil)
        #expect(TranscriptParser.timing(in: "00:00:01.000 --> 00:00:04.000") == 1)
        #expect(TranscriptParser.timing(in: "just a line") == nil)
    }

    @Test func theFilenameDateWinsOverTheFileDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let modified = Date(timeIntervalSince1970: 0)

        let parsed = TranscriptParser.parse(
            "Priya: hello",
            filename: "standup 2026-09-14 09-30.vtt",
            modifiedAt: modified
        )
        let parts = calendar.dateComponents([.year, .month, .day], from: try #require(parsed.eventDate))
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 14)
    }

    @Test func aHeaderDateIsUsedWhenTheFilenameHasNone() throws {
        let parsed = TranscriptParser.parse(vtt, filename: "meeting.vtt")
        #expect(parsed.eventDate != nil)
    }

    @Test func withNoDateAnywhereTheFileDateIsUsed() {
        let modified = Date(timeIntervalSince1970: 1_000_000)
        let parsed = TranscriptParser.parse("hello there", filename: "chat.txt", modifiedAt: modified)
        #expect(parsed.eventDate == modified)
    }

    @Test func datesAreReadInSeveralShapes() throws {
        #expect(TranscriptParser.date(inText: "meeting-2026-09-14.vtt") != nil)
        #expect(TranscriptParser.date(inText: "20260914_1430 call.srt") != nil)
        #expect(TranscriptParser.date(inText: "no date at all") == nil)
        #expect(TranscriptParser.date(inText: "2026-13-45 impossible") == nil)
    }

    @Test func anEmptyFileParsesToNothing() {
        let parsed = TranscriptParser.parse("", filename: "empty.vtt")
        #expect(parsed.cues.isEmpty)
        #expect(parsed.participants.isEmpty)
    }
}
