import Foundation
import Testing
import Transcript

private func sentences(_ count: Int) -> [Sentence] {
    (0..<count).map {
        Sentence(id: $0, text: "Sentence \($0).", start: Double($0) * 10, end: Double($0) * 10 + 4)
    }
}

@Suite("Short transcripts")
struct ShortTranscriptTests {
    @Test("Too little said to clip is refused with a reason, before any model loads")
    func refusesTooFewSentences() async {
        let finder = ClipFinder(models: ModelLocations())
        var thrown: (any Error)?

        do {
            for try await _ in finder.search(in: sentences(3)) {}
        } catch {
            thrown = error
        }

        let error = thrown as? ClipSearchError
        #expect(error != nil)
        if case .tooShort(let count) = error {
            #expect(count == 3)
        } else {
            Issue.record("expected tooShort, got \(String(describing: thrown))")
        }
        #expect(error?.errorDescription?.contains("3 sentences") == true)
    }
}

@Suite("Model locations")
struct ModelLocationTests {
    /// Asserts the behavior, not the names: a restated list goes stale on the
    /// next repackaging, which is the drift this test exists to catch.
    @Test("A directory is only a model directory when everything is in it")
    func refusesAHalfPopulatedDirectory() throws {
        let folder = URL.temporaryDirectory.appending(path: "clipper-models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let wanted = ModelLocations.clipsFiles
        #expect(!wanted.isEmpty, "an empty declaration would make every directory look complete")
        #expect(ModelLocations.missing(wanted, in: folder).count == wanted.count)

        let first = try #require(wanted.first)
        try Data().write(to: folder.appending(path: first))
        #expect(ModelLocations.missing(wanted, in: folder) == Array(wanted.dropFirst()),
                "the satisfied name drops out and every other one still stands")
    }

    /// An empty Apple manifest from `ClipModel` would make every directory look
    /// complete, and nothing else checks that the derivation holds.
    @Test("The required files are the SDK's own declaration")
    func namesComeFromTheSDK() {
        #expect(ModelLocations.clipsFiles.contains("clip_tokenizer.bin"))
        #expect(ModelLocations.clipsFiles.contains { $0.hasSuffix(".mlmodelc") })
        #expect(!ModelLocations.clipsFiles.contains { $0.hasSuffix("/") },
                "the trailing slash is the manifest's directory marker; no file is at that path")
    }
}
