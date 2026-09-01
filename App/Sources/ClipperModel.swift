import AppKit
import AVFoundation
import Foundation
import Observation
import OSLog
import Transcript

/// Drives one video through transcription, clip selection, title writing, and
/// export, and holds what the views draw.
@MainActor
@Observable
final class ClipperModel {
    enum Phase: Equatable {
        case idle
        case extractingAudio(Double)
        case loadingSpeech(Double)
        case transcribing(Double)
        case preparingModels
        case selecting
        case writingTitles(done: Int, total: Int)
        case ready
        case exporting(done: Int, total: Int)
        case failed(String)
    }

    private(set) var phase = Phase.idle
    private(set) var picks: [Pick] = []
    private(set) var sentences: [Sentence] = []

    /// What produced the transcript in hand.
    private(set) var reading: Reading?
    private(set) var videoName = ""
    private(set) var asset: AVURLAsset?

    /// How long each half took, kept apart because they are separately slow.
    private(set) var selectionSeconds: Double?
    private(set) var cardSeconds: [Double] = []

    /// Why there are no titles, when there are none. The clips still stand.
    private(set) var titleProblem: String?

    /// What this video cost, for the Inspector. `nil` until it has been read.
    var performance: Performance? {
        guard let reading else { return nil }
        return Performance(
            timings: reading.timings,
            selectionSeconds: selectionSeconds,
            cardSeconds: cardSeconds
        )
    }

    struct Performance: Sendable, Equatable {
        let timings: Reading.Timings
        let selectionSeconds: Double?
        let cardSeconds: [Double]

        var cardTotal: Double? {
            cardSeconds.isEmpty ? nil : cardSeconds.reduce(0, +)
        }

        /// Opening the video through to named clips, model loading excluded:
        /// that happens once at launch rather than per video.
        var total: Double? {
            guard let selectionSeconds else { return nil }
            return timings.extractingSeconds + timings.readingSeconds
                + selectionSeconds + (cardTotal ?? 0)
        }
    }

    /// What was opened: duration, size, codecs. `nil` until it has been read.
    private(set) var source: SourceInfo?
    var selection: Pick.ID?

    private var work: Task<Void, Never>?

    /// A cancelled run keeps going until its next suspension point, so each
    /// run reports only while its number is still the current one.
    private var run = 0

    /// The selection when it is a clip that can be cut. The recording is not:
    /// it is already the file on disk.
    var exportableClip: Pick? {
        selectedPick.flatMap { $0.isWholeRecording ? nil : $0 }
    }

    /// The recording itself, offered above the clips so the whole transcript
    /// can be read and exported. `nil` before there is one.
    var wholeRecording: Pick? {
        sentences.isEmpty ? nil : .wholeRecording(of: sentences)
    }

    var selectedPick: Pick? {
        guard let selection else { return nil }
        return selection == Pick.wholeRecordingID
            ? wholeRecording
            : picks.first { $0.id == selection }
    }

    /// Exporting waits for a run rather than cancelling it, which would cost
    /// every title that had not landed.
    var canExport: Bool {
        switch phase {
        case .selecting, .writingTitles: false
        default: !picks.isEmpty
        }
    }

    /// Choosing a file is a presentation in SwiftUI, not a call.
    var isChoosingVideo = false
    var isExporting = false
    private(set) var finished: [ClipFile] = []

    /// Why the last export did not finish, for the alert over the clips. An
    /// export that fails leaves the clips it was made from standing, so this
    /// is separate from ``Phase/failed(_:)``, which is a run that produced
    /// nothing to show.
    var exportProblem: Problem?

    /// The transcript waiting to be written, and whether its panel is up.
    var isExportingTranscript = false
    private(set) var transcriptFile: TranscriptFile?

    /// Whether there is a video to close.
    var isOpen: Bool { asset != nil }

    /// The videos opened before, for the File menu.
    private(set) var recents: [URL] = Recents.urls

    func chooseVideo() {
        isChoosingVideo = true
    }

    /// Closes the video, or the window when there is no video, which is the
    /// order a document app closes things in.
    func closeVideoOrWindow() {
        guard isOpen else {
            NSApp.keyWindow?.performClose(nil)
            return
        }
        close()
    }

    /// Puts the window back to the drop zone, with the run in flight cancelled
    /// and the clips written for the panel thrown away.
    func close() {
        work?.cancel()
        run += 1
        finishExporting()
        phase = .idle
        asset = nil
        videoName = ""
        source = nil
        reading = nil
        picks = []
        sentences = []
        selection = nil
        selectionSeconds = nil
        cardSeconds = []
        titleProblem = nil
    }

    /// Cuts the clips, then offers them to `fileExporter`.
    func export(_ picks: [Pick]) {
        guard let asset, !picks.isEmpty else { return }
        finishExporting()
        work?.cancel()
        run += 1
        let run = run
        work = Task { await cut(picks, of: asset.url, run: run) }
    }

    /// Offers the whole transcript, or one clip's, to `fileExporter` as
    /// SubRip. A clip carries only the sentences it kept, timed against its own
    /// cut, so the subtitles match what it plays.
    func exportTranscript(of pick: Pick? = nil) {
        guard !sentences.isEmpty else { return }
        let stem = (videoName as NSString).deletingPathExtension
        if let pick, !pick.isWholeRecording {
            let kept = pick.keptSentenceIDs.filter(sentences.indices.contains)
            guard !kept.isEmpty else { return }
            transcriptFile = TranscriptFile(
                text: Subtitles.subRip(
                    of: kept.map { sentences[$0] },
                    in: pick.ranges(in: sentences)
                ),
                name: "\(stem) - \(pick.slug).srt"
            )
        } else {
            transcriptFile = TranscriptFile(
                text: Subtitles.subRip(of: sentences),
                name: "\(stem).srt"
            )
        }
        isExportingTranscript = true
    }

    func finishExportingTranscript() {
        transcriptFile = nil
    }

    func finishExporting() {
        discard(finished)
        finished = []
    }

    /// Drops the work of a run that has been superseded. The phase goes back
    /// to ready rather than being left as it was: a superseded export that
    /// leaves `.exporting` behind spins forever with nothing running.
    private func abandon(_ files: [ClipFile]) {
        discard(files)
        if case .exporting = phase { phase = .ready }
    }

    private func discard(_ files: [ClipFile]) {
        for file in files {
            // The whole scratch folder, so an abandoned export leaves nothing.
            try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
        }
    }

    func open(_ url: URL) {
        work?.cancel()
        run += 1
        let run = run
        Recents.remember(url)
        recents = Recents.urls
        work = Task { await load(url, run: run) }
    }

    func forgetRecents() {
        Recents.clear()
        recents = Recents.urls
    }

    /// Adds a sentence to a clip or takes it out. A clip always keeps at least
    /// one, so the last selected sentence cannot be removed.
    func setSentence(_ sentenceID: Int, selected: Bool, inPick pickID: Pick.ID) {
        guard let index = picks.firstIndex(where: { $0.id == pickID }),
              sentences.indices.contains(sentenceID)
        else { return }

        if selected {
            picks[index].selectedSentenceIDs.insert(sentenceID)
        } else if picks[index].selectedSentenceIDs.count > 1 {
            picks[index].selectedSentenceIDs.remove(sentenceID)
        }
    }

    /// State from a superseded run is discarded rather than drawn.
    private func current(_ run: Int) -> Bool { run == self.run }
}

extension ClipperModel {
    private func load(_ url: URL, run: Int) async {
        let asset = AVURLAsset(url: url)
        self.asset = asset
        videoName = url.lastPathComponent
        source = nil
        reading = nil
        picks = []
        sentences = []
        selection = nil
        selectionSeconds = nil
        cardSeconds = []
        titleProblem = nil

        do {
            source = try await SourceInfo.load(from: asset)
            guard current(run) else { return }

            phase = .extractingAudio(0)
            let read = try await Models.reader.read(asset) { [weak self] stage in
                Task { @MainActor in self?.report(stage, run: run) }
            }
            try Task.checkCancellation()
            guard current(run) else { return }
            sentences = read.sentences
            reading = read

            let finder = Models.clipFinder
            phase = .preparingModels
            try await finder.prepare()
            guard current(run) else { return }

            phase = .selecting
            for try await update in finder.search(in: sentences) {
                guard current(run) else { return }
                apply(update)
            }

            guard current(run) else { return }
            if selection == nil { selection = picks.first?.id }
            phase = picks.isEmpty ? .failed("No clips came back for that video.") : .ready
        } catch {
            guard current(run) else { return }
            if error is CancellationError {
                phase = .idle
            } else if picks.isEmpty {
                phase = .failed(reason(error))
            } else {
                if selection == nil { selection = picks.first?.id }
                phase = .ready
            }
        }
    }

    /// Selection lands in one go; the cards come back one at a time.
    private func apply(_ update: ClipSearch) {
        switch update {
        case .selected(let clips, let seconds):
            picks = clips.map { Pick($0) }
            selectionSeconds = seconds
            if selection == nil { selection = picks.first?.id }
            phase = picks.isEmpty ? .ready : .writingTitles(done: 0, total: picks.count)

        case .written(let id, let card, let seconds):
            guard let index = picks.firstIndex(where: { $0.id == id }) else { return }
            picks[index].card = card
            cardSeconds.append(seconds)
            phase = .writingTitles(done: picks.count(where: { $0.card != nil }), total: picks.count)

        case .writingFailed(let reason):
            titleProblem = reason
        }
    }

    /// Extraction is this app's step; the rest is the SDK's own progress.
    private func report(_ stage: Reader.Stage, run: Int) {
        guard current(run), isReading else { return }
        phase = switch stage {
        case .extractingAudio(let fraction): .extractingAudio(fraction)
        case .loadingSpeech(let fraction): .loadingSpeech(fraction)
        case .transcribing(let fraction): .transcribing(fraction)
        }
    }

    /// A stage can arrive after the run has moved on to finding clips, which it
    /// must not drag back to transcribing.
    private var isReading: Bool {
        switch phase {
        case .extractingAudio, .loadingSpeech, .transcribing:
            true
        case .idle, .preparingModels, .selecting, .writingTitles, .ready, .exporting, .failed:
            false
        }
    }

    private func cut(_ picks: [Pick], of source: URL, run: Int) async {
        var written: [ClipFile] = []
        do {
            for (index, pick) in picks.enumerated() {
                try Task.checkCancellation()
                guard current(run) else { return abandon(written) }
                phase = .exporting(done: index, total: picks.count)

                let name = pick.fileName(number: index + 1, of: picks.count) + ".mp4"
                // The unique part is the folder, not the file. A wrapper takes
                // its name from the URL it was made with, so a uniqued file
                // name is the name the export lands under.
                let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
                try FileManager.default.createDirectory(
                    at: folder, withIntermediateDirectories: true
                )
                let scratch = folder.appending(path: name)
                let ranges = pick.ranges(in: sentences)
                Logger.export.info("clip \(index + 1, privacy: .public) of \(picks.count, privacy: .public)")
                try await withDeadline(seconds: Cutting.allowance(for: ranges)) {
                    try await Cutting.write(source, ranges: ranges, to: scratch)
                }
                written.append(ClipFile(url: scratch, name: name))
            }

            guard current(run) else { return abandon(written) }
            finished = written
            phase = .ready
            isExporting = true
        } catch {
            guard current(run) else { return abandon(written) }
            discard(written)
            // The clips are still good; only writing them out went wrong. The
            // panel stays on screen and says so, rather than the run being
            // replaced by an error page.
            phase = .ready
            if !(error is CancellationError) {
                let problem = Problem(error)
                Logger.export.error("export failed: \(problem.detail, privacy: .public)")
                exportProblem = problem
            }
        }
    }

    /// Runs `work`, or gives up on it. `Cutting.write` throws when its task is
    /// cancelled, so a write that gets nowhere reports itself instead of
    /// leaving a progress line with nothing behind it.
    @discardableResult
    private func withDeadline<T: Sendable>(
        seconds: Int,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CuttingError.stalled(seconds: seconds)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }
}
