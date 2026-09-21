import Foundation
import Testing
@testable import OlaiCore

struct UtteranceBoundaryTests {
    @Test func theFirstResultIsNeverANewUtterance() {
        var boundary = UtteranceBoundary()
        let first = boundary.isNewUtterance(transcript: "hello", startingAt: 0)
        #expect(!first)
    }

    @Test func growingTextRevisesWhatIsShown() {
        var boundary = UtteranceBoundary()
        _ = boundary.isNewUtterance(transcript: "Is the dictation", startingAt: 1)
        let grown = boundary.isNewUtterance(transcript: "Is the dictation working", startingAt: 1)
        #expect(!grown)
    }

    /// The case that defeated matching on leading characters.
    @Test func aRevisionOfTheOpeningWordsIsStillTheSameUtterance() {
        var boundary = UtteranceBoundary()
        _ = boundary.isNewUtterance(transcript: "He is a dictation working", startingAt: 2.0)
        let second = boundary.isNewUtterance(transcript: "He has a dictation working", startingAt: 2.0)
        let third = boundary.isNewUtterance(transcript: "How is the dictation working?", startingAt: 2.0)
        #expect(!second)
        #expect(!third)
    }

    @Test func aTranscriptThatNowStartsLaterInTheAudioIsNew() {
        var boundary = UtteranceBoundary()
        _ = boundary.isNewUtterance(transcript: "Take notes here", startingAt: 1.0)
        let next = boundary.isNewUtterance(transcript: "And trying", startingAt: 6.5)
        #expect(next)
    }

    /// The failure in the screen recording: every phrase replaced the one before it.
    @Test func eachPhraseInTheRecordingIsItsOwnUtterance() {
        var boundary = UtteranceBoundary()
        let phrases: [(String, TimeInterval)] = [
            ("Tak", 0.5),
            ("Take notes here", 0.5),
            ("And trying", 4.0),
            ("To show it in Lord", 9.0),
            ("And working through building", 15.0),
            ("And working through building of the app", 15.0),
        ]

        let boundaries = phrases.map { boundary.isNewUtterance(transcript: $0.0, startingAt: $0.1) }
        // "Take notes here" revises "Tak"; each later phrase starts a new utterance,
        // except the last, which extends the one before it.
        #expect(boundaries == [false, false, true, true, true, false])
    }

    @Test func timingsThatDoNotMoveKeepTheSameUtterance() {
        var boundary = UtteranceBoundary()
        _ = boundary.isNewUtterance(transcript: "one two", startingAt: 3.0)
        let jitter = boundary.isNewUtterance(transcript: "one two three", startingAt: 3.02)
        #expect(!jitter)
    }

    // MARK: Without timings

    @Test func withoutTimingsSomethingShorterAndUnrelatedIsNew() {
        var boundary = UtteranceBoundary()
        _ = boundary.isNewUtterance(transcript: "Take notes here", startingAt: nil)
        let shorter = boundary.isNewUtterance(transcript: "And trying", startingAt: nil)
        #expect(shorter)
    }

    @Test func withoutTimingsATrimmedRevisionIsNotNew() {
        var boundary = UtteranceBoundary()
        _ = boundary.isNewUtterance(transcript: "How is the dictation working", startingAt: nil)
        let trimmed = boundary.isNewUtterance(transcript: "How is the dictation", startingAt: nil)
        #expect(!trimmed)
    }

    @Test func withoutTimingsALongerRewriteIsTreatedAsARevision() {
        var boundary = UtteranceBoundary()
        _ = boundary.isNewUtterance(transcript: "It's late and", startingAt: nil)
        let rewritten = boundary.isNewUtterance(transcript: "It's latency not legacy", startingAt: nil)
        #expect(!rewritten)
    }

    @Test func resettingForgetsTheUtteranceOnScreen() {
        var boundary = UtteranceBoundary()
        _ = boundary.isNewUtterance(transcript: "something", startingAt: 4.0)
        boundary.reset()
        let afterReset = boundary.isNewUtterance(transcript: "fresh start", startingAt: 0)
        #expect(!afterReset)
    }
}
