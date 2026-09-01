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

@Suite("Disk space")
struct StorageTests {
    @Test("A write asks for its own size plus the headroom")
    func addsHeadroom() {
        // A volume that reports nothing counts as room, so these run against
        // the real temporary directory only for the shape of the arithmetic.
        #expect(Storage.headroom == 250_000_000)
    }

    @Test("A volume that will not report its capacity counts as room")
    func unknownCapacityIsRoom() {
        // A path on no volume has no capacity to read.
        let nowhere = URL(filePath: "/dev/null/not-a-volume")
        #expect(Storage.available(at: nowhere) == nil)
        #expect(Storage.hasRoom(for: 1_000_000_000_000, at: nowhere))
    }
}

@Suite("Export allowance")
struct AllowanceTests {
    private func ranges(_ spans: [(Double, Double)]) -> [TimeRange] {
        spans.map { TimeRange(start: $0.0, end: $0.0 + $0.1) }
    }

    @Test("A short clip still gets a floor")
    func floor() {
        #expect(Cutting.allowance(for: ranges([(0, 2)])) == 120)
    }

    @Test("A long clip gets time in proportion to itself")
    func scales() {
        #expect(Cutting.allowance(for: ranges([(0, 60)])) == 1200)
        #expect(Cutting.allowance(for: ranges([(0, 30), (100, 30)])) == 1200)
    }

    @Test("No spans is still a floor rather than zero")
    func empty() {
        #expect(Cutting.allowance(for: []) == 120)
    }
}

@Suite("Diagnostics")
struct DiagnosticsTests {
    @Test("A report names the app, the OS build, and the machine")
    func versions() {
        let lines = Diagnostics.versions
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Clipper "))
        #expect(lines[1].hasPrefix("macOS "))
        // Nothing should read as unknown on a Mac that answers sysctl.
        #expect(!lines[1].contains("(?)"))
        #expect(!lines[2].hasPrefix("? "))
        #expect(lines[2].contains("cores"))
    }
}

@Suite("Malformed durations")
struct MalformedDurationTests {
    @Test("An allowance is a number even when the spans are not")
    func allowanceSurvivesNaN() {
        // `Int(_: Double)` traps on these, and a malformed asset reports them.
        #expect(Cutting.allowance(for: [TimeRange(start: 0, end: .nan)]) == Cutting.floor)
        #expect(Cutting.allowance(for: [TimeRange(start: 0, end: .infinity)]) == Cutting.floor)
        #expect(Cutting.allowance(for: [TimeRange(start: 0, end: -5)]) == Cutting.floor)
    }

    @Test("A span too long to count still gives a usable allowance")
    func allowanceIsBounded() {
        let huge = Cutting.allowance(for: [TimeRange(start: 0, end: 1e18)])
        #expect(huge > Cutting.floor)
        #expect(huge <= Int(Int32.max))
    }
}
