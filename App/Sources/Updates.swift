import AppKit
import Sparkle

/// Sparkle, started once at launch.
@MainActor
final class Updates {
    static let shared = Updates()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func check() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}
