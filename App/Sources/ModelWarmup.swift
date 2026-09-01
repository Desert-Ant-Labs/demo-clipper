import Observation
import SwiftUI

/// Gets all three models ready before anything needs them, so the load and the
/// first compile happen at launch rather than at a dropped video.
@MainActor
@Observable
final class ModelWarmup {
    /// The three models a run waits on. Clips and Title fail separately: a
    /// machine with the selector and no card model still makes clips.
    enum Model: String, CaseIterable, Identifiable, Equatable {
        case voz = "Voz"
        case clips = "Clips"
        case title = "Title"

        var id: String { rawValue }
    }

    /// Fetching weights and getting them ready are separate waits, and the
    /// second is the long one on a first run: Core ML compiles the selector for
    /// this machine, and MLX reads the card model's weights. Neither reports a
    /// fraction, so preparing says so and counts nothing.
    enum State: Equatable {
        case idle
        case downloading(Double)
        case preparing
        case ready
        case failed(String)
    }

    /// How long each model took to be ready, for the performance sheet. A
    /// first run includes its download; every run after it is load alone.
    private(set) var loadSeconds: [Model: Double] = [:]

    private(set) var speech = State.idle
    private(set) var clips = State.idle
    private(set) var title = State.idle

    private var speechWork: Task<Void, Never>?
    private var clipsWork: Task<Void, Never>?
    private var titleWork: Task<Void, Never>?

    /// Starts all three at once. They come off the Hub independently, so a
    /// first run fetches them in parallel rather than one behind another.
    func warm() {
        warmSpeech()
        warmClips()
        warmTitle()
    }

    func state(of model: Model) -> State {
        switch model {
        case .voz: speech
        case .clips: clips
        case .title: title
        }
    }

    /// The models with something still to say: being got ready, or failed and
    /// waiting to be started again.
    ///
    /// A failure holds the warm-up rather than falling through to the drop
    /// zone. Clips that come back unnamed read as a broken app rather than as
    /// a model that did not load, and the row is where the reason and the
    /// retry are.
    var pending: [Model] {
        Model.allCases.filter { model in
            switch state(of: model) {
            case .idle, .ready: false
            case .downloading, .preparing, .failed: true
            }
        }
    }

    /// Starts a failed model over. A fetch this size fails on a dropped
    /// connection, and the answer to that is the same work again.
    func retry(_ model: Model) {
        guard case .failed = state(of: model) else { return }
        switch model {
        case .voz: speech = .idle; warmSpeech()
        case .clips: clips = .idle; warmClips()
        case .title: title = .idle; warmTitle()
        }
    }

    private func warmSpeech() {
        guard speechWork == nil else { return }
        speechWork = Task {
            await prepareSpeech()
            speechWork = nil
        }
    }

    private func prepareSpeech() async {
        speech = .preparing
        let started = Date()
        do {
            try await Models.reader.prepare { [weak self] progress in
                Task { @MainActor in self?.apply(progress) }
            }
            loadSeconds[.voz] = -started.timeIntervalSinceNow
            speech = .ready
        } catch is CancellationError {
            speech = .idle
        } catch {
            speech = .failed(reason(error))
        }
    }

    /// Fetches the selector and gets it ready. Its own task, so its download
    /// runs alongside the others rather than holding them up.
    private func warmClips() {
        guard clipsWork == nil else { return }
        let finder = Models.clipFinder
        clipsWork = Task {
            if clips != .ready {
                clips = await finder.selectionIsDownloaded() ? .preparing : .downloading(0)
            }
            let started = Date()
            do {
                try await finder.prepareSelection { fraction in
                    Task { @MainActor in
                        guard self.clips.isWorking else { return }
                        self.clips = fraction < 1 ? .downloading(fraction) : .preparing
                    }
                }
                loadSeconds[.clips] = -started.timeIntervalSinceNow
                clips = .ready
            } catch is CancellationError {
                clips = .idle
            } catch {
                clips = .failed(reason(error))
            }
            clipsWork = nil
        }
    }

    /// Fetches the card model and gets it ready, in parallel with the selector.
    /// The two used to share a task, so the card model sat at "Downloading 0%"
    /// until the selector had finished downloading and preparing.
    private func warmTitle() {
        guard titleWork == nil else { return }
        let finder = Models.clipFinder
        titleWork = Task {
            if title != .ready {
                title = await finder.titlesAreDownloaded() ? .preparing : .downloading(0)
            }
            let started = Date()
            do {
                try await finder.prepareTitles { fraction in
                    Task { @MainActor in
                        guard self.title.isWorking else { return }
                        self.title = fraction < 1 ? .downloading(fraction) : .preparing
                    }
                }
                loadSeconds[.title] = -started.timeIntervalSinceNow
                title = .ready
            } catch is CancellationError {
                title = .idle
            } catch {
                title = .failed(reason(error))
            }
            titleWork = nil
        }
    }

    private func apply(_ progress: Speech.Progress) {
        guard speech != .ready else { return }
        switch progress {
        case .loading(let fraction):
            speech = fraction < 1 ? .downloading(fraction) : .preparing
        case .reading:
            break
        }
    }
}

extension ModelWarmup.State {
    var isWorking: Bool {
        switch self {
        case .downloading, .preparing: true
        case .idle, .ready, .failed: false
        }
    }
}
