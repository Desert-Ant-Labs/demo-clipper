import AVFoundation
import Foundation
import Title
import Transcript

/// Fixtures for SwiftUI previews, so the app's views can be built and looked at
/// without a video, a transcript, or either model on hand.
extension Sentence {
    static let samples: [Sentence] = [
        "The bottleneck stops being compute. It becomes taste.",
        "We trained it overnight on a machine that cost less than a laptop.",
        "There is no inference bill, because nothing leaves the device.",
        "Which means the price of running it is the price of the hardware.",
        "And that changes what a small team can reasonably ship.",
    ].enumerated().map { index, text in
        Sentence(id: index, text: text, start: Double(index) * 6, end: Double(index) * 6 + 5)
    }
}

extension Clip {
    static func sample(id: Int, keeping sentenceIDs: [Int], score: Double, percentile: Double) -> Clip {
        Clip(
            id: id,
            sentenceIDs: sentenceIDs,
            text: sentenceIDs.map { Sentence.samples[$0].text }.joined(separator: " "),
            score: score,
            percentile: percentile,
            estimatedDurationSec: Double(sentenceIDs.count) * 5
        )
    }
}

extension Pick {
    static let sample = Pick(
        .sample(id: 0, keeping: [0, 1, 2], score: 0.81, percentile: 1),
        card: Card(
            title: "Taste Over Compute",
            description: "Training got cheap enough that judgment is the scarce part."
        )
    )

    /// The second has no card, as every clip does until the writer reaches it.
    static let samples: [Pick] = [
        sample,
        Pick(.sample(id: 1, keeping: [2, 3], score: 0.64, percentile: 0.5)),
    ]
}

extension SourceInfo {
    static let sample = SourceInfo(
        name: "Designing-on-device-Models.mp4",
        duration: CMTime(seconds: 428, preferredTimescale: 600),
        fileSize: 346_402_713,
        videoSize: CGSize(width: 1080, height: 1920),
        frameRate: 29.99,
        videoCodec: "HEVC",
        audioCodec: "AAC",
        sampleRate: 48000,
        channels: 2
    )
}

extension Reading {
    static let sample = Reading(
        sentences: Sentence.samples,
        timings: ClipperModel.Performance.sample.timings
    )
}

extension ClipperModel.Performance {
    static let sample = ClipperModel.Performance(
        timings: Reading.Timings(
            extractingSeconds: 0.58,
            mediaSeconds: 325,
            readingSeconds: 1.1,
            realtimeFactor: 295
        ),
        selectionSeconds: 3.3,
        cardSeconds: [0.19, 0.18]
    )
}
