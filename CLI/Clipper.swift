import ArgumentParser
import AVFoundation
import Foundation
import Title
import Transcript

@main
struct Clipper: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clipper",
        abstract: "Find the clips worth posting in a video, on device."
    )

    @Argument(help: "The video to clip. Omit it with --from-transcript.", completion: .file())
    var video: String?

    @Option(name: [.short, .customLong("out")], help: "Directory to write clips into.")
    var output: String?

    @Option(name: [.short, .customLong("count")], help: "How many clips to keep.")
    var count: Int?

    @Flag(name: .long, help: "Find clips and print them without exporting.")
    var dryRun = false

    @Flag(name: .long, help: "Print the timed transcript and stop.")
    var transcript = false

    @Flag(name: .long, help: "Print the result as JSON.")
    var json = false

    @Option(
        name: .long,
        help: """
            A JSON transcript to clip instead of a video: a list of sentences, \
            an object with a "sentences" key, or a list of either. Nothing is \
            transcribed and nothing is exported, so this is the way to see what \
            the models do on their own.
            """,
        completion: .file()
    )
    var fromTranscript: String?

    @Option(name: .long, help: "Directory holding the Voz model.", completion: .directory)
    var vozModel: String?

    @Option(name: .long, help: "Directory holding the Clips model.", completion: .directory)
    var clipsModel: String?

    @Option(name: .long, help: "Directory holding the card model.", completion: .directory)
    var titleModel: String?

    @Flag(name: .long, help: "Pick the clips and skip writing their titles.")
    var noTitles = false

    /// The models this run should use, with the flags overriding what the
    /// machine has.
    private var models: ModelLocations {
        var models = ModelLocations.resolved
        if let vozModel { models.voz = URL(filePath: vozModel) }
        if let clipsModel { models.clips = URL(filePath: clipsModel) }
        if let titleModel { models.title = URL(filePath: titleModel) }
        return models
    }

    func validate() throws {
        guard video != nil || fromTranscript != nil else {
            throw ValidationError("Pass a video, or a JSON transcript with --from-transcript.")
        }
    }

    func run() async throws {
        if let fromTranscript {
            try await clipTranscripts(at: URL(filePath: fromTranscript).standardizedFileURL)
            return
        }

        let source = URL(filePath: video ?? "").standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw ValidationError("No file at \(source.path(percentEncoded: false))")
        }

        let asset = AVURLAsset(url: source)
        let info = try await SourceInfo.load(from: asset)

        let reading = try await read(asset, named: info.name)
        if transcript {
            try emit(Report.transcript(info, reading.sentences), plain: printTranscript(reading.sentences))
            return
        }

        let picks = try await findClips(in: reading.sentences)
        guard !picks.isEmpty else { throw CleanExit.message("No clips came back for that video.") }

        let exports = dryRun ? [:] : try await export(picks, of: source, in: reading.sentences)
        try emit(
            Report(source: info, picks: picks, sentences: reading.sentences, files: exports),
            plain: printSummary(picks, in: reading.sentences, files: exports)
        )
    }
}

extension Clipper {
    private func read(_ asset: AVURLAsset, named name: String) async throws -> Reading {
        Progress.log("Transcribing \(name)")
        let reader = Reader(speech: Speech(directory: models.voz))
        let reading = try await reader.read(asset) { stage in
            switch stage {
            case .extractingAudio(let fraction):
                Progress.update("Loading audio", "\(Int(fraction * 100))%")
            case .loadingSpeech(let fraction):
                Progress.update("Loading Voz", "\(Int(fraction * 100))%")
            case .transcribing(let fraction):
                Progress.update("Transcribing", "\(Int(fraction * 100))%")
            }
        }
        Progress.finish(
            "\(reading.sentences.count) sentences (Voz"
            + (reading.speedLabel.map { ", \($0)" } ?? "") + ")"
        )
        return reading
    }

    /// Runs both models over a transcript, reporting each stage as it lands.
    private func findClips(in sentences: [Sentence]) async throws -> [Pick] {
        let finder = ClipFinder(models: models, namesClips: !noTitles)
        Progress.log("Loading Clips" + (finder.writesTitles ? " and the card model" : ""))

        var picks: [Pick] = []
        var written = 0
        for try await update in finder.search(in: sentences, count: count) {
            switch update {
            case .selected(let clips, let seconds):
                picks = clips.map { Pick($0) }
                Progress.finish("\(picks.count) clips in \(Format.seconds(seconds))")
            case .written(let id, let card, let seconds):
                guard let index = picks.firstIndex(where: { $0.id == id }) else { continue }
                picks[index].card = card
                written += 1
                Progress.update(
                    "Writing titles", "\(written)/\(picks.count) (\(Format.seconds(seconds)) each)")
            case .writingFailed(let reason):
                // Asked for no titles, not having any is the result.
                if !noTitles { Progress.finish("No titles: \(reason)") }
            }
        }
        if written > 0 { Progress.finish("\(written) titles") }
        return picks
    }

    /// The models on their own: no audio, no export, just what they make of a
    /// transcript. This is what a reference run is compared against.
    private func clipTranscripts(at url: URL) async throws {
        let transcripts = try Transcripts.read(at: url)
        guard !transcripts.isEmpty else { throw ValidationError("No transcripts in \(url.lastPathComponent)") }

        var reports: [Report] = []
        for transcript in transcripts {
            let sentences = transcript.sentences.enumerated().map { index, text in
                // No timings in a bare transcript. Two and a half words a
                // second is the same estimate the SDK makes.
                let start = Double(index) * 4
                return Sentence(id: index, text: text, start: start, end: start + 3.5)
            }
            Progress.log("\(transcript.name): \(sentences.count) sentences")
            let picks = try await findClips(in: sentences)
            reports.append(Report(name: transcript.name, picks: picks, sentences: sentences))
            if !json { printSummary(picks, in: sentences, files: [:]) }
        }

        if json { try emit(reports) }
    }

    /// Returns each clip's written path, keyed by clip.
    private func export(
        _ picks: [Pick],
        of source: URL,
        in sentences: [Sentence]
    ) async throws -> [Pick.ID: URL] {
        let directory = URL(filePath: output ?? FileManager.default.currentDirectoryPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A recording with no picture is written out as audio.
        let info = try? await SourceInfo.load(from: AVURLAsset(url: source))
        let type = info?.clipExtension ?? "mp4"

        var written: [Pick.ID: URL] = [:]
        for (index, pick) in picks.enumerated() {
            let destination = directory
                .appending(path: pick.fileName(number: index + 1, of: picks.count))
                .appendingPathExtension(type)
            let file = try await Cutting.write(
                source, ranges: pick.ranges(in: sentences), to: destination
            )
            Progress.log("Exported \(file.lastPathComponent)")
            written[pick.id] = file
        }
        return written
    }

    private func emit(_ report: Report, plain: @autoclosure () -> Void) throws {
        guard json else { return plain() }
        try emit([report])
    }

    private func emit(_ reports: [Report]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let payload = reports.count == 1 ? try encoder.encode(reports[0]) : try encoder.encode(reports)
        print(String(decoding: payload, as: UTF8.self))
    }

    private func printTranscript(_ sentences: [Sentence]) {
        for sentence in sentences {
            print(String(format: "%7.2f  %@", sentence.start, sentence.text))
        }
    }

    private func printSummary(_ picks: [Pick], in sentences: [Sentence], files: [Pick.ID: URL]) {
        for (index, pick) in picks.enumerated() {
            print("")
            print("\(index + 1). \(pick.displayTitle)  [\(pick.duration(in: sentences).formattedDuration)]")
            if let card = pick.card { print("   \(card.description)") }
            print(String(
                format: "   sentences: %@, score %.3f, percentile %.2f",
                pick.keptSentenceIDs.map(String.init).joined(separator: ","),
                pick.clip.score, pick.clip.percentile))
            if let file = files[pick.id] { print("   \(file.path(percentEncoded: false))") }
        }
    }
}

/// A transcript read off disk: sentences and something to call it.
private struct Transcripts {
    let name: String
    let sentences: [String]

    /// Three shapes, because three things write them: a bare list of sentences,
    /// one object with a `sentences` key, or a list of those objects.
    static func read(at url: URL) throws -> [Transcripts] {
        let data = try Data(contentsOf: url)
        let stem = url.deletingPathExtension().lastPathComponent

        if let one = try? JSONDecoder().decode([String].self, from: data) {
            return [Transcripts(name: stem, sentences: one)]
        }
        if let one = try? JSONDecoder().decode(Entry.self, from: data) {
            return [Transcripts(name: one.stratum ?? stem, sentences: one.sentences)]
        }
        let many = try JSONDecoder().decode([Entry].self, from: data)
        return many.enumerated().map { index, entry in
            Transcripts(name: entry.stratum ?? "\(stem) \(index + 1)", sentences: entry.sentences)
        }
    }

    private struct Entry: Decodable {
        let sentences: [String]
        let stratum: String?
    }
}

/// Machine-readable form of a run, printed under `--json`.
private struct Report: Encodable {
    struct Clip: Encodable {
        let rank: Int
        let title: String?
        let summary: String?
        let score: Double
        let percentile: Double
        let seconds: Double
        let sentences: [Int]
        let ranges: [Range]
        let transcript: String
        let file: String?
    }

    struct Range: Encodable {
        let start: Double
        let end: Double
    }

    struct Source: Encodable {
        let name: String
        let seconds: Double?
        let resolution: String?
        let frameRate: Double?
        let videoCodec: String?
        let audio: String?
        let bytes: Int64?
    }

    struct Sentence: Encodable {
        let id: Int
        let start: Double
        let end: Double
        let text: String
    }

    var source: Source
    var clips: [Clip] = []
    var sentences: [Sentence] = []

    init(
        source info: SourceInfo,
        picks: [Pick],
        sentences: [Transcript.Sentence],
        files: [Pick.ID: URL]
    ) {
        self.source = Source(
            name: info.name,
            seconds: info.duration.seconds,
            resolution: info.resolutionLabel,
            frameRate: info.frameRate,
            videoCodec: info.videoCodec,
            audio: info.audioLabel,
            bytes: info.fileSize
        )
        self.clips = picks.map { $0.reported(in: sentences, file: files[$0.id]) }
    }

    /// A run that had no video to describe.
    init(name: String, picks: [Pick], sentences: [Transcript.Sentence]) {
        self.source = Source(
            name: name, seconds: nil, resolution: nil, frameRate: nil,
            videoCodec: nil, audio: nil, bytes: nil
        )
        self.clips = picks.map { $0.reported(in: sentences, file: nil) }
    }

    static func transcript(_ info: SourceInfo, _ sentences: [Transcript.Sentence]) -> Report {
        var report = Report(source: info, picks: [], sentences: sentences, files: [:])
        report.sentences = sentences.map {
            Sentence(id: $0.id, start: $0.start, end: $0.end, text: $0.text)
        }
        return report
    }
}

extension Pick {
    fileprivate func reported(in sentences: [Transcript.Sentence], file: URL?) -> Report.Clip {
        Report.Clip(
            rank: clip.id,
            title: card?.title,
            summary: card?.description,
            score: clip.score,
            percentile: clip.percentile,
            seconds: duration(in: sentences),
            sentences: keptSentenceIDs,
            ranges: ranges(in: sentences).map { Report.Range(start: $0.start, end: $0.end) },
            transcript: text(in: sentences),
            file: file?.path(percentEncoded: false)
        )
    }
}

private enum Format {
    static func seconds(_ value: Double) -> String {
        value < 10 ? String(format: "%.2fs", value) : String(format: "%.1fs", value)
    }
}

/// Progress goes to stderr so stdout stays pipeable.
private enum Progress {
    static func log(_ message: String) {
        write("\(message)\n")
    }

    static func update(_ label: String, _ detail: String) {
        write("\r\(label) \(detail)")
    }

    static func finish(_ message: String) {
        write("\r\(message)\n")
    }

    private static func write(_ text: String) {
        try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
    }
}
