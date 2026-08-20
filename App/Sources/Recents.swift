import AppKit
import Foundation

/// The videos opened before.
///
/// `NSDocumentController` keeps the list the Dock and the Finder already show
/// for this app, so there is nothing of ours to persist. Recording a URL does
/// not need a document: the controller takes any file.
@MainActor
enum Recents {
    static var urls: [URL] {
        NSDocumentController.shared.recentDocumentURLs
    }

    static func remember(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    static func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
}
