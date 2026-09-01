import SwiftUI
import UniformTypeIdentifiers

// `fileExporter` takes documents, which is what gets a panel saying
// "Export 3 items" rather than "Open".
struct ClipFile: FileDocument {
    static let readableContentTypes: [UTType] = [.mpeg4Movie, .mpeg4Audio]

    let url: URL
    let name: String

    /// What this clip is, so the panel offers the right kind. A clip of a
    /// recording with no picture is audio.
    var contentType: UTType {
        url.pathExtension == "m4a" ? .mpeg4Audio : .mpeg4Movie
    }

    init(url: URL, name: String) {
        self.url = url
        self.name = name
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrapper = try FileWrapper(url: url)
        wrapper.preferredFilename = name
        return wrapper
    }
}
