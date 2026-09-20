import Foundation
import Testing
@testable import OlaiCore

struct TranscriptDocumentTests {
    private let transcript = ParsedTranscript(
        cues: [
            TranscriptCue(start: 1, speaker: "Priya", text: "Shall we start?"),
            TranscriptCue(start: 65, speaker: "Rahul", text: "Yes."),
            TranscriptCue(start: nil, speaker: nil, text: "unattributed line"),
        ],
        participants: ["Priya", "Rahul"],
        eventDate: Date(timeIntervalSince1970: 1_757_000_000)
    )

    @Test func theBodyHasEverySectionTheTemplateDoes() throws {
        let data = TranscriptDocument.body(for: transcript, title: "Mirror sync")
        let text = try #require(TipTapDocument.plainText(from: data))

        for heading in ["Title", "Date/time", "Participants", "Transcript", "Summary", "Actions"] {
            #expect(text.contains(heading), "missing \(heading)")
        }
        #expect(text.contains("Mirror sync"))
        #expect(text.contains("Priya"))
    }

    @Test func cuesReadAsTimestampSpeakerText() {
        #expect(
            TranscriptDocument.line(for: transcript.cues[0]) == "[00:01] Priya: Shall we start?"
        )
        #expect(TranscriptDocument.line(for: transcript.cues[1]) == "[01:05] Rahul: Yes.")
        #expect(TranscriptDocument.line(for: transcript.cues[2]) == "unattributed line")
    }

    @Test func timestampsGrowAnHourFieldOnlyWhenNeeded() {
        #expect(TranscriptDocument.timestamp(5) == "00:05")
        #expect(TranscriptDocument.timestamp(605) == "10:05")
        #expect(TranscriptDocument.timestamp(3725) == "1:02:05")
    }

    @Test func anEmptyTranscriptStillProducesAUsablePage() throws {
        let empty = ParsedTranscript(cues: [], participants: [], eventDate: nil)
        let data = TranscriptDocument.body(for: empty, title: "Empty")
        let text = try #require(TipTapDocument.plainText(from: data))
        #expect(text.contains("Transcript"))
        #expect(text.contains("Actions"))
    }
}
