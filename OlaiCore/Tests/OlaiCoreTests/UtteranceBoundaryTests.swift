import Foundation
import Testing
@testable import OlaiCore

/// Cases drawn from real dictation sessions: each name says which failure it guards.
struct UtteranceBoundaryTests {
    private func boundaries(_ transcripts: [String]) -> [Bool] {
        var boundary = UtteranceBoundary()
        return transcripts.map { boundary.isNewUtterance(transcript: $0) }
    }

    @Test func theFirstResultIsNeverNew() {
        #expect(boundaries(["hello"]) == [false])
    }

    @Test func growingTextRevisesWhatIsShown() {
        #expect(boundaries(["Is the dictation", "Is the dictation working"]) == [false, false])
    }

    @Test func aTrimmedResultStillRevises() {
        #expect(boundaries(["How is the dictation working", "How is the dictation"]) == [false, false])
    }

    /// Recording one: separate phrases, each replacing the last, losing every one.
    @Test func separatePhrasesAreSeparateUtterances() {
        let spoken = ["Take notes here", "And trying", "To show it in Lord"]
        #expect(boundaries(spoken) == [false, true, true])
    }

    /// Recording two: one sentence revised as it was spoken, appended three times.
    @Test func aLongSentenceBeingRevisedStaysOneUtterance() {
        let spoken = [
            "OK, so which model are you currently using? I'm using Gwen three",
            "OK, so which model are you currently using? I'm using 305 the nine",
            "OK, so which model are you currently using? I'm using 3.5 to 9,000,000,000 parameter",
        ]
        #expect(boundaries(spoken) == [false, false, false])
    }

    /// The session before those: the opening words themselves were revised.
    @Test func aRewrittenOpeningIsStillTheSameUtterance() {
        let spoken = [
            "He is a dictation working",
            "He has a dictation working",
            "How is the dictation working?",
        ]
        #expect(boundaries(spoken) == [false, false, false])
    }

    @Test func unrelatedSentencesAreSeparate() {
        let spoken = ["this is the first thing I said", "and here is the second thing"]
        #expect(boundaries(spoken) == [false, true])
    }

    @Test func resettingForgetsWhatWasShown() {
        var boundary = UtteranceBoundary()
        _ = boundary.isNewUtterance(transcript: "something entirely different")
        boundary.reset()
        let afterReset = boundary.isNewUtterance(transcript: "fresh start")
        #expect(!afterReset)
    }

    // MARK: The measures themselves

    @Test func sharedOpeningIsAFractionOfTheShorterText() {
        #expect(UtteranceBoundary.sharedOpeningRatio("abcdef", "abcxyz") == 0.5)
        #expect(UtteranceBoundary.sharedOpeningRatio("abc", "xyz") == 0)
        #expect(UtteranceBoundary.sharedOpeningRatio("", "abc") == 0)
    }

    @Test func wordSimilarityIgnoresCaseAndPunctuation() {
        #expect(UtteranceBoundary.wordSimilarity("Hello, world!", "hello world") == 1)
        #expect(UtteranceBoundary.wordSimilarity("one two three", "four five six") == 0)
        #expect(UtteranceBoundary.wordSimilarity("", "anything") == 0)
    }

    @Test func sharedEndingIsAFractionOfTheShorterText() {
        #expect(UtteranceBoundary.sharedEndingRatio("xyzabc", "uvwabc") == 0.5)
        #expect(UtteranceBoundary.sharedEndingRatio("abc", "xyz") == 0)
    }

    /// A rewritten opening keeps the ending that was just heard.
    @Test func aRewrittenOpeningKeepsItsEnding() {
        let ratio = UtteranceBoundary.sharedEndingRatio(
            "He has a dictation working",
            "How is the dictation working"
        )
        #expect(ratio >= 0.5)
    }

    @Test func wordSimilaritySeesThroughARewrittenOpening() {
        let score = UtteranceBoundary.wordSimilarity(
            "He is a dictation working",
            "How is the dictation working"
        )
        #expect(score >= 0.6)
    }
}
