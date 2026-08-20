import Foundation

extension Int {
    /// `1 sentence` / `4 sentences`.
    ///
    /// Spelled out rather than using `^[...](inflect: true)`, which is only
    /// resolved when the string reaches SwiftUI as a `LocalizedStringKey`.
    /// Handed to something that takes a plain `String`, the markup is what gets
    /// drawn.
    var sentenceCount: String {
        self == 1 ? "1 sentence" : "\(self) sentences"
    }
}

/// Stands in for a title while one is being written.
///
/// Only ever drawn redacted, so the length is the point: a bar the size of a
/// written title rather than one the size of `Clip 1`. Worded to read sensibly
/// on the chance it is ever drawn plain.
enum CardPlaceholder {
    static let title = "Writing the title for this clip"
}

extension Double {
    /// `577 ms` / `5.6 s`. Sub-second work is the common case for these
    /// models, so milliseconds matter more than a second's resolution shows.
    var formattedSeconds: String {
        self < 1 ? String(format: "%.0f ms", self * 1000) : String(format: "%.1f s", self)
    }
}
