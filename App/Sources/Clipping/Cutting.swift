import AVFoundation
import Foundation
import OSLog
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
        let asset = AVURLAsset(url: source)
        let needs = await estimate(of: asset, keeping: ranges)
        guard Storage.hasRoom(for: needs) else {
            throw SpeechError.outOfSpace(
                needs: Storage.demand(needs), free: Storage.freeSpaceLabel()
            )
        }

        let composition: AVComposition
        do {
            composition = try await Self.composition(of: asset, keeping: ranges)
        } catch let error as CuttingError {
            throw error
        } catch {
            // A source that has been moved or deleted since it was opened
            // fails here, and AVFoundation's own words for it are "The
            // operation could not be completed".
            Logger.export.error("unreadable source: \(reason(error), privacy: .public)")
            throw CuttingError.unreadableSource
        }
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CuttingError.exportUnavailable
        }

        let destination = firstFreeName(from: url)
        Logger.export.info("writing a clip")
        do {
            try await session.export(to: destination, as: .mp4)
        } catch is CancellationError {
            // Someone asked for this to stop. Passed on as it is, so a caller
            // can tell being cancelled apart from going wrong.
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        } catch where Storage.isFull(error) {
            try? FileManager.default.removeItem(at: destination)
            throw SpeechError.outOfSpace(
                needs: Storage.demand(needs), free: Storage.freeSpaceLabel()
            )
        } catch {
            Logger.export.error("writing failed: \(reason(error), privacy: .public)")
            try? FileManager.default.removeItem(at: destination)
            throw CuttingError.exportFailed(reason(error))
        }
        Logger.export.info("wrote a clip")
        return destination
    }

    /// How long one clip is given before the wait is called a stall.
    ///
    /// A stalled export and a slow one look alike from here, so the allowance
    /// scales with the clip and starts generous. Reporting a stall late is
    /// better than calling a working export broken.
    static func allowance(for ranges: [TimeRange]) -> Int {
        let kept = ranges.reduce(0) { $0 + $1.duration }
        // `Int(_: Double)` traps on a value that is not finite, and a
        // malformed asset reports durations that are not.
        guard kept.isFinite, kept > 0 else { return floor }
        return max(floor, Int(min(kept * 20, Double(Int32.max))))
    }

    /// The least time any clip gets, however short it is.
    static let floor = 120

    /// Roughly what the clip will take: the source's own bytes for as much of
    /// it as the clip keeps. The export re-encodes and usually lands under
    /// this, so it errs high, which is the direction a space check should err.
    ///
    /// Best effort. A check on the space cannot be the thing that fails the
    /// write it guards, so anything it cannot read estimates nothing.
    static func estimate(of asset: AVURLAsset, keeping ranges: [TimeRange]) async -> Int64 {
        let kept = ranges.reduce(0) { $0 + $1.duration }
        guard let total = try? await asset.load(.duration).seconds,
              total.isFinite, total > 0, kept.isFinite, kept > 0,
              let bytes = try? asset.url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        else { return 0 }
        return Int64(Double(bytes) * min(1, kept / total))
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

        // Nothing landed, so every span missed the source. Exporting this
        // reaches AVFoundation as "Operation Stopped", which names neither the
        // cause nor a way out.
        guard cursor > .zero else { throw CuttingError.nothingToCut }

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
