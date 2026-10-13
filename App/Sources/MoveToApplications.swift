import AppKit

/// Sparkle can't update an app run from a disk image or Downloads, so a copy
/// there offers to move itself to Applications.
@MainActor
enum MoveToApplications {
    private static let declinedKey = "declinedMoveToApplications"

    /// True when the app is relaunching from Applications.
    @discardableResult
    static func offer() -> Bool {
        let app = Bundle.main.bundleURL
        guard needsMove(app), !UserDefaults.standard.bool(forKey: declinedKey) else { return false }
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")

        let alert = NSAlert()
        alert.messageText = "Move \(name) to Applications?"
        alert.informativeText = "\(name) can only update itself from the Applications folder."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        NSApp.activate()
        let answer = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: declinedKey) }
        guard answer == .alertFirstButtonReturn else { return false }

        let destination = URL(filePath: "/Applications").appending(path: app.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: app, to: destination)
            try removeQuarantine(from: destination)
        } catch {
            NSAlert(error: error).runModal()
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }

    private static func needsMove(_ app: URL) -> Bool {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path
        return app.path.hasPrefix("/Volumes/") || app.path.contains("/AppTranslocation/") || app.path.hasPrefix(downloads)
    }

    /// Without this, macOS runs the copy from a randomized location again.
    private static func removeQuarantine(from app: URL) throws {
        let xattr = Process()
        xattr.executableURL = URL(filePath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", app.path]
        try xattr.run()
        xattr.waitUntilExit()
    }
}
