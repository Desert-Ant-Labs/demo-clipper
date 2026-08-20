import Foundation

/// The models the app loads once and shares.
///
/// Warming them at launch and running them on a video have to reach the same
/// instances, or the weights are read twice.
@MainActor
enum Models {
    static let reader = Reader()
    static let clipFinder = ClipFinder()
}
