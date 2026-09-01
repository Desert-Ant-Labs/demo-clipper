import Foundation
import Testing
import Title
import Transcript

private func sentences(_ count: Int, spacing: Double = 10) -> [Sentence] {
    (0..<count).map { index in
        Sentence(
            id: index,
            text: "Sentence \(index).",
            start: Double(index) * spacing,
            end: Double(index) * spacing + 4
        )
    }
}

private func made(_ keep: [Int], of spoken: [Sentence], titled title: String? = nil) -> Pick {
    var pick = Pick(
        Clip(
            id: 0,
            sentenceIDs: keep,
            text: keep.compactMap { spoken.indices.contains($0) ? spoken[$0].text : nil }
                .joined(separator: " "),
            score: 0.5,
            percentile: 0.5,
            estimatedDurationSec: Double(keep.count) * 4
        )
    )
    if let title { pick.card = Card(title: title, description: "A description.") }
    return pick
}

@Suite("Pick")
struct PickTests {
    @Test("Each kept sentence becomes its own range, so pauses are cut out")
    func dropsSilenceBetweenSentences() {
        // Sentences run 4s with a 6s pause between them.
        let pick = made([1, 2, 3], of: sentences(10))

        #expect(pick.ranges(in: sentences(10)).count == 3)
        #expect(pick.duration(in: sentences(10)) < 15)
    }

    @Test("Sentences spoken back to back stay one range")
    func mergesTouchingSentences() {
        // Spacing equals sentence length, so each sentence starts as the last ends.
        let spoken = sentences(3, spacing: 4)

        #expect(made([0, 1, 2], of: spoken).ranges(in: spoken).count == 1)
    }

    @Test("A deselected sentence leaves the cut but the model's pick still stands")
    func deselectingASentenceRecutsTheClip() throws {
        let spoken = sentences(10)
        var pick = made([1, 2, 3], of: spoken)
        let full = pick.duration(in: spoken)

        pick.selectedSentenceIDs.remove(2)

        #expect(pick.clip.sentenceIDs == [1, 2, 3])
        #expect(pick.keptSentenceIDs == [1, 3])
        #expect(pick.includes(2) == false)
        #expect(pick.ranges(in: spoken).count == 2)
        #expect(pick.duration(in: spoken) < full)
        #expect(pick.text(in: spoken) == "Sentence 1. Sentence 3.")
    }

    @Test("Sentences the transcript does not have are dropped rather than trapped on")
    func ignoresKeepsOutsideTheTranscript() {
        let pick = made([0, 2, 99], of: sentences(3))

        #expect(pick.ranges(in: sentences(3)).count == 2)
        #expect(pick.text(in: sentences(3)) == "Sentence 0. Sentence 2.")
    }
}

@Suite("Cards")
struct CardTests {
    @Test("A clip is real before it has been named, and says which one it is")
    func standsWithoutACard() {
        let pick = made([0, 1], of: sentences(4))

        #expect(pick.card == nil)
        #expect(pick.displayTitle == "Clip 1")
        #expect(pick.ranges(in: sentences(4)).count == 2)
    }

    @Test("The placeholder counts from one, since a rank counts from zero")
    func numbersThePlaceholderForReading() {
        var pick = Pick(
            Clip(id: 4, sentenceIDs: [0], text: "Sentence 0.", score: 0.5,
                 percentile: 0.5, estimatedDurationSec: 4)
        )

        #expect(pick.displayTitle == "Clip 5")
        pick.card = Card(title: "The Pricing Mistake", description: "What it cost.")
        #expect(pick.displayTitle == "The Pricing Mistake")
    }
}

@Suite("Time labels")
struct TimeLabelTests {
    @Test("Minutes and seconds, widening past an hour", arguments: [
        (0.0, "0:00"), (4.0, "0:04"), (64.0, "1:04"), (3599.0, "59:59"),
        (3600.0, "1:00:00"), (3661.0, "1:01:01"),
    ])
    func formatsClockTimes(seconds: Double, expected: String) {
        #expect(seconds.formattedDuration == expected)
    }

    @Test("Times that carry no value do not trap")
    func survivesNonNumericTimes() {
        #expect(Double.nan.formattedDuration == "0:00")
        #expect(Double.infinity.formattedDuration == "0:00")
        #expect((-5.0).formattedDuration == "0:00")
    }
}

@Suite("Export names")
struct ExportNameTests {
    private func named(_ title: String) -> Pick {
        made([0], of: sentences(2), titled: title)
    }

    @Test("Numbered and padded so a folder sorts in the order they were found")
    func padsTheNumberToTheTotal() {
        let pick = named("Pricing")

        #expect(pick.fileName(number: 3, of: 5) == "03-pricing")
        #expect(pick.fileName(number: 9, of: 12) == "09-pricing")
        #expect(pick.fileName(number: 10, of: 12) == "10-pricing")
        #expect(pick.fileName(number: 1, of: 100) == "001-pricing")
    }

    @Test("One clip on its own carries no number to keep it apart from")
    func oneClipIsNotNumbered() {
        #expect(named("Pricing").fileName(number: 1, of: 1) == "pricing")
    }

    @Test("Slugs come off the title, and never come out empty")
    func slugsTheTitle() {
        #expect(named("The Pricing Mistake!").slug == "the-pricing-mistake")
        #expect(named("  Spaced   out  ").slug == "spaced-out")
        #expect(named("!!!").slug == "clip")
        #expect(named(String(repeating: "a", count: 200)).slug.count == 60)
    }

    @Test("A clip with no title still exports under a name that says which it is")
    func namesAnUnwrittenClip() {
        let pick = Pick(
            Clip(id: 2, sentenceIDs: [0], text: "Sentence 0.", score: 0.5,
                 percentile: 0.5, estimatedDurationSec: 4)
        )

        #expect(pick.slug == "clip-3")
        #expect(pick.fileName(number: 3, of: 4) == "03-clip-3")
    }

    @Test("Repeated titles stay apart, because the writer repeats them")
    func separatesRepeatedTitles() {
        let first = named("AI Product Iteration Loop")
        let second = named("AI Product Iteration Loop")

        #expect(first.fileName(number: 2, of: 5) != second.fileName(number: 4, of: 5))
    }

    @Test("A title cut at the limit does not end on the separator")
    func trimsTheDanglingSeparator() {
        let awkward = named(String(repeating: "ab ", count: 40))

        #expect(awkward.slug.count <= 60)
        #expect(!awkward.slug.hasSuffix("-"))
    }
}
