import Foundation

/// Decides whether a speech result revises what is on screen or starts something new.
///
/// Recognition gives a revisable guess at what is being said, and neither `isFinal` nor
/// the segment timings mark where one run of speech ends and the next begins:
///
/// - Speaking a second sentence after a pause can report a transcript that starts over,
///   with no final for the first. Replacing then loses the first sentence.
/// - Speaking continuously reports a growing transcript whose segment timings advance as
///   earlier words are confirmed. Treating that as new text appends the same sentence
///   again and again.
///
/// So the text itself is compared: what carries over at the start, what carries over at
/// the end, and how many words survive in order.
///
/// What separates the two is how much of the text carries over. A revision keeps most of
/// it -- the same words, in order, with an ending changed or added. A new run of speech
/// shares almost nothing. Where the answer is unclear this keeps both, since repeated
/// words can be deleted but lost words cannot be recovered.
public struct UtteranceBoundary: Sendable {
    /// What the editor is showing.
    public private(set) var shownText: String = ""

    public init() {}

    /// Records a result, returning true when it begins a new utterance.
    public mutating func isNewUtterance(transcript: String, startingAt _: TimeInterval? = nil) -> Bool {
        defer { shownText = transcript }

        let previous = shownText.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previous.isEmpty, !next.isEmpty else { return false }

        // Simply carrying on: the commonest case by far.
        if next.hasPrefix(previous) || previous.hasPrefix(next) { return false }

        if Self.sharedOpeningRatio(previous, next) >= Self.overlapThreshold { return false }
        // A recogniser that re-guesses the opening usually keeps the ending it had just
        // heard: "He has a dictation working" becomes "How is the dictation working?".
        if Self.sharedEndingRatio(previous, next) >= Self.overlapThreshold { return false }
        return Self.wordSimilarity(previous, next) < Self.similarityThreshold
    }

    /// Forgets the utterance on screen, for a new recognition task.
    public mutating func reset() {
        self = UtteranceBoundary()
    }

    // MARK: Comparing

    /// How much of the shorter text the two share from the start.
    ///
    /// Compared without case or punctuation: recognition adds and removes commas and
    /// question marks as it goes, and a trailing "?" should not read as a new sentence.
    public static func sharedOpeningRatio(_ a: String, _ b: String) -> Double {
        let first = normalized(a)
        let second = normalized(b)
        return ratio(zip(first, second).prefix { $0 == $1 }.count, first, second)
    }

    /// How much of the shorter text the two share at the end.
    public static func sharedEndingRatio(_ a: String, _ b: String) -> Double {
        let first = normalized(a)
        let second = normalized(b)
        return ratio(zip(first.reversed(), second.reversed()).prefix { $0 == $1 }.count, first, second)
    }

    private static func ratio(_ shared: Int, _ a: String, _ b: String) -> Double {
        let shortest = min(a.count, b.count)
        return shortest == 0 ? 0 : Double(shared) / Double(shortest)
    }

    /// Lowercased, punctuation dropped, runs of space collapsed.
    private static func normalized(_ text: String) -> String {
        words(text).joined(separator: " ")
    }

    /// How many words the two have in common, in order, as a fraction of their length.
    /// Catches a revision that rewrites the opening — "He is a" becoming "How is the" —
    /// which shares no useful prefix but nearly every other word.
    public static func wordSimilarity(_ a: String, _ b: String) -> Double {
        let first = words(a)
        let second = words(b)
        guard !first.isEmpty, !second.isEmpty else { return 0 }

        var table = Array(
            repeating: Array(repeating: 0, count: second.count + 1),
            count: first.count + 1
        )
        for i in 1...first.count {
            for j in 1...second.count {
                table[i][j] = first[i - 1] == second[j - 1]
                    ? table[i - 1][j - 1] + 1
                    : max(table[i - 1][j], table[i][j - 1])
            }
        }

        let common = Double(table[first.count][second.count])
        return 2 * common / Double(first.count + second.count)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static let overlapThreshold = 0.5
    private static let similarityThreshold = 0.6
}
