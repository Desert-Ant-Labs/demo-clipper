import SwiftUI
import UniformTypeIdentifiers

// `fileExporter` takes documents, which is what gets a panel saying
// "Export 3 items" rather than "Open".
struct ClipFile: FileDocument {
    static let readableContentTypes: [UTType] = [.mpeg4Movie]

    let url: URL
    let name: String

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
