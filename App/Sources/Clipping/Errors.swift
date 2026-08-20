import Foundation

/// Why a recording could not be read. Transcription happens here rather than in
/// the SDK, so these are this app's to report.
enum SpeechError: LocalizedError {
    case noAudioTrack
    case audioExtractionFailed
    case noSpeech
    case outOfSpace(free: String?)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            "That video has no audio track."
        case .audioExtractionFailed:
            "The audio could not be read from that video."
        case .noSpeech:
            "No speech was found in that recording."
        case .outOfSpace(let free):
            if let free {
                "Not enough disk space. Clipper needs a couple of gigabytes to "
                    + "pull the audio out and write the clips, and \(free) is free."
            } else {
                "Not enough disk space to pull the audio out and write the clips."
            }
        }
    }
}

/// Why a clip could not be cut. Cutting happens here rather than in the SDK,
/// which hands back time spans and nothing else.
enum CuttingError: LocalizedError {
    case noPlayableTrack
    case exportUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPlayableTrack:
            "That video has neither a picture nor a sound track to cut."
        case .exportUnavailable:
            "This video cannot be exported in a supported format."
        case .exportFailed(let why):
            "The clip could not be written. \(why)"
        }
    }
}

/// The best sentence a thrown error has to offer.
///
/// Several SDK error types are not `LocalizedError` and localize to
/// "operation couldn't be completed" or to `ClipsError error 1`.
func reason(_ error: any Error) -> String {
    if let localized = (error as? any LocalizedError)?.errorDescription { return localized }
    // A Swift error bridges to a synthesized domain and loses its description;
    // `String(describing:)` keeps it: `localFileMissing("…/clip_tokenizer.bin")`.
    // A real `NSError` has a real localization.
    guard (error as NSError).domain.contains(".") else { return error.localizedDescription }
    return String(describing: error)
}
