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

@Suite("Release versions")
struct UpdateCheckTests {
    @Test("A tag is compared without its v")
    func stripsThePrefix() {
        #expect(UpdateCheck.number(in: "v1.2") == "1.2")
        #expect(UpdateCheck.number(in: "1.2") == "1.2")
    }

    @Test("A later release is newer")
    func findsNewer() {
        #expect(UpdateCheck.isNewer("1.1", than: "1.0"))
        #expect(UpdateCheck.isNewer("2.0", than: "1.9"))
    }

    @Test("The running version and older ones are not")
    func ignoresCurrentAndOlder() {
        #expect(!UpdateCheck.isNewer("1.0", than: "1.0"))
        #expect(!UpdateCheck.isNewer("0.9", than: "1.0"))
    }

    @Test("Point releases compare by number, so 1.10 follows 1.9")
    func comparesNumerically() {
        #expect(UpdateCheck.isNewer("1.10", than: "1.9"))
        #expect(!UpdateCheck.isNewer("1.9", than: "1.10"))
    }

    @Test("A version that could not be read offers nothing")
    func refusesEmpty() {
        #expect(!UpdateCheck.isNewer("1.1", than: ""))
        #expect(!UpdateCheck.isNewer("", than: "1.0"))
    }
}
