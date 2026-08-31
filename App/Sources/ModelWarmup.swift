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
    private var modelWork: Task<Void, Never>?

    /// Starts all three. Each model has one build, so each is loaded once.
    func warm() {
        warmSpeech()
        warmClipModels()
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
        case .voz:
            speech = .idle
            warmSpeech()
        case .clips:
            clips = .idle
            warmClipModels()
        case .title:
            // Said before the task starts, so the row does not show a
            // checkmark in the moment between the two.
            title = .preparing
            warmClipModels()
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

    /// The selector goes first, since a run needs it first. The card model
    /// reports its fetch, then nothing while MLX reads its weights.
    private func warmClipModels() {
        guard modelWork == nil else { return }
        let finder = Models.clipFinder
        modelWork = Task {
            if title != .ready {
                title = await finder.titlesAreDownloaded() ? .preparing : .downloading(0)
            }
            // A model already on disk goes straight to preparing, so the row
            // does not claim a download that will not happen.
            if clips != .ready {
                clips = await finder.selectionIsDownloaded() ? .preparing : .downloading(0)
            }
            let selectionStarted = Date()
            do {
                try await finder.prepareSelection { fraction in
                    // The callback hops onto the main actor, so it can land
                    // after the load it belongs to finished.
                    Task { @MainActor in
                        guard self.clips.isWorking else { return }
                        self.clips = fraction < 1 ? .downloading(fraction) : .preparing
                    }
                }
                loadSeconds[.clips] = -selectionStarted.timeIntervalSinceNow
                clips = .ready
            } catch is CancellationError {
                clips = .idle
            } catch {
                clips = .failed(reason(error))
            }

            let titleStarted = Date()
            do {
                try await finder.prepareTitles { fraction in
                    Task { @MainActor in
                        guard self.title.isWorking else { return }
                        self.title = fraction < 1 ? .downloading(fraction) : .preparing
                    }
                }
                loadSeconds[.title] = -titleStarted.timeIntervalSinceNow
                title = .ready
            } catch is CancellationError {
                title = .idle
            } catch {
                // Not fatal. Clips without titles are a worse result, not a
                // failed one, so this is said once and the app carries on.
                title = .failed(reason(error))
            }
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
