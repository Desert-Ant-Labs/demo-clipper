import DesertAntUI
import SwiftUI

// A first launch fetches 1GB of weights. Offering a drop zone during that only
// leads to a video sitting in the same queue.
struct WarmupView: View {
    @Environment(ModelWarmup.self) private var warmup

    var body: some View {
        VStack(spacing: 20) {
            DA.Loader(.fillSpiral)
                .frame(width: 40)
            StepPanel(width: 320) {
                ForEach(ModelWarmup.Model.allCases) { model in
                    StepRow(
                        title: "\(model.rawValue) model",
                        phase: phase(of: model),
                        progress: progress(of: model),
                        state: state(of: model)
                    )
                }
            }
            .animation(.easeOut(duration: 0.2), value: warmup.pending)
            Text("Fetching the models and getting them ready. This happens once.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func state(of model: ModelWarmup.Model) -> StepRow.State {
        switch warmup.state(of: model) {
        case .ready, .idle: .done
        case .downloading, .preparing: .running
        case .failed: .waiting
        }
    }

    /// Fetching and getting ready are different waits, and on a machine that
    /// already has the weights only the second one happens.
    private func phase(of model: ModelWarmup.Model) -> String? {
        switch warmup.state(of: model) {
        case .downloading: "Downloading"
        case .preparing: "Preparing"
        case .failed(let reason): reason
        case .idle, .ready: nil
        }
    }

    /// Only a fetch reports a fraction. Preparing is Core ML compiling for this
    /// machine and MLX reading weights, neither of which counts anything.
    private func progress(of model: ModelWarmup.Model) -> Double? {
        if case .downloading(let fraction) = warmup.state(of: model) { fraction } else { nil }
    }
}
