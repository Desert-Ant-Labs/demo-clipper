import AppKit
import OSLog
import UniformTypeIdentifiers

/// Asks where the clips should go, and puts them there.
///
/// AppKit's panels rather than SwiftUI's `fileExporter`, which on macOS 26 sets
/// out to present and never does: the clips are cut, the app asks for a
/// destination, and nothing appears. The same modifier also ignores a wrapper's
/// `preferredFilename` for several documents and has no `defaultFilename` for
/// one, so all three faults sat on this one surface.
@MainActor
enum ClipSaver {
    /// What came of asking.
    enum Outcome {
        case saved([URL])
        case cancelled
    }

    /// Writes text to a file the person chooses, for the transcript.
    static func save(
        text: String, named name: String, over window: NSWindow?
    ) async throws -> Outcome {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        // The name may end in .srt, which is not plain text's own extension.
        // Allowing the name's type keeps the panel from appending .txt.
        panel.allowedContentTypes = [
            UTType(filenameExtension: (name as NSString).pathExtension) ?? .plainText
        ]
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard let destination = await run(panel, over: window) else { return .cancelled }
        try Data(text.utf8).write(to: destination)
        return .saved([destination])
    }

    static func save(_ clips: [ClipFile], over window: NSWindow?) async throws -> Outcome {
        guard let first = clips.first else { return .cancelled }

        if clips.count == 1 {
            guard let destination = await ask(for: first, over: window) else { return .cancelled }
            return .saved([try put(first, at: destination)])
        }

        guard let folder = await askForFolder(over: window) else { return .cancelled }
        return .saved(try clips.map { try put($0, at: folder.appending(path: $0.name)) })
    }

    /// A save panel, named for the clip it is offering.
    private static func ask(for clip: ClipFile, over window: NSWindow?) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = clip.name
        panel.allowedContentTypes = [clip.contentType]
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        return await run(panel, over: window)
    }

    /// A folder, for several clips that already carry their own names.
    private static func askForFolder(over window: NSWindow?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        return await run(panel, over: window)
    }

    /// As a sheet on the window when there is one, so it arrives attached to
    /// the clips it came from rather than floating loose. The panel's own
    /// completion handler runs on the main thread, which is where this is.
    private static func run(_ panel: NSSavePanel, over window: NSWindow?) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let complete: (NSApplication.ModalResponse) -> Void = { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
            if let window {
                panel.beginSheetModal(for: window, completionHandler: complete)
            } else {
                panel.begin(completionHandler: complete)
            }
        }
    }

    /// Moves the clip out of its scratch folder. Replacing is the panel's own
    /// promise: it asked before returning a name that was already taken.
    private static func put(_ clip: ClipFile, at destination: URL) throws -> URL {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try manager.removeItem(at: destination)
        }
        try manager.copyItem(at: clip.url, to: destination)
        return destination
    }
}
