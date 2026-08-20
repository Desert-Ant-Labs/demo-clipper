import DesertAntUI
import SwiftUI

// A first launch fetches a couple of GB of weights. Offering a drop zone
// during that only leads to a video sitting in the same queue.
struct WarmupView: View {
    @Environment(ModelWarmup.self) private var warmup

    var body: some View {
        VStack(spacing: 20) {
            DA.Loader(.fillSpiral)
                .frame(width: 40)
            StepPanel(width: 320) {
                ForEach(ModelWarmup.Model.allCases) { model in
                    StepRow(
                        title: title(for: model),
                        detail: detail(for: model),
                        state: state(of: model)
                    )
                }
            }
            .animation(.easeOut(duration: 0.2), value: warmup.pending)
            Text("Preparing the models. This happens once.")
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
    private func title(for model: ModelWarmup.Model) -> String {
        switch warmup.state(of: model) {
        case .downloading: "Downloading \(model.rawValue) model"
        case .preparing: "Preparing \(model.rawValue) model"
        case .idle, .ready, .failed: "\(model.rawValue) model"
        }
    }

    private func detail(for model: ModelWarmup.Model) -> String? {
        switch warmup.state(of: model) {
        case .downloading(let fraction):
            fraction > 0 ? "\(Int(fraction * 100))%" : nil
        case .failed(let reason):
            reason
        case .idle, .preparing, .ready:
            nil
        }
    }
}
