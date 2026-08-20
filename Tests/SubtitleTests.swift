import Foundation
import Testing
import Transcript

@Suite("Subtitles")
struct SubtitleTests {
    private func sentence(_ id: Int, _ text: String, _ start: Double, _ end: Double) -> Sentence {
        Sentence(id: id, text: text, start: start, end: end)
    }

    @Test("A stamp is two-digit hours and a comma before the milliseconds")
    func stamps() {
        #expect(Subtitles.stamp(0) == "00:00:00,000")
        #expect(Subtitles.stamp(62.5) == "00:01:02,500")
        #expect(Subtitles.stamp(3723.004) == "01:02:03,004")
    }

    @Test("A whole recording is timed from its start")
    func wholeRecording() {
        let text = Subtitles.subRip(of: [
            sentence(0, "First.", 0, 1.5),
            sentence(1, "Second.", 90, 92),
        ])
        #expect(text.contains("00:00:00,000 --> 00:00:01,500\nFirst."))
        #expect(text.contains("00:01:30,000 --> 00:01:32,000\nSecond."))
        #expect(text.hasPrefix("1\n"))
    }

    @Test("A clip's times are rebased onto the clip, not the recording")
    func clipIsRebased() {
        // Two spans, far apart in the source. In the cut they run back to back,
        // so the second sentence starts where the first span ended.
        let sentences = [
            sentence(0, "Kept early.", 10, 12),
            sentence(1, "Kept late.", 300, 303),
        ]
        let ranges = [TimeRange(start: 10, end: 12), TimeRange(start: 300, end: 303)]
        let text = Subtitles.subRip(of: sentences, in: ranges)

        #expect(text.contains("00:00:00,000 --> 00:00:02,000\nKept early."))
        #expect(text.contains("00:00:02,000 --> 00:00:05,000\nKept late."))
        // Nothing may still carry a source time.
        #expect(!text.contains("00:05:00"))
    }

    @Test("A gap inside one span is kept, because the cut keeps it too")
    func gapWithinASpanIsKept() {
        let sentences = [
            sentence(0, "One.", 10, 11),
            sentence(1, "Two.", 14, 15),
        ]
        let text = Subtitles.subRip(of: sentences, in: [TimeRange(start: 10, end: 15)])
        #expect(text.contains("00:00:00,000 --> 00:00:01,000\nOne."))
        #expect(text.contains("00:00:04,000 --> 00:00:05,000\nTwo."))
    }

    @Test("Numbering runs from one, in order")
    func numbering() {
        let text = Subtitles.subRip(of: [
            sentence(0, "A.", 0, 1),
            sentence(1, "B.", 1, 2),
            sentence(2, "C.", 2, 3),
        ])
        #expect(text.contains("\n1\n") || text.hasPrefix("1\n"))
        #expect(text.contains("\n2\n"))
        #expect(text.contains("\n3\n"))
    }
}
