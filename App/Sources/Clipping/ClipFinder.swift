import Clips
import Foundation
import Title
import Transcript

/// Why a search could not produce clips.
enum ClipSearchError: LocalizedError {
    case modelUnavailable(String)
    case searchFailed(String)
    case writingFailed(String)
    case tooShort(sentences: Int)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            "The clip model could not be loaded. \(reason)"
        case .searchFailed(let reason):
            "The clip model could not read that transcript. \(reason)"
        case .writingFailed(let reason):
            "The clips have no titles. \(reason)"
        case .tooShort(let sentences):
            "There is not enough said in that video to clip. It has "
                + "\(sentences) \(sentences == 1 ? "sentence" : "sentences"), and a clip "
                + "needs at least \(ClipFinder.minimumSentences)."
        }
    }
}

/// What the search reports as it runs.
///
/// Selection returns every clip at once. The cards land one at a time after it,
/// so a clip is playable and exportable before it has a name.
enum ClipSearch: Sendable {
    /// The clips, unnamed, and how long the selector took over all of them.
    case selected([Clip], seconds: Double)
    /// One clip has been named.
    case written(id: Clip.ID, card: Card, seconds: Double)
    /// No cards will arrive. The clips already reported still stand.
    case writingFailed(reason: String)
}

/// Picks the clips worth posting out of a transcript, and names them, both on
/// device.
///
/// Driven a stage at a time so clips reach the screen before their cards exist.
actor ClipFinder {
    private let clips: Clips
    private var writer: Titles?

    /// Where the models were found, for anything that wants to say so.
    nonisolated let locations: ModelLocations

    /// Whether this finder should name its clips at all. Its own flag rather
    /// than a missing ``ModelLocations/title``, since no directory means fetch
    /// the weights, and asking for unnamed clips must not start a download.
    nonisolated let namesClips: Bool

    init(models: ModelLocations = .resolved, namesClips: Bool = true) {
        self.locations = models
        self.namesClips = namesClips
        self.clips = Clips(directory: models.clips?.path(percentEncoded: false))
    }

    /// Loads both models, so the wait is not inside ``search(in:count:)``. A
    /// writer that will not load is not fatal: the clips come back unnamed.
    func prepare() async throws {
        try await prepareSelection()
        if namesClips { try? await prepareTitles() }
    }

    /// Whether the selector's weights are already on this machine, so a
    /// warm-up can say whether it is fetching or getting them ready.
    func selectionIsDownloaded() -> Bool {
        clips.isDownloaded()
    }

    /// Loads the selector on its own, for a warm-up that reports the two
    /// models apart.
    func prepareSelection(
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws {
        do {
            try await clips.download(progress: progress)
        } catch {
            throw ClipSearchError.modelUnavailable(Self.explain(error, at: locations.clips))
        }
    }

    /// Whether the card model's weights are already on this machine.
    func titlesAreDownloaded() -> Bool {
        !namesClips || locations.title != nil || TitleModel.isAvailable()
    }

    /// Loads the writer on its own. MLX reads the weights here.
    ///
    /// A directory of our own is adopted as it stands. Without one the weights
    /// come off the Hub into the managed cache, the same fetch `Clips` and
    /// `Voz` make, so a downloaded build names its clips without being handed
    /// a model first.
    func prepareTitles(
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws {
        guard writer == nil else { return }
        guard namesClips else {
            throw ClipSearchError.modelUnavailable("Titles were not asked for.")
        }
        guard Self.metalKernelsArePresent else {
            throw ClipSearchError.modelUnavailable(
                "MLX has no compiled Metal kernels here, so the card model cannot run. "
                    + "SwiftPM on the command line cannot build them, which is mlx-swift's "
                    + "own documented limitation. Build with `mise run build` instead, or "
                    + "pass --no-titles to pick clips without naming them.")
        }
        let directory: URL
        if let local = locations.title {
            let missing = ModelLocations.missing(ModelLocations.titleFiles, in: local)
            guard missing.isEmpty else {
                throw ClipSearchError.modelUnavailable(
                    "\(local.path(percentEncoded: false)) is missing "
                        + missing.joined(separator: ", ") + ".")
            }
            directory = local
        } else {
            do {
                let stored = try await TitleModel.resolve { progress($0.fraction) }
                directory = URL(filePath: stored.rootPath)
            } catch {
                throw ClipSearchError.modelUnavailable(reason(error))
            }
        }
        do {
            writer = try await Titles(directory: directory)
        } catch {
            throw ClipSearchError.modelUnavailable(reason(error))
        }
    }

    /// Whether this run will name its clips. MLX needs its compiled kernels,
    /// which a SwiftPM command-line build does not produce.
    nonisolated var writesTitles: Bool { namesClips && Self.metalKernelsArePresent }

    /// Searches for clips, reporting each stage as it finishes.
    ///
    /// - Parameters:
    ///   - sentences: The transcript to search.
    ///   - count: Keeps this many of the ranked clips. `nil` takes every clip
    ///     the model offers.
    nonisolated func search(
        in sentences: [Sentence],
        count: Int? = nil
    ) -> AsyncThrowingStream<ClipSearch, any Error> {
        AsyncThrowingStream<ClipSearch, any Error> { continuation in
            let search = Task {
                do {
                    try await run(
                        in: sentences,
                        count: count,
                        report: { continuation.yield($0) }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in search.cancel() }
        }
    }

    /// A Short is five to nine sentences.
    static let minimumSentences = 5

    private func run(
        in sentences: [Sentence],
        count: Int?,
        report: @escaping @Sendable (ClipSearch) -> Void
    ) async throws {
        guard sentences.count >= Self.minimumSentences else {
            throw ClipSearchError.tooShort(sentences: sentences.count)
        }

        let started = Date()
        let clips: [Clip]
        do {
            clips = try await self.clips.clips(in: sentences.map(\.text), limit: count)
        } catch {
            throw ClipSearchError.searchFailed(Self.explain(error, at: locations.clips))
        }
        try Task.checkCancellation()
        report(.selected(clips, seconds: -started.timeIntervalSinceNow))
        guard !clips.isEmpty else { return }

        guard namesClips else { return }
        do {
            try await prepareTitles()
        } catch {
            report(.writingFailed(reason: reason(error)))
            return
        }
        guard let writer else { return }

        // Sequential: two generations at once on one GPU are slower than one
        // after the other.
        for clip in clips {
            try Task.checkCancellation()
            let started = Date()
            do {
                let card = try await writer.card(for: clip)
                // An empty card is how the writer reports producing nothing.
                guard !card.isEmpty else { continue }
                report(.written(id: clip.id, card: card, seconds: -started.timeIntervalSinceNow))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Same model and same call for every clip, so one failure is
                // all of them.
                report(.writingFailed(reason: reason(error)))
                return
            }
        }
    }

    /// Names the missing file rather than passing on the SDK's word for it.
    ///
    /// `ModelStoreError` is not `LocalizedError`, so `localizedDescription` on
    /// one is Foundation's "operation couldn't be completed".
    private static func explain(_ error: any Error, at directory: URL?) -> String {
        if let directory {
            let missing = ModelLocations.missing(ModelLocations.clipsFiles, in: directory)
            if !missing.isEmpty {
                return "\(directory.path(percentEncoded: false)) is missing "
                    + missing.joined(separator: ", ")
                    + ". Run `mise run models` to install it."
            }
        } else {
            return "No clip model directory was found. Run `mise run models`, "
                + "or set CLIPPER_CLIPS_MODEL to one."
        }
        return reason(error)
    }

    /// Where MLX keeps its compiled Metal kernels, relative to the executable.
    private static let metalLibrary =
        "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"

    /// True when MLX can find its kernels.
    ///
    /// Checked before loading: MLX prints `Failed to load the default metallib`
    /// and aborts the process rather than throwing. SwiftPM on the command line
    /// cannot build the shaders, so only an Xcode build has them.
    private static var metalKernelsArePresent: Bool {
        let roots = [
            Bundle.main.resourceURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
            Bundle.main.bundleURL,
        ].compactMap { $0 }
        return roots.contains {
            FileManager.default.fileExists(
                atPath: $0.appending(path: metalLibrary).path(percentEncoded: false))
        }
    }
}
