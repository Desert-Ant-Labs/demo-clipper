import AVFoundation
import Foundation
import Transcript

/// Cuts a source down to a set of spans, to write out or to play.
///
/// The SDK hands back the spans and stops there, so laying them end to end is
/// this app's job. The same composition serves both, so a preview plays what an
/// export writes.
enum Cutting {
    /// Writes the spans as an MP4 and returns where it landed, which is `url`
    /// unless something was already there.
    @discardableResult
    static func write(_ source: URL, ranges: [TimeRange], to url: URL) async throws -> URL {
        guard Storage.hasRoom() else {
            throw SpeechError.outOfSpace(free: Storage.freeSpaceLabel())
        }
        let composition = try await composition(of: AVURLAsset(url: source), keeping: ranges)
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CuttingError.exportUnavailable
        }

        let destination = firstFreeName(from: url)
        do {
            try await session.export(to: destination, as: .mp4)
        } catch where Storage.isFull(error) {
            try? FileManager.default.removeItem(at: destination)
            throw SpeechError.outOfSpace(free: Storage.freeSpaceLabel())
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw CuttingError.exportFailed(reason(error))
        }
        return destination
    }

    /// Exporting twice into the same folder steps aside the way the Finder
    /// does, rather than replacing what is there.
    static func firstFreeName(from url: URL) -> URL {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path(percentEncoded: false)) else { return url }

        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let type = url.pathExtension

        for attempt in 2...9999 {
            let candidate = folder
                .appending(path: "\(stem)-\(attempt)")
                .appendingPathExtension(type)
            if !manager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        return url
    }

    /// Lays the spans of `asset` end to end, playable as it is.
    static func composition(
        of asset: AVAsset,
        keeping ranges: [TimeRange]
    ) async throws -> AVComposition {
        let composition = AVMutableComposition()
        let sourceVideo = try await asset.loadTracks(withMediaType: .video).first
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        guard sourceVideo != nil || sourceAudio != nil else {
            throw CuttingError.noPlayableTrack
        }
        let sourceRange = try await CMTimeRange(start: .zero, duration: asset.load(.duration))

        let video = sourceVideo.flatMap { _ in
            composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }
        let audio = sourceAudio.flatMap { _ in
            composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        var cursor = CMTime.zero
        for range in ranges {
            let span = CMTimeRange(
                start: CMTime(seconds: range.start, preferredTimescale: 600),
                duration: CMTime(seconds: range.duration, preferredTimescale: 600)
            ).intersection(sourceRange)
            guard span.duration > .zero else { continue }

            if let sourceVideo, let video {
                try video.insertTimeRange(span, of: sourceVideo, at: cursor)
            }
            if let sourceAudio, let audio {
                try audio.insertTimeRange(span, of: sourceAudio, at: cursor)
            }
            cursor = cursor + span.duration
        }

        // Carries the source's rotation, so portrait footage stays portrait.
        if let sourceVideo, let video {
            video.preferredTransform = try await sourceVideo.load(.preferredTransform)
        }
        return composition
    }

    /// Where a source time lands in the cut, with the dropped spans closed up.
    static func offset(of time: Double, in ranges: [TimeRange]) -> Double {
        var cursor = 0.0
        for range in ranges {
            if time >= range.start, time <= range.end { return cursor + (time - range.start) }
            cursor += range.duration
        }
        return 0
    }
}
