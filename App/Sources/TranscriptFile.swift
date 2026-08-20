import SwiftUI
import Transcript
import UniformTypeIdentifiers

/// A transcript on its way to a file. The formatting is ``Subtitles``; this is
/// only what `fileExporter` needs to write it.
struct TranscriptFile: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]

    let text: String
    let name: String

    init(text: String, name: String) {
        self.text = text
        self.name = name
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: Data(text.utf8))
        wrapper.preferredFilename = name
        return wrapper
    }
}
