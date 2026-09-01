import Foundation
import OSLog

/// One subsystem for everything this app logs, so a report can be gathered by
/// asking for it rather than by naming every category.
enum Log {
    /// The app's own identifier, so the subsystem cannot drift from the bundle
    /// it came out of.
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.desertant.clipper"
}

extension Logger {
    /// A run from the file arriving to the clips being on screen.
    static let run = Logger(subsystem: Log.subsystem, category: "run")

    /// Cutting the clips and writing them out.
    static let export = Logger(subsystem: Log.subsystem, category: "export")
}
