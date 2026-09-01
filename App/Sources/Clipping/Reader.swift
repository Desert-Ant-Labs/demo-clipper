import AVFoundation
import Foundation
import Transcript

/// Turns a video into a sentence transcript with source timings, on device.
///
/// Splitting goes through the SDK's `Sentence`, so every consumer of the core
/// hands the clip model the same transcript.
struct Reader: Sendable {
    /// The recognizer, held rather than made per read: it keeps the loaded
    /// model.
    let speech: Speech

    /// Where a read has got to. Pulling the audio out of the container is a
    /// step of its own, and long enough on a large recording to count.
    enum Stage: Sendable, Equatable {
        case extractingAudio(fraction: Double)
        case loadingSpeech(fraction: Double)
        case transcribing(fraction: Double)
    }

    init(speech: Speech? = nil) {
        self.speech = speech ?? Speech(directory: ModelLocations.resolved.voz)
    }

    /// Loads the model without transcribing anything.
    func prepare(
        progress: @escaping @Sendable (Speech.Progress) -> Void = { _ in }
    ) async throws {
        try await speech.prepare(progress: progress)
    }

    func read(
        _ asset: AVURLAsset,
        progress: @escaping @Sendable (Stage) -> Void = { _ in }
    ) async throws -> Reading {
        let needs = await Self.audioSize(of: asset)
        guard Storage.hasRoom(for: needs) else {
            throw SpeechError.outOfSpace(
                needs: Storage.demand(needs), free: Storage.freeSpaceLabel()
            )
        }
        // Voz reads an audio file, and a video container is not one.
        let extracting = Date()
        let audio = try await extractAudio(from: asset, progress: progress)
        let extractingSeconds = -extracting.timeIntervalSinceNow
        defer { try? FileManager.default.removeItem(at: audio) }

        // Said here rather than left to the recognizer's first callback: a
        // loaded model reports nothing until it has read something, and the
        // step before this one would go on claiming to be running until then.
        progress(.transcribing(fraction: 0))

        let transcript = try await speech.transcribe(audio) {
            progress(Stage($0))
        }
        let sentences = Sentence.sentences(from: transcript.words)
        guard !sentences.isEmpty else { throw SpeechError.noSpeech }

        return Reading(
            sentences: sentences,
            timings: Reading.Timings(
                extractingSeconds: extractingSeconds,
                mediaSeconds: transcript.mediaSeconds,
                readingSeconds: transcript.readingSeconds,
                realtimeFactor: transcript.realtimeFactor
            )
        )
    }

    /// Writes the asset's audio to a temporary file for Voz to read.
    private func extractAudio(
        from asset: AVURLAsset,
        progress: @escaping @Sendable (Stage) -> Void
    ) async throws -> URL {
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw SpeechError.noAudioTrack
        }
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw SpeechError.audioExtractionFailed
        }
        let url = URL.temporaryDirectory.appending(path: "clipper-\(UUID().uuidString).m4a")
        // The sequence is taken here because the session cannot cross tasks.
        let states = session.states(updateInterval: 0.2)
        let watcher = Task {
            for await state in states {
                guard case .exporting(let done) = state else { continue }
                progress(.extractingAudio(fraction: done.fractionCompleted))
            }
        }
        defer { watcher.cancel() }

        do {
            try await session.export(to: url, as: .m4a)
        } catch where Storage.isFull(error) {
            throw SpeechError.outOfSpace(
                needs: Storage.demand(await Self.audioSize(of: asset)),
                free: Storage.freeSpaceLabel()
            )
        }
        return url
    }

    /// Roughly what the extracted audio takes: a megabyte a minute, at the
    /// bitrate the extractor writes.
    ///
    /// Best effort. A recording this cannot measure still reaches the reader,
    /// which has a real sentence for why it could not be read.
    static func audioSize(of asset: AVURLAsset) async -> Int64 {
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64(seconds / 60 * 1_000_000)
    }
}

extension Reader.Stage {
    init(_ progress: Speech.Progress) {
        self = switch progress {
        case .loading(let fraction): .loadingSpeech(fraction: fraction)
        case .reading(let fraction): .transcribing(fraction: fraction)
        }
    }
}
