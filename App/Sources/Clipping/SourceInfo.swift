import AVFoundation
import Foundation

/// What the source recording is, read once when it is opened.
struct SourceInfo: Sendable, Equatable {
    let name: String
    let duration: CMTime
    let fileSize: Int64?

    /// Display size, with the source's rotation applied, so portrait footage
    /// reports portrait. `nil` when there is no video track.
    let videoSize: CGSize?
    let frameRate: Double?
    let videoCodec: String?
    let audioCodec: String?
    let sampleRate: Double?
    let channels: Int?

    var aspectRatio: CGFloat? {
        guard let videoSize, videoSize.height > 0 else { return nil }
        return videoSize.width / videoSize.height
    }

    var hasVideo: Bool { videoSize != nil }

    static func load(from asset: AVURLAsset) async throws -> SourceInfo {
        let duration = try await asset.load(.duration)
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio).first

        var videoSize: CGSize?
        var frameRate: Double?
        var videoCodec: String?
        if let video {
            let (size, transform, rate, formats) = try await video.load(
                .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions
            )
            let shown = size.applying(transform)
            videoSize = CGSize(width: abs(shown.width), height: abs(shown.height))
            frameRate = rate > 0 ? Double(rate) : nil
            videoCodec = formats.first.map(codecName)
        }

        var audioCodec: String?
        var sampleRate: Double?
        var channels: Int?
        if let audio {
            let formats = try await audio.load(.formatDescriptions)
            audioCodec = formats.first.map(codecName)
            if let stream = formats.first?.audioStreamBasicDescription {
                sampleRate = stream.mSampleRate
                channels = Int(stream.mChannelsPerFrame)
            }
        }

        return SourceInfo(
            name: asset.url.lastPathComponent,
            duration: duration,
            fileSize: try? asset.url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init),
            videoSize: videoSize,
            frameRate: frameRate,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            sampleRate: sampleRate,
            channels: channels
        )
    }

    /// The four-character media subtype, named where the code is not readable.
    static func codecName(_ format: CMFormatDescription) -> String {
        let code = format.mediaSubType.rawValue
        // Codes are four bytes, padded with spaces: AAC in an m4a is "aac ".
        let tag = String(
            [24, 16, 8, 0]
                .map { UInt8((code >> $0) & 0xFF) }
                .map { Character(UnicodeScalar($0)) }
        ).trimmingCharacters(in: .whitespaces)

        return switch tag {
        case "hvc1", "hev1": "HEVC"
        case "avc1", "avc3": "H.264"
        case "av01": "AV1"
        case "vp09": "VP9"
        case "mp4a", "aac": "AAC"
        case "alac": "Apple Lossless"
        case "lpcm": "Linear PCM"
        case "Opus": "Opus"
        default: tag
        }
    }
}

extension SourceInfo {
    /// `1080 x 1920`, or nil when there is no video.
    var resolutionLabel: String? {
        guard let videoSize else { return nil }
        return "\(Int(videoSize.width)) x \(Int(videoSize.height))"
    }

    var frameRateLabel: String? {
        frameRate.map { String(format: "%.4g fps", $0) }
    }

    var fileSizeLabel: String? {
        fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    var audioLabel: String? {
        guard let audioCodec else { return nil }
        let rate = sampleRate.map { String(format: "%.4g kHz", $0 / 1000) }
        let layout = channels.map { $0 == 1 ? "mono" : $0 == 2 ? "stereo" : "\($0) ch" }
        return [audioCodec, rate, layout].compactMap(\.self).joined(separator: ", ")
    }
}
