import Foundation

/// Why a recording could not be read. Transcription happens here rather than in
/// the SDK, so these are this app's to report.
enum SpeechError: LocalizedError {
    case noAudioTrack
    case audioExtractionFailed
    case noSpeech
    case outOfSpace(needs: String, free: String?)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            "That video has no audio track."
        case .audioExtractionFailed:
            "The audio could not be read from that video."
        case .noSpeech:
            "No speech was found in that recording."
        case .outOfSpace(let needs, let free):
            if let free {
                "There is not enough disk space. This needs about \(needs), "
                    + "and \(free) is free."
            } else {
                "There is not enough disk space. This needs about \(needs)."
            }
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noAudioTrack, .noSpeech:
            "Clipper picks clips out of what is said, so it needs a recording with speech in it."
        case .audioExtractionFailed:
            "Try a different file, or one exported again from the app that made it."
        case .outOfSpace:
            "Free up some space and try again."
        }
    }
}

/// Why a clip could not be cut. Cutting happens here rather than in the SDK,
/// which hands back time spans and nothing else.
enum CuttingError: LocalizedError {
    case noPlayableTrack
    case nothingToCut
    case unreadableSource
    case stalled(seconds: Int)
    case exportUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPlayableTrack:
            "That video has neither a picture nor a sound track to cut."
        case .nothingToCut:
            "That clip lands outside the video, so there is nothing to cut."
        case .unreadableSource:
            "The video could not be read."
        case .stalled(let seconds):
            "Writing the clip got nowhere in \(seconds) seconds, so it was stopped."
        case .exportUnavailable:
            "This video cannot be written out in a supported format."
        case .exportFailed(let why):
            "The clip could not be written. \(why)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noPlayableTrack, .exportUnavailable:
            "Try a different file, or one exported again from the app that made it."
        case .nothingToCut:
            "Pick a different clip."
        case .unreadableSource:
            "It may have been moved, renamed, or deleted since it was opened. Open it again."
        case .stalled:
            "Try the export again. If it stops in the same place, the file may be the cause."
        case .exportFailed:
            "Try the export again, or write the clip somewhere else."
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

/// What to put in front of someone when a run fails, and what to keep for the
/// report they might file about it.
///
/// Foundation's own sentence for an error it has no words for is "The operation
/// could not be completed", which tells a reader nothing. Everything here says
/// what happened and what to do; the unhelpful sentence, if there was one, goes
/// in ``detail`` where it can be copied into an issue.
struct Problem: Equatable {
    /// What happened, in the reader's terms.
    let message: String
    /// What they can do about it.
    let advice: String?
    /// The underlying text, for a bug report.
    let detail: String

    init(_ error: any Error) {
        let localized = error as? any LocalizedError
        message = localized?.errorDescription ?? "Something went wrong."
        advice = localized?.recoverySuggestion

        // The domain and code pin which error this was. The sentence follows
        // only when it says something the message did not, so a report does
        // not print the same line twice.
        let ns = error as NSError
        let underlying = reason(error)
        detail = underlying == message
            ? "\(ns.domain) \(ns.code)"
            : "\(ns.domain) \(ns.code): \(underlying)"
    }
}
