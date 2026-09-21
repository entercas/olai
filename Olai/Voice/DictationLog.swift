import Foundation

/// A temporary record of what speech recognition actually reports, so the rule for
/// splitting utterances can be based on its behaviour rather than on assumptions about
/// it. Written to `Application Support/dictation-log.txt` inside the app's container.
///
/// Remove this once the boundary rule is settled.
enum DictationLog {
    private static let url: URL? = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "dictation-log.txt")
    }()

    static func start(_ note: String) {
        append("\n=== \(note) at \(Date().formatted(date: .omitted, time: .standard)) ===")
    }

    static func result(
        generation: Int,
        isFinal: Bool,
        segments: [(start: Double, duration: Double, text: String)],
        transcript: String
    ) {
        let first = segments.first.map { String(format: "%.2f", $0.start) } ?? "-"
        let last = segments.last.map { String(format: "%.2f", $0.start + $0.duration) } ?? "-"
        append(
            "task=\(generation) final=\(isFinal ? 1 : 0) segs=\(segments.count) "
                + "span=\(first)..\(last) | \(transcript)"
        )
    }

    private static func append(_ line: String) {
        guard let url else { return }
        let data = Data((line + "\n").utf8)

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
