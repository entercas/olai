import Foundation

/// Decides whether a speech result revises what is on screen or starts something new.
///
/// Speech recognition streams a revisable guess at the current run of speech, and
/// revises its opening words as readily as its closing ones -- "He is a" becomes "How
/// is the" -- so the words themselves cannot say where one utterance ends and the next
/// begins. Two signals can:
///
/// - Segment timings. Each segment carries where it sits in the task's audio, so a
///   transcript that now begins later than the one before it has dropped what came
///   earlier: that is a new utterance.
/// - Failing that, length. A revision grows or refines what was said; a recogniser that
///   has started over reports something shorter that is not a trimmed version of it.
public struct UtteranceBoundary: Sendable {
    /// Where the utterance on screen starts in the task's audio.
    public private(set) var start: TimeInterval = 0
    /// What the editor is showing.
    public private(set) var shownText: String = ""
    /// Whether any result has reported a time past the beginning. Until one does, a
    /// timing of zero could equally mean "starts at the beginning" or "not filled in",
    /// so the length rule decides instead.
    private var hasTimings = false

    public init() {}

    /// Records a result, returning true when it begins a new utterance.
    public mutating func isNewUtterance(transcript: String, startingAt segmentStart: TimeInterval?) -> Bool {
        defer { shownText = transcript }

        if let segmentStart, segmentStart > 0 { hasTimings = true }

        // The first result of a task is the utterance, not a new one -- but its start
        // has to be remembered, or the next result looks like a jump forward.
        guard !shownText.isEmpty else {
            start = segmentStart ?? 0
            return false
        }

        if hasTimings, let segmentStart {
            guard segmentStart > start + Self.tolerance else { return false }
            start = segmentStart
            return true
        }

        if transcript.hasPrefix(shownText) || shownText.hasPrefix(transcript) { return false }
        return transcript.count < shownText.count
    }

    /// Resets for a new recognition task.
    public mutating func reset() {
        self = UtteranceBoundary()
    }

    /// Segment timings wobble slightly between results for the same words.
    private static let tolerance: TimeInterval = 0.05
}
