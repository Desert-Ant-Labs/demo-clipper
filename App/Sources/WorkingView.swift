import DesertAntUI
import SwiftUI

// One bar across the whole run would need weights per step, and the honest
// weights change with the video. Steps need none.
struct WorkingView: View {
    @Environment(ClipperModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            DA.Loader(.fillSpiral)
                .frame(width: 40)

            StepPanel(width: 300) {
                ForEach(Step.allCases, id: \.self) { step in
                    StepRow(
                        title: step.title,
                        phase: phase(of: step),
                        progress: progress(of: step),
                        state: state(of: step)
                    )
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.phase)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func state(of step: Step) -> StepRow.State {
        guard let current = Step(model.phase) else { return .waiting }
        if step == current { return .running }
        return step.rawValue < current.rawValue ? .done : .waiting
    }

    /// Fetching a model and getting it ready are named apart: the first is a
    /// measured wait and the second counts nothing.
    private func phase(of step: Step) -> String? {
        guard state(of: step) == .running else { return nil }
        return switch model.phase {
        case .loadingSpeech(let fraction):
            fraction < 1 ? "Downloading" : "Preparing"
        case .preparingModels:
            "Preparing"
        case .extractingAudio, .transcribing, .selecting,
             .writingTitles, .idle, .ready, .exporting, .failed:
            nil
        }
    }

    /// A step that cannot count shows no bar.
    private func progress(of step: Step) -> Double? {
        guard state(of: step) == .running else { return nil }
        return switch model.phase {
        case .extractingAudio(let fraction):
            fraction > 0 ? fraction : nil
        case .transcribing(let fraction):
            fraction > 0 ? fraction : nil
        case .loadingSpeech(let fraction):
            fraction < 1 ? fraction : nil
        case .preparingModels, .selecting,
             .writingTitles, .idle, .ready, .exporting, .failed:
            nil
        }
    }
}

// Writing titles is not a step: by then the clips are on screen and this panel
// is gone.
private enum Step: Int, CaseIterable {
    case audio, transcript, clips

    init?(_ phase: ClipperModel.Phase) {
        switch phase {
        case .extractingAudio:
            self = .audio
        case .loadingSpeech, .transcribing:
            self = .transcript
        case .preparingModels, .selecting:
            self = .clips
        case .writingTitles, .idle, .ready, .exporting, .failed:
            return nil
        }
    }

    var title: String {
        switch self {
        case .audio: "Extracting audio"
        case .transcript: "Transcribing"
        case .clips: "Generating clips"
        }
    }
}

#Preview {
    WorkingView()
        .environment(ClipperModel())
        .frame(width: 640, height: 480)
}
