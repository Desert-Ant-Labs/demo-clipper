import Foundation
import Title
import Transcript

/// A clip the model picked, the sentences kept from it, and the card written
/// for it.
///
/// The SDK's ``Clip`` is the model's answer and is never edited. A pick holds
/// one, plus what this app lets you change about it.
struct Pick: Identifiable, Sendable, Equatable {
    /// What the model picked, untouched.
    let clip: Clip

    /// `nil` until the writer reaches this clip, and after one that failed.
    var card: Card?

    /// What the clip currently uses. Starts as the pick and moves either way.
    var selectedSentenceIDs: Set<Int>

    var id: Clip.ID { clip.id }

    init(_ clip: Clip, card: Card? = nil) {
        self.clip = clip
        self.card = card
        self.selectedSentenceIDs = Set(clip.sentenceIDs)
    }

    /// The id of the pick standing for the whole recording. The model numbers
    /// its clips from zero, so a negative id cannot collide with one.
    static let wholeRecordingID = -1

    /// The whole recording as a pick, so the sidebar, the detail view and the
    /// subtitle export treat it exactly like a clip.
    ///
    /// It is never one of ``ClipperModel/picks``: it is not something the model
    /// chose, it has no card to write, and counting it would report one clip
    /// too many.
    static func wholeRecording(of sentences: [Sentence]) -> Pick {
        Pick(Clip(
            id: wholeRecordingID,
            sentenceIDs: sentences.map(\.id),
            text: sentences.map(\.text).joined(separator: " "),
            score: 0,
            percentile: 0,
            estimatedDurationSec: (sentences.last?.end ?? 0) - (sentences.first?.start ?? 0)
        ))
    }

    /// Whether this stands for the recording rather than a clip cut from it.
    var isWholeRecording: Bool { clip.id == Self.wholeRecordingID }

    /// The selection in source order.
    var keptSentenceIDs: [Int] {
        selectedSentenceIDs.sorted()
    }

    func includes(_ sentenceID: Int) -> Bool {
        selectedSentenceIDs.contains(sentenceID)
    }

    /// Source spans to cut, one per sentence so the pauses do not survive.
    /// Computed by the SDK, so an edited pick is cut like an unedited one.
    func ranges(in sentences: [Sentence]) -> [TimeRange] {
        edited(in: sentences).ranges(in: sentences)
    }

    /// Length of the assembled clip, which is shorter than the span it covers.
    func duration(in sentences: [Sentence]) -> Double {
        edited(in: sentences).duration(in: sentences)
    }

    /// The pick's transcript, joined from the sentences it keeps.
    func text(in sentences: [Sentence]) -> String {
        keptSentenceIDs
            .compactMap { sentences.indices.contains($0) ? sentences[$0].text : nil }
            .joined(separator: " ")
    }

    /// The clip as edited. Sentences the transcript does not have are dropped,
    /// so a pick over a stale transcript cuts short rather than trapping.
    private func edited(in sentences: [Sentence]) -> Clip {
        let kept = keptSentenceIDs.filter(sentences.indices.contains)
        return Clip(
            id: clip.id,
            sentenceIDs: kept,
            text: text(in: sentences),
            score: clip.score,
            percentile: clip.percentile,
            estimatedDurationSec: clip.estimatedDurationSec
        )
    }
}

extension Pick {
    /// A row label for a clip that is on screen before its title exists.
    var placeholderTitle: String { "Clip \(clip.id + 1)" }

    /// What to show: the written title where there is one.
    var displayTitle: String { card?.title ?? placeholderTitle }

    /// Lowercase, hyphenated form of the title, safe to use as a file name.
    var slug: String {
        var slug = String(
            displayTitle
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: "-")
                .prefix(60)
        )
        // Cutting at 60 can land mid-word and leave the separator dangling.
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "clip" : slug
    }

    /// `03-the-pricing-mistake`, padded so ten sorts after nine. The number is
    /// what keeps two clips apart, since titles repeat.
    func fileName(number: Int, of total: Int) -> String {
        let width = max(2, String(total).count)
        return String(format: "%0\(width)d-%@", number, slug)
    }
}
