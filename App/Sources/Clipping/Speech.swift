import Foundation
import Voz
import Transcript

/// Transcribes with Voz, on device.
///
/// The model is downloaded on first use and cached by the SDK. One is held in
/// memory and reused, so the wait happens once per launch rather than once per
/// video.
actor Speech {
    /// How far a transcription has got. Loading runs to completion before
    /// reading starts, and the fraction restarts at 0 in each.
    enum Progress: Sendable, Equatable {
        case loading(fraction: Double)
        case reading(fraction: Double)
    }

    /// A folder holding the model files, or `nil` to let the SDK fetch and
    /// cache them itself.
    private let directory: URL?
    /// A transcript and how fast it was produced.
    struct Transcript: Sendable {
        let words: [TimedWord]

        /// How long the recording is.
        let mediaSeconds: Double

        /// Wall clock spent reading it.
        let readingSeconds: Double

        /// Seconds of audio read per second of wall clock.
        let realtimeFactor: Double
    }

    private var voz: Voz?

    init(directory: URL? = nil) {
        self.directory = directory
    }

    /// Loads the model without transcribing anything.
    func prepare(
        progress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws {
        _ = try await recognizer(progress: progress)
    }

    func transcribe(
        _ url: URL,
        progress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws -> Transcript {
        let voz = try await recognizer(progress: progress)
        let result = try await voz.transcribe(url) { done in
            progress(.reading(fraction: done.fractionCompleted))
        }
        let words = Self.spaced(result.words)
        guard !words.isEmpty else { throw SpeechError.noSpeech }
        return Transcript(
            words: words,
            mediaSeconds: result.duration,
            readingSeconds: result.processingTime,
            realtimeFactor: result.realtimeFactor
        )
    }

    /// The SDK's `TimedWord` carries its own surrounding whitespace, which is
    /// Whisper's convention. Voz emits bare words, so the separator is put
    /// back here or the sentences run together.
    private static func spaced(_ words: [Word]) -> [TimedWord] {
        words.enumerated().map { index, word in
            let joined = index > 0 && word.text.first?.isPunctuation != true
            return TimedWord(text: joined ? " " + word.text : word.text,
                             start: word.start, end: word.end)
        }
    }

    private func recognizer(
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws -> Voz {
        if let voz { return voz }
        // A directory of our own is loaded as-is. The downloading init resolves
        // the model's `main` revision against the Hub first, which is a network
        // call even when every file is already on disk.
        let voz = if let directory {
            try Voz(modelDirectory: directory)
        } else {
            try await Voz { fetched in
                progress(.loading(fraction: fetched.fraction))
            }
        }
        self.voz = voz
        return voz
    }
}
