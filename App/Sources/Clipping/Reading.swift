import Foundation
import Transcript

/// A transcript, and what read it. Not `Transcript`, which is the SDK module
/// declaring ``Sentence`` and ``Clip``.
struct Reading: Sendable, Equatable {
    let sentences: [Sentence]

    /// What reading it cost.
    let timings: Timings

    /// What one read of a recording took.
    struct Timings: Sendable, Equatable {
        /// Pulling the audio out of the video container.
        let extractingSeconds: Double
        /// How long the recording is.
        let mediaSeconds: Double
        /// Wall clock Voz spent on it.
        let readingSeconds: Double
        /// Seconds of audio read per second of wall clock.
        let realtimeFactor: Double
    }

    init(sentences: [Sentence], timings: Timings) {
        self.sentences = sentences
        self.timings = timings
    }

    /// `285x speed`, or nothing for a recording read no faster than it plays.
    var speedLabel: String? {
        let factor = timings.realtimeFactor
        guard factor >= 1 else { return nil }
        return "\(Int(factor.rounded()))x speed"
    }
}

extension Double {
    /// `m:ss`, widening past an hour. Times carrying no value report NaN
    /// seconds, which would trap on conversion.
    var formattedDuration: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
