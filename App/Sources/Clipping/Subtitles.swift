import Foundation
import Transcript

/// A transcript as SubRip, which is what every editor and every video host
/// reads.
enum Subtitles {
    /// Subtitles for a whole recording, timed from its start.
    static func subRip(of sentences: [Sentence]) -> String {
        text(sentences.map { (start: $0.start, end: $0.end, text: $0.text) })
    }

    /// Subtitles for one clip, timed against the clip's own mp4 rather than
    /// the recording it came from.
    ///
    /// A clip is a composition of `ranges`, so everything between them is cut
    /// and the times have to be rebased onto what is left. Timing them from
    /// the recording would put every line late by however much was dropped
    /// before it.
    static func subRip(of sentences: [Sentence], in ranges: [TimeRange]) -> String {
        var elapsed = 0.0
        var lines: [Line] = []
        for range in ranges {
            for sentence in sentences
            where sentence.start >= range.start && sentence.start < range.end {
                let start = elapsed + (sentence.start - range.start)
                let end = elapsed + (min(sentence.end, range.end) - range.start)
                lines.append((start: start, end: max(start, end), text: sentence.text))
            }
            elapsed += range.duration
        }
        return text(lines)
    }

    private typealias Line = (start: Double, end: Double, text: String)

    private static func text(_ lines: [Line]) -> String {
        lines.enumerated().map { index, line in
            """
            \(index + 1)
            \(stamp(line.start)) --> \(stamp(line.end))
            \(line.text)

            """
        }.joined(separator: "\n")
    }

    /// `00:01:02,500`. SubRip wants two-digit hours and a comma before the
    /// milliseconds, not the point every other format uses.
    static func stamp(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let whole = Int(total)
        let milliseconds = Int(((total - Double(whole)) * 1000).rounded())
        return String(
            format: "%02d:%02d:%02d,%03d",
            whole / 3600, whole / 60 % 60, whole % 60, min(999, milliseconds)
        )
    }
}
