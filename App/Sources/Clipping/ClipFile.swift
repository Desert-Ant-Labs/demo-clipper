import Foundation
import UniformTypeIdentifiers

/// A clip that has been cut and is waiting to be put somewhere.
struct ClipFile: Equatable, Sendable {
    /// Where it was written while it waited, in a folder of its own.
    let url: URL
    /// What it should be called where it lands.
    let name: String

    /// A clip of a recording with no picture is audio, and the panel offers
    /// that type rather than a movie.
    var contentType: UTType {
        url.pathExtension == "m4a" ? .mpeg4Audio : .mpeg4Movie
    }
}
